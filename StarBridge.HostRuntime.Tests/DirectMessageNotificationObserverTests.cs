using StarBridge.HostRuntime.Notifications;
using StarBridge.NativeBridge;

internal static class DirectMessageNotificationObserverTests
{
    private sealed class Clock : TimeProvider {
        internal long Seconds;
        public override long TimestampFrequency => 1;
        public override long GetTimestamp() => Seconds;
    }
    internal static Task Run() {
        var clock = new Clock();
        var observer = new DirectMessageNotificationObserver(clock);
        var origin = DateTimeOffset.Parse("2026-01-01T00:00:00Z");
        void Check(bool condition, string reason) { if (!condition) throw new Exception(reason); }
        bool Read(int server, long sequence, bool incoming = true, int unread = 1,
            int? created = null, long generation = 1, long active = 1, bool fail = false,
            bool malformed = false, bool empty = false, bool history = false) {
            clock.Seconds = Math.Max(clock.Seconds, server);
            var request = BridgeEnvelope.Request("directMessages.read", "notice-fixture", generation,
                history ? new { schemaVersion = 1, targetRef = "history" } : (object)new { schemaVersion = 1 },
                new BridgeAccountContext("test", "scm", "synthetic"));
            var response = fail ? BridgeEnvelope.ErrorResponse(request, new("unavailable", "fixture")) :
                BridgeEnvelope.Response(request, new { schemaVersion = 1, serverTime = origin.AddSeconds(server),
                    conversations = empty ? Array.Empty<object>() : new object[] { new {
                        conversationKey = new string('a', 64), latestSequence = sequence,
                        lastMessageIncoming = malformed ? (bool?)null : incoming, unreadCount = unread,
                        lastMessageAt = origin.AddSeconds(created ?? server),
                    } } });
            return observer.Observe(request, response, active);
        }
        Check(!Read(1, 10), "First read must establish a baseline, not replay history.");
        Check(Read(2, 11), "Fresh incoming message must be recognized.");
        Check(!Read(3, 11) && !Read(2, 10) && !Read(4, 11), "Duplicates and older responses must not replay.");
        Check(!Read(5, 12, incoming: false) && !Read(6, 12), "Own sends advance baseline without notification.");
        Check(!Read(7, 13, unread: 0) && !Read(8, 13), "Read messages never reappear after unread changes.");
        Check(!Read(45, 20) && Read(46, 21), "Reconnect baseline must suppress backlog then resume fresh events.");
        Check(!Read(47, 1, generation: 0) && Read(48, 22), "Stale account responses must not reset current baseline.");
        Check(!Read(49, 23, fail: true) && !Read(50, 23) && Read(51, 24), "Failed reads require a quiet rebaseline.");
        Check(!Read(52, 1) && !Read(53, 24), "Sequence regression cannot lower the high-water mark.");
        Check(!Read(54, 24, empty: true) && !Read(55, 24), "Missing and reappearing conversations cannot replay.");
        Check(!Read(56, 25, malformed: true) && !Read(57, 25), "Unknown message direction is never guessed.");
        Check(!Read(58, 99, history: true) && Read(59, 26), "History/pagination is not a fresh inbox source.");
        Check(!Read(60, 26, generation: 2, active: 2) && Read(61, 27, generation: 2, active: 2), "New owner generation needs its own baseline.");
        observer.Reset();
        Check(!Read(62, 28, generation: 2, active: 2), "Explicit invalidation clears the baseline.");
        return Task.CompletedTask;
    }
}
