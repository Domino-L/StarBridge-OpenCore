using StarBridge.HostRuntime.Notifications;
using StarBridge.HostRuntime.Overlay;
using StarBridge.NativeBridge;

internal static class DirectUnreadOverlayTests
{
    private sealed class Sink : IInformationOverlayDirectUnreadSink
    {
        internal readonly List<InformationOverlayDirectUnread?> Updates = [];
        internal bool Throw;
        public void UpdateDirectUnread(InformationOverlayDirectUnread? unread)
        {
            if (Throw) throw new InvalidOperationException("Synthetic renderer failure");
            Updates.Add(unread);
        }
    }

    private sealed class Fixture : IDisposable
    {
        internal readonly string Root = Path.Combine(Path.GetTempPath(), "cx81-" + Guid.NewGuid().ToString("N"));
        internal readonly Sink Sink = new();
        internal readonly BridgeAccountContext Account = new("fixture", "fixture", "synthetic");
        internal long Generation = 1;
        internal readonly NotificationSettingsBridgeDispatcher Owner;
        private int _revision, _second;
        internal Fixture()
        {
            Directory.CreateDirectory(Root);
            Owner = new(Root, () => Generation, directUnread: Sink);
        }
        internal static object Row(char key, int unread, string callsign = "Fixture", bool sequence = true) => new {
            conversationKey = new string(key, 64), unreadCount = unread, callsign,
            latestSequence = sequence ? (long?)1 : null, lastMessageIncoming = sequence ? (bool?)true : null,
            lastMessageAt = DateTimeOffset.Parse("2026-10-24T00:00:00Z"), preview = "Synthetic private message"
        };
        internal async Task Read(object[] rows, string? target = null, bool noAccount = false,
            long? requestGeneration = null, long? responseGeneration = null, bool failed = false, bool mismatchedAccount = false)
        {
            var request = BridgeEnvelope.Request("directMessages.read", Guid.NewGuid().ToString("N"),
                requestGeneration ?? Generation, target == null ? (object)new { schemaVersion = 1 } : new { schemaVersion = 1, targetRef = target },
                noAccount ? null : Account);
            var response = failed ? BridgeEnvelope.ErrorResponse(request, new("fixture.unavailable", "Synthetic failure")) :
                BridgeEnvelope.Response(request, new {
                    schemaVersion = 1, conversations = rows,
                    serverTime = DateTimeOffset.Parse("2026-10-24T00:00:00Z").AddSeconds(_second++)
                });
            if (responseGeneration != null) response = response with { SessionGeneration = responseGeneration.Value };
            if (mismatchedAccount) response = response with { AccountContext = new("fixture", "fixture", "other") };
            var observed = await Owner.ObserveAsync(request, response, default);
            Check(observed == response, "Unread projection preserves the domain response.");
        }
        internal async Task Save(bool overlay = true, string preview = "sourceOnly")
        {
            var result = await Owner.DispatchAsync(BridgeEnvelope.Request("notificationSettings.save", Guid.NewGuid().ToString("N"), Generation,
                new { schemaVersion = 1, expectedRevision = _revision, inAppEnabled = true, windowsEnabled = false,
                    overlayEnabled = overlay, position = "bottomRight", preview }));
            Check(result.Response.Status == "ok", "Synthetic preferences saved.");
            _revision++;
        }
        public void Dispose() { Owner.Dispose(); Directory.Delete(Root, true); }
    }

    internal static async Task Summaries()
    {
        using var f = new Fixture();
        await f.Read([]);
        Check(f.Sink.Updates.SequenceEqual(new InformationOverlayDirectUnread?[] { null }), "Zero unread clears on first full read.");
        await f.Read([Fixture.Row('a', 8), Fixture.Row('b', 0, "ReadFixture")]);
        Check(f.Sink.Updates.Last() == new InformationOverlayDirectUnread(1, "Fixture"), "Count conversations, not unread messages; baseline is published.");
        var before = f.Sink.Updates.Count;
        await f.Read([Fixture.Row('a', 9)]);
        Check(f.Sink.Updates.Count == before, "Unchanged count and callsign are deduplicated without a fresh event.");
        await f.Read([Fixture.Row('a', 9, "ChangedFixture")]);
        Check(f.Sink.Updates.Last() == new InformationOverlayDirectUnread(1, "ChangedFixture"), "Same count with changed sender is published.");
        await f.Read([Fixture.Row('a', 1), Fixture.Row('b', 4, "SecondFixture"), Fixture.Row('c', 0)]);
        Check(f.Sink.Updates.Last() == new InformationOverlayDirectUnread(2, ""), "Multiple unread conversations never expose a callsign.");
        await f.Read([Fixture.Row('a', 0), Fixture.Row('b', 0)]);
        Check(f.Sink.Updates.Last() == null, "Read receipts clear the mark with unchanged latestSequence.");
        before = f.Sink.Updates.Count;
        await f.Read([]);
        Check(f.Sink.Updates.Count == before, "Repeated zero is deduplicated.");
        await f.Read([Fixture.Row('a', 1, sequence: false)]);
        Check(f.Sink.Updates.Last() == new InformationOverlayDirectUnread(1, "Fixture"), "Readable legacy rows need no fresh-message sequence contract for a quiet mark.");
    }

    internal static async Task Privacy()
    {
        using var f = new Fixture();
        await f.Save(preview: "hiddenDetails");
        await f.Read([Fixture.Row('a', 1)]);
        Check(f.Sink.Updates.Last() == new InformationOverlayDirectUnread(1, ""), "Hidden details redacts the sender.");
        await f.Save(preview: "fullContent");
        await f.Read([Fixture.Row('a', 1, new string('x', 512))]);
        Check(f.Sink.Updates.Last() == new InformationOverlayDirectUnread(1, new string('x', 512)), "512 characters is allowed.");
        await f.Read([Fixture.Row('a', 1, new string('x', 513))]);
        Check(f.Sink.Updates.Last() == new InformationOverlayDirectUnread(1, ""), "Overlong sender hides only the callsign, retaining unread count.");
    }

    internal static async Task Gates()
    {
        using var f = new Fixture();
        var policies = new NotificationPolicyStore(f.Root);
        await f.Read([Fixture.Row('a', 1)]);
        policies.Save(f.Account, 0, Guid.NewGuid().ToString("N"), [new("directMessages", NotificationSourceMode.DoNotDisturb)], () => true);
        await f.Read([Fixture.Row('a', 1)]);
        Check(f.Sink.Updates.Last() == null, "Source muted clears even when no new message arrived.");
        policies.Save(f.Account, 1, Guid.NewGuid().ToString("N"), [new("directMessages", NotificationSourceMode.ImportantOnly)], () => true);
        await f.Read([Fixture.Row('a', 1)]);
        Check(f.Sink.Updates.Last()?.Conversations == 1, "ImportantOnly permits direct messages under the existing policy.");
        await f.Save(overlay: false);
        var before = f.Sink.Updates.Count;
        await f.Read([Fixture.Row('a', 1)]);
        Check(f.Sink.Updates.Last() == null && f.Sink.Updates.Count == before + 1, "Overlay off publishes null after invalidation resets deduplication.");
        before = f.Sink.Updates.Count;
        await f.Read([Fixture.Row('a', 1)]);
        Check(f.Sink.Updates.Count == before, "Repeated disabled reads are deduplicated.");
        await f.Save();
        await f.Read([Fixture.Row('a', 1)]);
        await f.Read([Fixture.Row('a', 1)], noAccount: true);
        Check(f.Sink.Updates.Last() == null, "Missing account context clears the mark.");
    }

    internal static async Task ResponseBoundaries()
    {
        using var f = new Fixture();
        await f.Read([Fixture.Row('a', 1)]);
        var before = f.Sink.Updates.Count;
        await f.Read([], target: "synthetic-history");
        await f.Read([], failed: true);
        await f.Read([], mismatchedAccount: true);
        await f.Read([new { unreadCount = "invalid", callsign = "Fixture" }]);
        Check(f.Sink.Updates.Count == before, "Single-conversation, failed, mismatched and malformed responses leave the summary unchanged.");
        f.Owner.Reset();
        f.Generation++;
        await f.Read([Fixture.Row('b', 2, "CurrentFixture")]);
        before = f.Sink.Updates.Count;
        await f.Read([], requestGeneration: 1);
        await f.Read([], responseGeneration: 1);
        Check(f.Sink.Updates.Count == before && f.Sink.Updates.Last()?.Callsign == "CurrentFixture", "Old request or response generation cannot overwrite the current mark.");
        f.Generation++;
        await f.Read([], requestGeneration: 2);
        Check(f.Sink.Updates.Last() == null, "A generation change also clears a retired mark before a late response is ignored.");
        await f.Read([Fixture.Row('b', 2, "CurrentFixture")]);
        Check(f.Sink.Updates.Last()?.Conversations == 1, "New generation republishes even an identical summary.");
    }

    internal static async Task LifecycleAndFailures()
    {
        using var f = new Fixture();
        await f.Read([Fixture.Row('a', 1)]);
        f.Owner.Reset();
        Check(f.Sink.Updates.Last() == null, "Reset clears the mark.");
        var before = f.Sink.Updates.Count;
        await f.Read([]);
        Check(f.Sink.Updates.Count == before + 1, "Reset clears the deduplication state as well.");
        f.Sink.Throw = true;
        await f.Read([Fixture.Row('a', 1)]);
        f.Owner.Reset();
        f.Sink.Throw = false;
        await f.Read([Fixture.Row('a', 1)]);
        Check(f.Sink.Updates.Last()?.Conversations == 1, "Sink failures are swallowed and delivery can recover.");
        before = f.Sink.Updates.Count;
        // Room inbox reads invalidate the room reminder often; the direct-message mark must not flicker.
        typeof(NotificationSettingsBridgeDispatcher).GetMethod("InvalidateReminder",
            System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic)!.Invoke(f.Owner, []);
        Check(f.Sink.Updates.Count == before, "Room reminder invalidation leaves the unread mark alone.");
        await f.Save(preview: "hiddenDetails");
        Check(f.Sink.Updates.Last() == null, "Existing reminder invalidation clears private sender data immediately.");
        await f.Read([Fixture.Row('a', 1)]);
        Check(f.Sink.Updates.Last() == new InformationOverlayDirectUnread(1, ""), "Next full read recomputes under the changed preferences.");
        f.Owner.Dispose();
        Check(f.Sink.Updates.Last() == null, "Dispose clears the mark.");
        before = f.Sink.Updates.Count;
        await f.Read([Fixture.Row('a', 1)]);
        Check(f.Sink.Updates.Count == before, "Disposed dispatcher cannot revive a mark.");
    }

    private static void Check(bool value, string message) { if (!value) throw new Exception(message); }
}
