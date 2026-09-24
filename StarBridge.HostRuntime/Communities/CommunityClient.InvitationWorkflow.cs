using System.Security.Cryptography;
using System.Text;

namespace StarBridge.HostRuntime.Communities;

internal sealed partial class CommunityClient
{
    internal async Task<InvitationOutboxView> ReadInvitationOutboxAsync(string accountKey)
    {
        var items = await _invitationWorkflow.Value.ReadAsync(accountKey);
        return new(items.OrderByDescending(item => item.RequestedAt).Select(item => new InvitationOutboxRow(
            item.Id, item.Channel, item.Phase, item.SourceName, item.DestinationName, item.RequestedAt, item.MaxUses)).ToArray());
    }
    internal async Task<InvitationOutboxItem?> FindInvitationOperationAsync(string accountKey, string operationId) =>
        (await _invitationWorkflow.Value.ReadAsync(accountKey)).SingleOrDefault(item => item.Id == operationId);

    internal async Task<string> RebindInvitationSourceAsync(string bearer, InvitationOutboxItem item, string scope,
        Action current, CancellationToken token)
    {
        if (item.Origin != _origin.GetLeftPart(UriPartial.Authority)) throw Invalid();
        current();
        var root = await WorkspaceJson(bearer, "/api/fleets/directory?view=mine&q=&code=" + Uri.EscapeDataString(item.SourceCode), token);
        current();
        var page = Project(root, new("mine", "", null, null), scope, item.SourceCode);
        var source = page.Items.SingleOrDefault();
        if (source is null || source.Relationship is not ("member" or "owner")) throw Invalid();
        return source.TargetRef;
    }
    // accountKey is the stable environment + SCM subject partition, never a bearer or transient generation.
    // Caller must re-resolve both source and destination for the current authenticated session.
    internal async Task<InvitationSendProgress> AdvanceInvitationSendAsync(string bearer, string accountKey,
        string operationId, string organizationRef, InvitationDeliveryTarget destination, int maxUses, string action,
        string scope, Action current, CancellationToken token)
    {
        if (!InvitationOutboxJournal.IsId(operationId) || maxUses is < 1 or > 50
            || destination.Scope != scope || action is not ("advance" or "check" or "retryDelivery"))
            return new(operationId, "rejected", "dataInvalid");
        current();
        var source = Resolve(organizationRef, scope);
        var code = source.Code;
        var origin = _origin.GetLeftPart(UriPartial.Authority);
        if (destination.Origin.GetLeftPart(UriPartial.Authority) != origin) return new(operationId, "rejected", "dataInvalid");
        var pending = (await _invitationWorkflow.Value.ReadAsync(accountKey)).SingleOrDefault(item => item.Id == operationId);
        current();
        if (pending is not null && (pending.SourceCode != code || pending.Channel != destination.Channel
            || pending.DestinationId != destination.Id || pending.Origin != origin || pending.MaxUses != maxUses))
            return new(operationId, "rejected", "intentChanged");
        if (pending is null && action != "advance") return new(operationId, "unknown", "notFound");
        if (pending is null && destination.Channel == "private")
        {
            if (maxUses != 1) return new(operationId, "rejected", "dataInvalid");
            if (await IsPrivateRecipientInOrganizationAsync(bearer, code, destination.Id, current, token))
                return new(operationId, "rejected", "notAllowed");
        }
        // Optional recipient-preview work is not a prerequisite for the WPF-compatible send path.
        if (action == "advance" && (pending is null || pending.Phase is "prepared" or "generating"))
        {
            // Do not generate/replace a code on a server that cannot safely deliver the resulting card.
            var access = await WorkspaceJson(bearer,
                $"/api/fleets/admissions?code={Uri.EscapeDataString(code)}&section=access&offset=0", token, 16 * 1024);
            current();
            if (Number(access, "schemaVersion", 1, 1) != 1 || Number(access, "membershipModelVersion", 2, 2) != 2
                || Text(access, "code", 256) != code || Text(access, "section", 16) != "access") throw Invalid();
            if (!access.TryGetProperty("inviteGenerationVersion", out var generationVersion) || generationVersion.GetInt32() != 1
                || !access.TryGetProperty("inviteDeliveryVersion", out var deliveryVersion) || deliveryVersion.GetInt32() != 1)
                return new(operationId, "rejected", "unavailable");
        }
        var original = pending ?? new InvitationOutboxItem(operationId, code, destination.Channel, destination.Id, origin,
            DateTimeOffset.UtcNow, maxUses,
            Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes("invitation-delivery:" + operationId)))[..32].ToLowerInvariant(), "prepared",
            SourceName: source.Name, DestinationName: destination.DisplayName);
        return await _invitationWorkflow.Value.ExecuteAsync(accountKey, original, action,
            state => GenerateInvitationCardAsync(bearer, new(organizationRef, state.Id, state.RequestedAt, state.MaxUses), scope, current, token),
            (_, intent, confirm) => DeliverInvitationCardAsync(bearer, organizationRef, destination, intent, confirm, scope, current, token),
            () => { token.ThrowIfCancellationRequested(); current(); });
    }

    // WPF excludes existing members. Reuse the authorized workspace roster;
    // stable account IDs stay inside Host and no new backend route is needed.
    private async Task<bool> IsPrivateRecipientInOrganizationAsync(string bearer, string code,
        string recipient, Action current, CancellationToken token)
    {
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token);
        deadline.CancelAfter(TimeSpan.FromSeconds(12));
        var offset = 0;
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        while (true)
        {
            var page = await WorkspaceJson(bearer,
                $"/api/fleets/workspace?code={Uri.EscapeDataString(code)}&q=&offset={offset}", deadline.Token);
            current();
            if (Number(page, "schemaVersion", 1, 1) != 1 || Number(page, "membershipModelVersion", 2, 2) != 2 ||
                Text(page, "code", 256) != code || Text(page, "query", 128) != "" ||
                Number(page, "offset", 0, 1000000) != offset) throw Invalid();
            var rows = Rows(page, "members", 20);
            var total = Number(page, "totalCount", 0, 1000000);
            if (Number(page, "matchedCount", 0, 1000000) != total || offset > total ||
                rows.Length != Math.Min(20, total - offset)) throw Invalid();
            foreach (var row in rows)
            {
                var id = Text(row, "memberId", 512);
                if (string.IsNullOrWhiteSpace(id) || !seen.Add(id)) throw Invalid();
                if (id.Equals("account:" + recipient, StringComparison.OrdinalIgnoreCase)) return true;
            }
            int? next = page.GetProperty("next").ValueKind == System.Text.Json.JsonValueKind.Null
                ? null : Number(page, "next", 0, 1000000);
            if (next != (offset + rows.Length < total ? offset + rows.Length : (int?)null)) throw Invalid();
            if (next is null) return false;
            offset = next.Value;
        }
    }
}
