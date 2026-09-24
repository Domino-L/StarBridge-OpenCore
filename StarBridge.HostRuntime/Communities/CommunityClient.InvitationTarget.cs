namespace StarBridge.HostRuntime.Communities;

internal sealed record InvitationTargetPreview(bool CanSend, int EligibleRecipients) { public int SchemaVersion => 1; }

internal sealed partial class CommunityClient
{
    internal async Task<InvitationTargetPreview> PreviewInvitationTargetAsync(string bearer, string organizationRef,
        InvitationDeliveryTarget destination, string scope, Action current, CancellationToken token)
    {
        current();
        var source = Resolve(organizationRef, scope);
        if (destination.Scope != scope || destination.Channel is not ("private" or "room") ||
            destination.Origin.GetLeftPart(UriPartial.Authority) != _origin.GetLeftPart(UriPartial.Authority)) throw Invalid();
        var data = await WorkspaceJson(bearer, $"/api/fleets/invitation-target?code={Uri.EscapeDataString(source.Code)}&channel={destination.Channel}&destination={Uri.EscapeDataString(destination.Id)}", token, 4096);
        current();
        var fields = data.EnumerateObject().Select(field => field.Name).ToArray();
        if (fields.Length != 4 || fields.Distinct().Count() != 4 ||
            fields.Any(name => name is not ("schemaVersion" or "membershipModelVersion" or "canSend" or "eligibleRecipients")) ||
            Number(data, "schemaVersion", 1, 1) != 1 || Number(data, "membershipModelVersion", 2, 2) != 2) throw Invalid();
        var count = Number(data, "eligibleRecipients", 0, destination.Channel == "private" ? 1 : 50);
        var canSend = data.GetProperty("canSend").GetBoolean();
        if (canSend != (count > 0)) throw Invalid();
        return new(canSend, count);
    }
}
