using System.Net;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using StarBridge.HostRuntime.Communities;

internal static class InvitationSendWorkflowTests
{
    internal static async Task Verify()
    {
        var root = Path.Combine(Path.GetTempPath(), "StarBridge-invitation-outbox-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        await Restart(Path.Combine(root, "restart-private"), "private");
        await Restart(Path.Combine(root, "restart-room"), "room");
        await Failures(Path.Combine(root, "failures"));
        await Isolation(Path.Combine(root, "isolation"));
    }

    private static InvitationOutboxItem Intent() => new(Guid.NewGuid().ToString("N"), "A", "private", "recipient",
        "https://community.invalid", DateTimeOffset.UtcNow, 1, Guid.NewGuid().ToString("N"), "prepared");
    private static InvitationGenerationResult Generated() => new("accepted", InviteId: new string('a', 32), Code: "INVITE-SECRET", ExpiresAt: DateTimeOffset.UtcNow.AddDays(7));
    private static InvitationDeliveryResult Sent(InvitationOutboxItem item) => new("sent", MessageId: item.DeliveryId, Sequence: 9, CreatedAt: DateTimeOffset.UtcNow);

    private static async Task Restart(string root, string channel)
    {
        var journal = new InvitationOutboxJournal(root);
        using var handler = new Handler();
        var origin = new Uri("https://community.invalid");
        var id = Guid.NewGuid().ToString("N");
        var destinationId = channel == "private" ? "recipient" : "room-one";
        using (var first = new CommunityClient(origin, handler, invitationJournal: journal))
        {
            var source = (await first.ReadAsync("bearer", new("mine", "", null, null), "session:1", default)).Items.Single().TargetRef;
            var result = await first.AdvanceInvitationSendAsync("bearer", "environment:owner", id, source,
                new(channel, destinationId, "session:1", origin), 1, "advance", "session:1", () => { }, default);
            Check(result.Status == "unknown" && handler.Generations == 1 && handler.Sends == 1, "initial lost send leaves durable uncertain operation");
        }
        var loaded = await new InvitationSendWorkflow(new(root)).ReadAsync("environment:owner");
        Check(loaded.Single().Phase == "sending" && loaded[0].Generation!.Code == "INVITE-SECRET", "actual encrypted file reload restores generated card and original phase");
        var bytes = await File.ReadAllBytesAsync(Directory.GetFiles(root, "*.dat").Single());
        Check(!Encoding.UTF8.GetString(bytes).Contains("INVITE-SECRET") && !Encoding.UTF8.GetString(bytes).Contains(destinationId), "disk does not contain plaintext code or target");
        Check((await new InvitationSendWorkflow(new(root)).ReadAsync("environment:other")).Length == 0, "another account cannot list the operation");
        // New Host/client, fresh UI references and session generation, same stable account partition.
        using var recovered = new CommunityClient(origin, handler, invitationJournal: new(root));
        var rebound = (await recovered.ReadAsync("bearer", new("mine", "", null, null), "session:2", default)).Items.Single().TargetRef;
        var target = new InvitationDeliveryTarget(channel, destinationId, "session:2", origin);
        Check((await recovered.AdvanceInvitationSendAsync("bearer", "environment:owner", id, rebound,
            target with { Id = "changed" }, 1, "check", "session:2", () => { }, default)).Error == "intentChanged", "restart cannot rebind to a different recipient");
        var confirmed = await recovered.AdvanceInvitationSendAsync("bearer", "environment:owner", id, rebound,
            target, 1, "check", "session:2", () => { }, default);
        Check(confirmed.Status == "sent" && handler.Generations == 1 && handler.Sends == 1 && handler.Confirms == 1, "restart confirms without generating or sending again");
        Check((await new InvitationSendWorkflow(new(root)).ReadAsync("environment:owner")).Single().Phase == "sent", "confirmed final phase survives another reload");
        Check((await recovered.AdvanceInvitationSendAsync("bearer", "environment:owner", id, rebound,
            target, 1, "advance", "session:2", () => { }, default)).Status == "sent" && handler.Confirms == 1, "finished operation never makes another POST");
    }

    private static async Task Failures(string root)
    {
        foreach (var point in new[] { "before-generation", "after-generation", "after-delivery" })
        {
            var folder = Path.Combine(root, point);
            var journal = new InvitationOutboxJournal(folder);
            var workflow = new InvitationSendWorkflow(journal);
            var intent = Intent();
            await journal.RunAsync("owner", async session => { await session.SaveAsync(intent); return 0; });
            var path = Directory.GetFiles(folder, "*.dat").Single();
            FileStream? held = point == "before-generation" ? Hold() : null;
            var generations = 0; var writes = 0; var confirms = 0;
            var receipt = Generated();
            async Task<InvitationGenerationResult> Generate(InvitationOutboxItem state)
            {
                generations++;
                Check(state.Id == intent.Id && state.RequestedAt == intent.RequestedAt, "generation always uses original request");
                if (point == "after-generation" && generations == 1) held = Hold();
                await Task.CompletedTask;
                return receipt;
            }
            Task<InvitationDeliveryResult> Deliver(InvitationOutboxItem state, InvitationDeliveryIntent request, bool confirm)
            {
                if (confirm) confirms++; else writes++;
                Check(request.RequestId == intent.DeliveryId && request.RequestedAt == intent.RequestedAt, "delivery always uses original request");
                if (point == "after-delivery" && writes == 1 && !confirm) held = Hold();
                return Task.FromResult(Sent(state));
            }
            try
            {
                await workflow.ExecuteAsync("owner", intent, "advance", Generate, Deliver, () => { });
                throw new InvalidOperationException("Expected final replacement to fail.");
            }
            catch (IOException) { }
            catch (UnauthorizedAccessException) { }
            finally { held?.Dispose(); }
            var saved = (await new InvitationSendWorkflow(new(folder)).ReadAsync("owner")).Single();
            Check(saved.Phase == (point == "before-generation" ? "prepared" : point == "after-generation" ? "generating" : "sending"), "failed replacement preserves previous durable phase: " + point);
            Check(point != "before-generation" || generations == 0 && writes == 0, "no online request before durable intent");
            Check(point != "after-generation" || writes == 0, "no delivery before locally saved generation receipt");
            var restored = new InvitationSendWorkflow(new(folder));
            var result = await restored.ExecuteAsync("owner", intent, point == "after-delivery" ? "check" : "advance", Generate, Deliver, () => { });
            Check(result.Status == "sent" && writes == 1 && (point != "after-delivery" || confirms == 1 && generations == 1), "recovery commits without duplicate delivery: " + point);
            FileStream Hold() => new(path, FileMode.Open, FileAccess.Read, FileShare.Read);
        }
    }

    private static async Task Isolation(string root)
    {
        var journal = new InvitationOutboxJournal(root);
        var workflow = new InvitationSendWorkflow(journal);
        var intent = Intent();
        var receipt = Generated();
        var writes = 0;
        Task<InvitationGenerationResult> Generate(InvitationOutboxItem _) => Task.FromResult(receipt);
        Task<InvitationDeliveryResult> Deliver(InvitationOutboxItem _, InvitationDeliveryIntent request, bool confirm)
        {
            if (!confirm) writes++;
            return Task.FromResult(new InvitationDeliveryResult("unknown", "outcomeUnknown"));
        }
        Check((await workflow.ExecuteAsync("owner", intent, "check", Generate, Deliver, () => { })).Status == "unknown" && writes == 0, "checking unknown ID cannot create or send");
        await workflow.ExecuteAsync("owner", intent, "advance", Generate, Deliver, () => { });
        await workflow.ExecuteAsync("owner", intent, "advance", Generate, Deliver, () => { });
        Check(writes == 1, "ordinary continuation of uncertain delivery only confirms");
        await workflow.ExecuteAsync("owner", intent, "retryDelivery", Generate, Deliver, () => { });
        Check(writes == 2, "only distinct deliberate retry can resubmit exact original delivery");
        await journal.RunAsync("owner", async session =>
        {
            var original = session.Find(intent.Id)!;
            try { await session.SaveAsync(original with { Generation = receipt with { Code = "OTHER-CODE" } }); throw new InvalidOperationException("Expected frozen code rejection."); }
            catch (InvalidDataException) { }
            try { await session.SaveAsync(original with { Card = original.Card! with { Title = "Changed by newer client" } }); throw new InvalidOperationException("Expected frozen attachment rejection."); }
            catch (InvalidDataException) { }
            return 0;
        });
        var entered = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var release = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var running = journal.RunAsync("owner", async _ => { entered.SetResult(); await release.Task; return 0; });
        await entered.Task;
        try { await new InvitationOutboxJournal(root).RunAsync("owner", _ => Task.FromResult(0)); throw new InvalidOperationException("Expected cross-instance lock refusal."); }
        catch (IOException) { }
        finally { release.SetResult(); await running; }
        var file = Directory.GetFiles(root, "*.dat").Single();
        var bad = new byte[] { 1, 2, 3, 4 };
        await File.WriteAllBytesAsync(file, bad); // Synthetic fixture only.
        try { await workflow.ReadAsync("owner"); throw new InvalidOperationException("Expected corruption rejection."); }
        catch (CryptographicException) { }
        Check((await File.ReadAllBytesAsync(file)).SequenceEqual(bad), "corrupt journal is not silently reset or overwritten");
    }

    private sealed class Handler : HttpMessageHandler
    {
        internal int Generations, Sends, Confirms;
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            if (request.Method == HttpMethod.Get && request.RequestUri!.AbsolutePath == "/api/fleets/directory")
                return Reply(new { schemaVersion = 1, membershipModelVersion = 2, view = "mine", query = "", next = (string?)null,
                    items = new[] { new { code = "A", name = "Organization", description = "", language = "", activeTime = "", memberCount = 1,
                        relationship = "member", joinMode = "direct", actions = Array.Empty<string>() } } });
            if (request.Method == HttpMethod.Get && request.RequestUri!.AbsolutePath == "/api/fleets/workspace")
                return Reply(new { schemaVersion = 1, membershipModelVersion = 2, code = "A", query = "", offset = 0,
                    totalCount = 1, matchedCount = 1, next = (int?)null,
                    members = new[] { new { memberId = "account:owner" } } });
            if (request.Method == HttpMethod.Get)
                return Reply(new { schemaVersion = 1, membershipModelVersion = 2, code = "A", section = "access", inviteGenerationVersion = 1,
                    inviteDeliveryVersion = 1, access = new { canSendInvitationCard = true } });
            using var body = JsonDocument.Parse(await request.Content!.ReadAsStringAsync(token));
            if (request.RequestUri!.AbsolutePath == "/api/fleets/invites")
            {
                Generations++;
                return Reply(new { schemaVersion = 1, status = "accepted", requestId = body.RootElement.GetProperty("clientRequestId").GetString(),
                    inviteId = new string('a', 32), code = "INVITE-SECRET", expiresAt = DateTimeOffset.UtcNow.AddDays(7) });
            }
            Check(request.RequestUri.PathAndQuery is "/api/friends/chat/messages?view=client" or "/api/party-rooms/chat?view=client", "workflow fixes destination route");
            var id = body.RootElement.GetProperty("clientMessageId").GetString();
            if (!body.RootElement.GetProperty("confirmOnly").GetBoolean()) { Sends++; throw new HttpRequestException("Reply lost after commit"); }
            Confirms++;
            return Reply(new { schemaVersion = 1, status = "sent", requestId = id,
                messageId = body.RootElement.TryGetProperty("roomId", out _) ? new string('d', 32) : id, sequence = 9, createdAt = DateTimeOffset.UtcNow });
        }
        // The fixture spans two real CommunityClient lifetimes.
        protected override void Dispose(bool disposing) { }
        private static HttpResponseMessage Reply(object value) => new(HttpStatusCode.OK) { Content = JsonContent.Create(value) };
    }
    private static void Check(bool value, string message) { if (!value) throw new InvalidOperationException(message); }
}
