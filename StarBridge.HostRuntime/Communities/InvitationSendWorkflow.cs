using StarBridge.Core.Chat;

namespace StarBridge.HostRuntime.Communities;

internal sealed record InvitationSendProgress(string OperationId, string Status, string? Error = null) { public int SchemaVersion => 1; }

// Uses the same journal and immutable requests for both destinations. No automatic restart sends.
internal sealed class InvitationSendWorkflow(InvitationOutboxJournal journal)
{
    internal Task<InvitationOutboxItem[]> ReadAsync(string accountKey) => journal.RunAsync(accountKey, session => Task.FromResult(session.Items));

    internal Task<InvitationSendProgress> ExecuteAsync(string accountKey, InvitationOutboxItem original, string action,
        Func<InvitationOutboxItem, Task<InvitationGenerationResult>> generate,
        Func<InvitationOutboxItem, InvitationDeliveryIntent, bool, Task<InvitationDeliveryResult>> deliver, Action current,
        bool generationRetrySafe = true, bool deliveryConfirmationSupported = true)
    {
        if (action is not ("advance" or "check" or "retryDelivery")) throw new ArgumentException("Invalid invitation workflow action.");
        return journal.RunAsync(accountKey, async session =>
        {
            current();
            var state = session.Find(original.Id);
            if (state is null)
            {
                if (action != "advance" || original.Phase != "prepared" || original.Generation is not null || original.Delivery is not null || original.Card is not null)
                    return new InvitationSendProgress(original.Id, "unknown", "notFound");
                await session.SaveAsync(original);
                state = original;
            }
            else if ((state with { Phase = original.Phase, Generation = original.Generation, Delivery = original.Delivery, Card = original.Card }) != original)
                return new InvitationSendProgress(original.Id, "rejected", "intentChanged");
            if (state.Phase == "sent") return new InvitationSendProgress(state.Id, "sent");
            if (state.Phase is "prepared" or "generating")
            {
                if (state.Phase == "generating" && !generationRetrySafe)
                    return new InvitationSendProgress(state.Id, "unknown", "generationPending");
                if (action != "advance") return new InvitationSendProgress(state.Id, state.Phase == "prepared" ? "pending" : "unknown", "generationPending");
                state = state with { Phase = "generating" };
                await session.SaveAsync(state); // Must be durable before the first possible remote write.
                current();
                var generated = await generate(state);
                current();
                if (generated.Status != "accepted")
                {
                    if (!generationRetrySafe && generated.Status == "rejected")
                    {
                        state = state with { Phase = "prepared" };
                        await session.SaveAsync(state);
                    }
                    return new InvitationSendProgress(state.Id, generated.Status, generated.Error);
                }
                state = state with { Phase = "ready", Generation = generated,
                    Card = new ChatAttachmentContract(ChatAttachmentKinds.FleetInvitation, "组织邀请", "加入组织",
                        FleetInviteCode: generated.Code, ExpiresAt: generated.ExpiresAt) };
                await session.SaveAsync(state); // Never deliver a code that was not saved locally.
            }
            if (state.Phase == "ready" && action == "check") return new InvitationSendProgress(state.Id, "pending", "deliveryPending");
            // Preserve the exact original payload even if a later client changes its card wording.
            var intent = new InvitationDeliveryIntent(state.DeliveryId, state.RequestedAt, state.Card!);
            var wasUncertain = state.Phase == "sending";
            if (state.Phase == "sending")
            {
                if (!deliveryConfirmationSupported)
                    return new InvitationSendProgress(state.Id, "unknown", "outcomeUnknown");
                current();
                var confirmed = await deliver(state, intent, true);
                current();
                if (confirmed.Status == "sent") return await Finish(confirmed);
                // Explicit retry is separate from opening/restoring/checking the pending operation.
                // It retains the exact request id/time/card; the server rejects expired first-send intents.
                if (action != "retryDelivery" || confirmed.Error != "outcomeUnknown")
                    return new InvitationSendProgress(state.Id, "unknown", confirmed.Error);
            }
            state = state with { Phase = "sending" };
            await session.SaveAsync(state);
            current();
            var delivered = await deliver(state, intent, false);
            current();
            if (delivered.Status == "sent") return await Finish(delivered);
            // An explicit first-send rejection can resume, but an uncertain response remains frozen.
            if (delivered.Status == "rejected" && !wasUncertain)
            {
                state = state with { Phase = "ready", Delivery = delivered };
                await session.SaveAsync(state);
            }
            return new InvitationSendProgress(state.Id, wasUncertain ? "unknown" : delivered.Status, delivered.Error);

            async Task<InvitationSendProgress> Finish(InvitationDeliveryResult receipt)
            {
                state = state with { Phase = "sent", Delivery = receipt };
                await session.SaveAsync(state);
                return new(state.Id, "sent");
            }
        });
    }
}
