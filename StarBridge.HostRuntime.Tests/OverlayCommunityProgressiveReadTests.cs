using StarBridge.HostRuntime.Overlay;
using StarBridge.NativeBridge;

internal static class OverlayCommunityProgressiveReadTests
{
    private static readonly BridgeAccountContext Owner = new("test", "scm", "progressive-fixture");
    internal static async Task Run()
    {
        var now = new DateTimeOffset(2026, 9, 30, 0, 0, 0, TimeSpan.Zero);
        var reader = new Reader();
        using var source = new OverlayCommunitySource(() => (Owner, 1), reader, false, () => now);
        Guid? continuity = null;
        for (var cycle = 0; cycle < 4; cycle++)
        {
            reader.Started = new(TaskCreationOptions.RunContinuationsAsynchronously);
            reader.Release = new(TaskCreationOptions.RunContinuationsAsynchronously);
            reader.FailCommunication = cycle > 0;
            var refresh = source.RefreshAsync();
            try
            {
                await reader.Started.Task.WaitAsync(TimeSpan.FromSeconds(2));
                var content = source.Read();
                Check(content?.Members.Count == 1,
                    "Authorized organization members must remain visible before slow chat/announcement reads complete.");
                continuity ??= content!.ContinuityId;
                Check(content!.ContinuityId == continuity, "Communication delays must not reset the member scene.");
                now = now.AddSeconds(19);
                Check(source.Read()?.Members.Count == 1, "A pending communication read must not invalidate the fresh roster.");
                if(cycle >= 2)
                    Check(source.Read()!.AnnouncementText.Length == 0, "Fresh rosters never extend stale announcement authorization.");
            }
            finally { reader.Release.TrySetResult(); await refresh; }
            Check(source.Read()?.Members.Count == 1, "A transient communication failure must retain the freshly authorized members.");
            now = now.AddSeconds(10);
        }
        now = now.AddSeconds(40);
        Check(source.Read() is null, "No successful member read: the original roster lease must still expire.");
        await LegacyPasswordLoginTests.OverlayProgressiveAdapter();
        Console.WriteLine("PASS progressive roster survives slow communication across repeated refreshes and still expires");
    }
    private static void Check(bool ok, string message) { if (!ok) throw new InvalidOperationException(message); }
    private sealed class Reader : IOverlayCommunityReader
    {
        internal TaskCompletionSource Started = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal TaskCompletionSource Release = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal bool FailCommunication;
        public Task<IReadOnlyList<OverlayCommunityTarget>> ReadTargetsAsync(BridgeAccountContext owner, CancellationToken token) =>
            Task.FromResult<IReadOnlyList<OverlayCommunityTarget>>([new("A", "Organization", "reference")]);
        public Task<InformationOverlayCommunityContent> ReadContentAsync(BridgeAccountContext owner, OverlayCommunityTarget target, CancellationToken token) => Read(null, token);
        public Task<InformationOverlayCommunityContent> ReadContentAsync(BridgeAccountContext owner, OverlayCommunityTarget target,
            Action<InformationOverlayCommunityContent> rosterReady, CancellationToken token) => Read(rosterReady, token);
        private async Task<InformationOverlayCommunityContent> Read(Action<InformationOverlayCommunityContent>? rosterReady, CancellationToken token)
        {
            var content = new InformationOverlayCommunityContent("A", "Organization",
                [new("Fixture", "Fixture", "Member", "AppOnline", "", "", "", true)]);
            rosterReady?.Invoke(content);
            Started.TrySetResult();
            await Release.Task.WaitAsync(token);
            if (FailCommunication) throw new IOException("synthetic communication interruption");
            return content with { AnnouncementText = "Notice", LatestChatSequence = 10 };
        }
    }
}
