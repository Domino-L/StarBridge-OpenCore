using System.Reflection;
using StarBridge.Core.Presence;
using StarBridge.HostRuntime.Overlay;

namespace StarBridge.Desktop.Tests;

internal static class OverlayMainFleetChatTests
{
    private static void Check(bool value, string message) { if (!value) throw new Exception(message); }

    internal static void RunAll()
    {
        var tests = new List<(string Name, Action Run)>();
        foreach (var state in new[] { "expired", "hidden", "unavailable", "visible" })
        {
            tests.Add(("visible " + state, () => Transition(state, false)));
            tests.Add(("queued " + state, () => Transition(state, true)));
        }
        tests.Add(("list author refresh", ListRefresh));
        tests.Add(("Host supplies a new author", HostSuppliesAuthor));
        tests.Add(("same sequence in separate sources", SeparateSources));
        tests.Add(("slid-out queued author expires", SlidOutQueuedAuthor));
        tests.Add(("slid-out visible author expires", () => SlidOutVisibleAuthor(false)));
        tests.Add(("list author expires on tick", () => SlidOutVisibleAuthor(true)));
        tests.Add(("expired before first display", ExpiredBeforeDisplay));
        tests.Add(("Host renews author deadline", RenewedAuthor));
        var failed = 0;
        foreach (var test in tests)
        {
            try { test.Run(); Console.WriteLine("PASS main fleet chat " + test.Name); }
            catch (Exception error) { failed++; Console.WriteLine("FAIL main fleet chat " + test.Name + ": " + error.Message); }
        }
        Console.WriteLine($"Main fleet chat: {tests.Count - failed} passed, {failed} failed");
        if (failed > 0) throw new Exception($"Main fleet chat: {failed} failed");
    }

    private sealed class Fixture : IDisposable
    {
        internal readonly DateTimeOffset At = DateTimeOffset.UtcNow;
        internal readonly OverlayDisplaySettings Settings;
        internal readonly OverlayViewModel Model;
        internal readonly InformationOverlayCommunityContent Fleet = new("fleet", "Fixture fleet", []) { SharedFieldsOnly = true };
        internal Fixture(bool list = false)
        {
            Settings = OverlayDisplaySettings.Default with
            {
                ShowChat = true, ChatShowSender = true, ChatHideSelfMessages = false,
                ChatDisplayMode = list ? OverlayChatDisplayMode.MessageList : OverlayChatDisplayMode.FullScreenBarrage,
                AnimationFrameRate = OverlayAnimationFrameRate.Fps60
            };
            var source = Project(Fleet);
            Model = new(new([]), Settings, OverlayRosterSelectionSettings.Default, "en", true,
                source.Command, PlayerPresenceKind.AppOnline, "", source.Scene.Context, source.Chat);
        }
        internal InformationOverlayRoomMessage Message(long sequence) => new(sequence, "Projected author", "ProjectedGame",
            "Message " + sequence, At, false) { AuthorValidUntil = At.AddSeconds(5) };
        private static (OverlaySceneSnapshot Scene, OverlayCommandState Command, OverlayChatMessage[] Chat) Project(InformationOverlayCommunityContent fleet) =>
            NativeInformationOverlayRuntime.ProjectSource(null, fleet, OverlayScenePreference.Auto, "en", true);
        internal void Refresh(params InformationOverlayRoomMessage[] messages)
        {
            var source = Project(Fleet with { LatestChatSequence = messages.Select(m => m.Sequence).DefaultIfEmpty().Max(), Messages = messages });
            Model.Refresh(new([]), Settings, OverlayRosterSelectionSettings.Default, "en", true,
                source.Command, PlayerPresenceKind.AppOnline, "", source.Scene.Context, source.Chat);
        }
        internal InformationOverlayRoomMessage Changed(InformationOverlayRoomMessage message, string state) => state switch
        {
            "visible" => message with { AuthorValidUntil = At.AddMinutes(1) },
            "expired" => (Fleet with { Messages = [message] }).WithoutExpiredChatAuthors(At.AddSeconds(5)).Messages.Single(),
            _ => message with { SenderCallsign = "", SenderGameId = "" }
        };
        public void Dispose() => Model.ClearAuthorizedContent();
    }

    private static void Transition(string state, bool queued)
    {
        using var f = new Fixture();
        var count = queued ? OverlayDisplaySettings.ResolveChatBarrageCapacity(f.Settings.ChatBarrageDensity) + 1 : 1;
        var messages = Enumerable.Range(1, count).Select(i => f.Message(i)).ToArray();
        f.Refresh(messages);
        var target = messages[^1];
        var row = f.Model.ChatMessages.First();
        row.AdvanceBarrage(row.BarrageStartedAtUtc.AddSeconds(0.5));
        var progress = (row.BarrageStartedAtUtc, row.BarrageDurationSeconds, row.BarrageLane, row.MotionProgress, row.ExpiresAt);
        var pulse = f.Model.ChatPulse;
        var activity = f.Model.CommunicationAppearanceActivities.ToArray();
        messages[^1] = f.Changed(target, state) with { Text = "Replacement body must not replace the playing message" };
        f.Refresh(messages);
        Check(ReferenceEquals(row, f.Model.ChatMessages.First()) && progress ==
            (row.BarrageStartedAtUtc, row.BarrageDurationSeconds, row.BarrageLane, row.MotionProgress, row.ExpiresAt),
            "Author refresh must preserve the visible card and playback progress.");
        Check(f.Model.ChatPulse == pulse && activity.SequenceEqual(f.Model.CommunicationAppearanceActivities),
            "Author refresh must not replay, pulse or add appearance activity.");
        if (queued)
        {
            // Releasing one lane promotes the existing queued item without a new content read.
            typeof(OverlayViewModel).GetMethod("TickChatMessages", BindingFlags.Instance | BindingFlags.NonPublic)!
                .Invoke(f.Model, [DateTimeOffset.Now.AddSeconds(31)]);
        }
        var current = f.Model.ChatMessages.Single(r => r.Detail == target.Text);
        Check(state == "visible" ? current.Title.Contains("Projected author") && current.Title.Contains("ProjectedGame")
            : !current.Title.Contains("Projected author") && !current.Title.Contains("ProjectedGame"),
            "The current Host author projection must replace the old name: " + state);
        Check(current.Detail == target.Text, "Author refresh preserves the message text.");
        if (!queued)
        {
            f.Model.ChatMessages.Clear();
            f.Refresh(messages);
            Check(f.Model.ChatMessages.Count == 0, "An already played sequence cannot be replayed by author refresh.");
        }
    }

    private static void ListRefresh()
    {
        using var f = new Fixture(true);
        var message = f.Message(1);
        f.Refresh(message);
        var row = f.Model.ChatMessages.Single();
        var pulse = f.Model.ChatPulse;
        f.Refresh(f.Changed(message, "hidden") with { Text = "Host replacement text" });
        Check(ReferenceEquals(row, f.Model.ChatMessages.Single()) && row.Detail == message.Text &&
            !row.Title.Contains("Projected author") && f.Model.ChatPulse == pulse,
            "An author-only list refresh updates the existing card without replaying or replacing its text.");
    }

    private static void HostSuppliesAuthor()
    {
        using var f = new Fixture();
        var message = f.Message(1);
        f.Refresh(f.Changed(message, "unavailable"));
        var row = f.Model.ChatMessages.Single();
        f.Refresh(message);
        Check(ReferenceEquals(row, f.Model.ChatMessages.Single()) && row.Title.Contains("Projected author"),
            "Only a new Host projection can name an already known anonymous message.");
    }

    private static void SeparateSources()
    {
        using var f = new Fixture();
        var context = NativeInformationOverlayRuntime.ProjectSource(null, f.Fleet, OverlayScenePreference.Auto, "en", true).Scene.Context;
        void Refresh(params OverlayChatMessage[] messages) => typeof(OverlayViewModel)
            .GetMethod("RefreshChatMessages", BindingFlags.Instance | BindingFlags.NonPublic)!
            .Invoke(f.Model, [messages, f.Settings, false, context, new[] { "fleet", "organization" }]);
        OverlayChatMessage Message(string source, string author) => new(1, context.ChatChannelId!, author, "",
            source + " text", f.At, false, false, "#FFFFFF", SourceKey: source);
        Refresh(); // Admit both sources before their first live message.
        var fleet = Message("fleet", "Fleet author");
        var organization = Message("organization", "Organization author");
        Refresh(fleet, organization);
        var peer = f.Model.ChatMessages.Single(r => r.Detail == organization.Text);
        Refresh(fleet with { SenderCallsign = "" });
        Check(!f.Model.ChatMessages.Single(r => r.Detail == fleet.Text).Title.Contains("Fleet author") &&
            ReferenceEquals(peer, f.Model.ChatMessages.Single(r => r.Detail == organization.Text)) && peer.Title.Contains("Organization author"),
            "A projection only updates its source/sequence pair; an absent source supplies no author change.");
    }

    private static void Tick(Fixture fixture, DateTimeOffset now) => typeof(OverlayViewModel)
        .GetMethod("TickChatMessages", BindingFlags.Instance | BindingFlags.NonPublic)!.Invoke(fixture.Model, [now]);

    private static void SlidOutQueuedAuthor()
    {
        using var f = new Fixture();
        var capacity = OverlayDisplaySettings.ResolveChatBarrageCapacity(f.Settings.ChatBarrageDensity);
        var messages = Enumerable.Range(1, capacity + 1).Select(i => f.Message(i)).ToArray();
        f.Refresh(messages);
        var target = messages[^1];
        Check(!f.Model.ChatMessages.Any(row => row.Detail == target.Text), "The target is queued before the Host window moves.");
        f.Refresh(Enumerable.Range(capacity + 2, 50).Select(i => f.Message(i)).ToArray());
        Tick(f, f.At.AddSeconds(31));
        var row = f.Model.ChatMessages.Single(row => row.Detail == target.Text);
        Check(!row.Title.Contains("Projected author") && !row.Title.Contains("ProjectedGame"),
            "A queued message outside the latest 50 must be anonymous when dequeued after its author expires.");
    }

    private static void SlidOutVisibleAuthor(bool list)
    {
        using var f = new Fixture(list);
        f.Refresh(f.Message(1));
        var row = f.Model.ChatMessages.Single();
        if (!list) f.Refresh(); // No later Host author update for this retained card.
        var playback = (row.BarrageStartedAtUtc, row.BarrageDurationSeconds, row.BarrageLane, row.ExpiresAt);
        var pulse = f.Model.ChatPulse;
        var activity = f.Model.CommunicationAppearanceActivities.ToArray();
        Tick(f, f.At.AddSeconds(5));
        Check(f.Model.ChatMessages.Contains(row) && !row.Title.Contains("Projected author") && !row.Title.Contains("ProjectedGame"),
            "A retained card must lose its expired author on tick without a Host refresh.");
        Check(playback == (row.BarrageStartedAtUtc, row.BarrageDurationSeconds, row.BarrageLane, row.ExpiresAt) &&
            pulse == f.Model.ChatPulse && activity.SequenceEqual(f.Model.CommunicationAppearanceActivities),
            "Expiry preserves the card, playback and appearance activity.");
    }

    private static void ExpiredBeforeDisplay()
    {
        using var f = new Fixture(true);
        f.Refresh(f.Message(1) with { AuthorValidUntil = f.At.AddSeconds(-1) });
        Check(!f.Model.ChatMessages.Single().Title.Contains("Projected author"),
            "An author already expired at first display is never shown.");
    }

    private static void RenewedAuthor()
    {
        using var f = new Fixture(true);
        var message = f.Message(1);
        f.Refresh(message);
        var row = f.Model.ChatMessages.Single();
        f.Refresh(message with { AuthorValidUntil = f.At.AddMinutes(1) });
        Tick(f, f.At.AddSeconds(6));
        Check(ReferenceEquals(row, f.Model.ChatMessages.Single()) && row.Title.Contains("Projected author"),
            "A fresh Host author validity replaces the old deadline.");
        Tick(f, f.At.AddMinutes(1));
        Check(!row.Title.Contains("Projected author"), "A renewed author still expires at its new deadline.");
    }
}
