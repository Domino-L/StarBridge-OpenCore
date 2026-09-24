using System.Text.Json;
using StarBridge.HostRuntime.Account;

namespace StarBridge.HostRuntime.Communities;

internal sealed record InvitationSendRequest(string OperationId, string OrganizationRef, string Channel, string DestinationRef, int MaxUses, string Action);
internal sealed record InvitationOutboxRow(string OperationId, string Channel, string Phase, string SourceName,
    string DestinationName, DateTimeOffset RequestedAt, int MaxUses);
internal sealed record InvitationOutboxView(InvitationOutboxRow[] Items) { public int SchemaVersion => 1; }

internal static class InvitationBridgeRequests
{
    internal static InvitationSendRequest Preview(JsonElement payload)
    {
        Validate(payload, "organizationRef", "channel", "destinationRef");
        var channel = Text(payload, "channel", 16);
        var destination = Text(payload, "destinationRef", 256);
        if (channel is not ("private" or "room") || channel == "private" && !InvitationOutboxJournal.IsId(destination)) throw Invalid();
        return new("", Id(payload, "organizationRef"), channel, destination, 0, "check");
    }
    internal static void Read(JsonElement payload) => Validate(payload);
    internal static (string OperationId, string Action) Resume(JsonElement payload)
    {
        Validate(payload, "operationId", "action");
        return (Id(payload, "operationId"), Action(payload));
    }
    internal static InvitationSendRequest Send(JsonElement payload)
    {
        Validate(payload, "operationId", "organizationRef", "channel", "destinationRef", "maxUses", "action");
        var channel = Text(payload, "channel", 16);
        var destination = Text(payload, "destinationRef", 256);
        if (channel is not ("private" or "room") || channel == "private" && !InvitationOutboxJournal.IsId(destination)) throw Invalid();
        var limit = payload.GetProperty("maxUses");
        if (limit.ValueKind != JsonValueKind.Number || !limit.TryGetInt32(out var uses) || uses is < 1 or > 50) throw Invalid();
        return new(Id(payload, "operationId"), Id(payload, "organizationRef"), channel, destination, uses, Action(payload));
    }
    private static string Action(JsonElement payload)
    {
        var action = Text(payload, "action", 16);
        return action is "advance" or "check" or "retryDelivery" ? action : throw Invalid();
    }
    private static string Id(JsonElement payload, string name)
    { var value = Text(payload, name, 32); return InvitationOutboxJournal.IsId(value) ? value : throw Invalid(); }
    private static string Text(JsonElement payload, string name, int max)
    {
        if (!payload.TryGetProperty(name, out var field) || field.ValueKind != JsonValueKind.String) throw Invalid();
        var value = field.GetString()!;
        return value.Length > 0 && value.Length <= max && !value.Any(char.IsControl) ? value : throw Invalid();
    }
    private static void Validate(JsonElement payload, params string[] allowed)
    {
        if (payload.ValueKind != JsonValueKind.Object || !payload.TryGetProperty("schemaVersion", out var schema)
            || schema.ValueKind != JsonValueKind.Number || !schema.TryGetInt32(out var version) || version != 1) throw Invalid();
        var names = payload.EnumerateObject().Select(field => field.Name).ToArray();
        if (names.Length != allowed.Length + 1 || names.Distinct().Count() != names.Length
            || names.Any(name => name != "schemaVersion" && !allowed.Contains(name))) throw Invalid();
    }
    private static AccountBridgeHostException Invalid() => new("communities.dataInvalid");
}
