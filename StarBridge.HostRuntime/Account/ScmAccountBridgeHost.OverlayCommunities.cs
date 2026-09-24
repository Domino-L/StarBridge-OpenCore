using System.Text.Json;
using StarBridge.HostRuntime.Communities;
using StarBridge.HostRuntime.Overlay;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Account;

internal sealed partial class ScmAccountBridgeHost : IOverlayCommunityReader
{
    async Task<IReadOnlyList<OverlayCommunityTarget>> IOverlayCommunityReader.ReadTargetsAsync(
        BridgeAccountContext owner, CancellationToken token)
    {
        var generation = Generation;
        var targets = new List<OverlayCommunityTarget>();
        var seen = new HashSet<string>(StringComparer.Ordinal);
        var cursors = new HashSet<string>(StringComparer.Ordinal);
        string? after = null;
        do
        {
            var page = (CommunityPage)await ReadCommunitiesAsync(owner,
                JsonSerializer.SerializeToElement(new { schemaVersion = 1, view = "mine", query = "", after }), token);
            if (generation != Generation) throw new BridgeStaleGenerationException(generation, Generation);
            foreach (var row in page.Items.Where(x => x.Relationship is "member" or "owner"))
            {
                var target = _communities!.OverlayTarget(row.TargetRef, FriendScope(owner, generation));
                if (!seen.Add(target.Code)) throw new InvalidDataException("Duplicate organization source.");
                targets.Add(target);
            }
            after = page.Next;
            if (after is not null && (!cursors.Add(after) || cursors.Count >= 128))
                throw new InvalidDataException("Organization directory did not complete.");
        } while (after is not null);
        return targets;
    }

    async Task<InformationOverlayCommunityContent> IOverlayCommunityReader.ReadContentAsync(
        BridgeAccountContext owner, OverlayCommunityTarget target, CancellationToken token)
    {
        var generation = Generation;
        var members = new List<InformationOverlayCommunityMember>();
        var seen = new HashSet<string>(StringComparer.Ordinal);
        int? expectedTotal = null;
        var offset = 0;
        string? name = null;
        for (var pageIndex = 0; pageIndex < 128; pageIndex++)
        {
            var result = await ReadCommunityWorkspaceAsync(owner,
                JsonSerializer.SerializeToElement(new { schemaVersion = 1, targetRef = target.Reference, query = "", offset }), token);
            if (generation != Generation) throw new BridgeStaleGenerationException(generation, Generation);
            var page = JsonSerializer.SerializeToElement(result);
            if (page.GetProperty("code").GetString() != target.Code)
                throw new InvalidDataException("Mismatched organization source.");
            // Only rows visible to this viewer are required. A private member
            // omitted by the server must not be recovered from another source.
            var total = page.GetProperty("matchedCount").GetInt32();
            if (expectedTotal is not null && expectedTotal != total)
                throw new AccountBridgeHostException("overlay.source_changed", true);
            expectedTotal = total;
            name ??= page.GetProperty("name").GetString() ?? target.Name;
            foreach (var row in page.GetProperty("members").EnumerateArray())
            {
                // The opaque member address, not a callsign or a display name,
                // detects pagination drift. Never send account IDs to the HUD.
                if (!seen.Add(row.GetProperty("memberRef").GetString()!))
                    throw new AccountBridgeHostException("overlay.source_changed", true);
                members.Add(ProjectOverlayMember(row));
            }
            var next = page.GetProperty("next");
            if (next.ValueKind == JsonValueKind.Null)
            {
                if (members.Count != total)
                    throw new AccountBridgeHostException("overlay.source_changed", true);
                return new(target.Code, name, Array.AsReadOnly(members.ToArray()));
            }
            var nextOffset = next.GetInt32();
            if (nextOffset <= offset) throw new InvalidDataException("Non-progressing organization page.");
            offset = nextOffset;
        }
        // Never publish the first page as if it were the complete roster.
        throw new AccountBridgeHostException("overlay.source_too_large");
    }

    internal static InformationOverlayCommunityMember ProjectOverlayMember(JsonElement row)
    {
        string Text(string key) => row.TryGetProperty(key, out var value) && value.ValueKind == JsonValueKind.String
            ? value.GetString()! : "";
        return new(Text("gameName"), Text("callsign"), Text("roleTitle"), Text("liveStatus"),
            Text("ship"), Text("location"), Text("serverRegion"), row.GetProperty("isSelf").GetBoolean());
    }
}
