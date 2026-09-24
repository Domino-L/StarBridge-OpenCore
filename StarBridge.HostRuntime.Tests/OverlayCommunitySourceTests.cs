using System.Text.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Overlay;
using StarBridge.NativeBridge;

internal static class OverlayCommunitySourceTests
{
    private static readonly BridgeAccountContext Owner = new("test", "scm", "synthetic-member");
    private static readonly DateTimeOffset Start = new(2026, 9, 12, 0, 0, 0, TimeSpan.Zero);
    private static void Check(bool value, string message) { if (!value) throw new Exception(message); }
    private static InformationOverlayCommunityContent Content(string code, string name = "Organization") =>
        new(code, name, [new("Case_Handle", "Display", "Member", "AppOnline", "", "", "", true)]);

    internal static async Task Selection()
    {
        var reader = new Reader();
        using var source = new OverlayCommunitySource(() => (Owner, 1), reader, false, () => Start);
        await source.RefreshAsync();
        Check(source.Read()?.Code == "A", "Automatic selection has deterministic ordering.");
        var beforeRename = source.Read()!;
        source.Rename(Owner, 1, "A", "新名称");
        Check(source.Read()?.Name == "新名称", "Confirmed rename updates the native overlay immediately.");
        Check(source.Read()!.ContinuityId == beforeRename.ContinuityId && ReferenceEquals(source.Read()!.Members, beforeRename.Members),
            "Rename does not reload members or reset overlay continuity.");
        source.Rename(Owner, 2, "A", "Wrong session");
        Check(source.Read()?.Name == "新名称", "Another session cannot rename the displayed content.");
        reader.Read = code => Task.FromResult(Content(code, code == "A" ? "新名称" : "Organization"));
        reader.Targets = [new("B", "Same name", "b"), new("A", "Same name", "a")];
        var previous = source.Read();
        await source.RefreshAsync();
        Check(ReferenceEquals(previous, source.Read()), "Unchanged reads retain the exact snapshot, no mass reload.");
        reader.Targets = [new("0", "Earlier", "0"), .. reader.Targets];
        await source.RefreshAsync();
        Check(source.Read()?.Code == "A", "Joining another organization does not reshuffle the current source.");
        source.Select("B");
        Check(source.Read() is null, "Changing target clears old roster immediately.");
        await source.RefreshAsync();
        Check(source.Read()?.Code == "B", "Explicit target chooses identity, not name.");
        reader.Targets = [new("A", "Same name", "a")];
        await source.RefreshAsync();
        Check(source.Read() is null, "Missing explicit target does not switch to A.");
        source.Select(null);
        await source.RefreshAsync();
        Check(source.Read()?.Code == "A", "Returning to automatic resolves an available joined source.");
    }

    internal static async Task Recovery()
    {
        var now = Start;
        var reader = new Reader();
        using var source = new OverlayCommunitySource(() => (Owner, 1), reader, false, () => now);
        await source.RefreshAsync();
        var first = source.Read()!;
        reader.Read = _ => throw new AccountBridgeHostException("communities.unavailable", true);
        now = Start.AddSeconds(20);
        await source.RefreshAsync();
        Check(ReferenceEquals(first, source.Read()), "Short transient error preserves bounded authorized snapshot.");
        now = Start.AddSeconds(40);
        Check(source.Read() is null, "Unavailable authorization cannot retain content indefinitely.");
        reader.Read = code => Task.FromResult(Content(code));
        await source.RefreshAsync();
        Check(source.Read() is not null && first.ContinuityId != source.Read()!.ContinuityId,
            "Background success recovers without manual refresh and starts new continuity.");
        reader.Read = _ => throw new AccountBridgeHostException("communities.identityUnavailable");
        await source.RefreshAsync();
        Check(source.Read() is null, "Permission failure clears immediately.");
    }

    internal static async Task AccountAndLateResponses()
    {
        (BridgeAccountContext? Owner, long Generation) owner = (Owner, 1);
        var pending = new TaskCompletionSource<InformationOverlayCommunityContent>(TaskCreationOptions.RunContinuationsAsynchronously);
        var reader = new Reader { Read = _ => pending.Task };
        using var source = new OverlayCommunitySource(() => owner, reader, false, () => Start);
        var refresh = source.RefreshAsync();
        source.Select("B");
        pending.SetResult(Content("A"));
        await refresh;
        Check(source.Read() is null, "Late A response cannot populate explicit B.");
        reader.Read = code => Task.FromResult(Content(code));
        await source.RefreshAsync();
        Check(source.Read()?.Code == "B", "New selection can recover.");
        owner = (Owner with { Subject = "synthetic-other" }, 2);
        Check(source.Read() is null, "Account switch clears cached content synchronously.");
        await source.RefreshAsync();
        Check(source.Read()?.Code == "A", "New account does not inherit previous account selection.");
        owner = (null, 3);
        Check(source.Read() is null, "Logout immediately clears content.");
    }

    internal static async Task CoalescingAndProjection()
    {
        var pending = new TaskCompletionSource<InformationOverlayCommunityContent>(TaskCreationOptions.RunContinuationsAsynchronously);
        var reader = new Reader { Read = _ => pending.Task };
        using var source = new OverlayCommunitySource(() => (Owner, 1), reader, false, () => Start);
        var first = source.RefreshAsync();
        await source.RefreshAsync();
        Check(reader.ContentReads == 1, "Concurrent refreshes share one request lane.");
        pending.SetResult(Content("A"));
        await first;
        using var row = JsonDocument.Parse("""
            {"gameName":"Case_Handle","callsign":"Same display","roleTitle":"Member",
            "liveStatus":"AppOnline","ship":null,"location":null,"serverRegion":null,
            "serverShard":"not-for-overlay","isSelf":false}
            """);
        var member = ScmAccountBridgeHost.ProjectOverlayMember(row.RootElement);
        Check(member.GameId == "Case_Handle" && !member.IsSelf, "Preserve authoritative identity/self flag.");
        Check(member.Ship == "" && member.Location == "" && member.ServerRegion == "",
            "Do not fill redacted fields or derive region from a more detailed field.");
    }

    internal static async Task DemandAndDisposal()
    {
        var entered = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var pending = new TaskCompletionSource<InformationOverlayCommunityContent>(TaskCreationOptions.RunContinuationsAsynchronously);
        var reader = new Reader { Read = _ => { entered.TrySetResult(); return pending.Task; } };
        using var source = new OverlayCommunitySource(() => (Owner, 1), reader, true, () => Start);
        Check(reader.ContentReads == 0, "A configured but closed overlay does not fetch rosters.");
        Check(source.ReadForDisplay() is null, "First display read does not block the renderer on network I/O.");
        await entered.Task.WaitAsync(TimeSpan.FromSeconds(3));
        Check(reader.ContentReads == 1, "First display demand wakes the background reader immediately.");
        source.Dispose();
        pending.TrySetResult(Content("A"));
        await source.Completion.WaitAsync(TimeSpan.FromSeconds(3));
        Check(source.ReadForDisplay() is null, "Late network completion cannot publish after disposal.");
    }

    private sealed class Reader : IOverlayCommunityReader
    {
        internal IReadOnlyList<OverlayCommunityTarget> Targets = [new("B", "Same name", "b"), new("A", "Same name", "a")];
        internal Func<string, Task<InformationOverlayCommunityContent>> Read = code => Task.FromResult(Content(code));
        internal int ContentReads;
        public Task<IReadOnlyList<OverlayCommunityTarget>> ReadTargetsAsync(BridgeAccountContext owner, CancellationToken token) => Task.FromResult(Targets);
        public Task<InformationOverlayCommunityContent> ReadContentAsync(BridgeAccountContext owner, OverlayCommunityTarget target, CancellationToken token)
        { ContentReads++; return Read(target.Code); }
    }
}
