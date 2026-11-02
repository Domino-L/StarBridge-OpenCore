using System.Text.Json;
using StarBridge.HostRuntime.Notifications;
using StarBridge.NativeBridge;

// All data and monotonic time belong to this in-memory/TEMP fixture.
internal static class TradeNotificationActivationTests
{
    private sealed class Clock : TimeProvider
    {
        internal long Seconds;
        public override long TimestampFrequency => 1;
        public override long GetTimestamp() => Seconds;
    }

    private sealed class Sink : IDesktopNotificationSink
    {
        internal readonly List<DesktopNotification> Cards = [];
        public ValueTask<bool> TryPresentAsync(DesktopNotification card, CancellationToken token)
        {
            Cards.Add(card);
            return ValueTask.FromResult(true);
        }
        public void Clear() { }
        public void Dispose() { }
    }

    private sealed class Fixture : IDisposable
    {
        internal readonly string Root = Directory.CreateTempSubdirectory("cxt23d-activation-").FullName;
        internal readonly Clock Time = new();
        internal readonly Sink Desktop = new();
        internal readonly List<BridgeEnvelope> Events = [];
        internal readonly NotificationSettingsBridgeDispatcher Settings;
        internal BridgeAccountContext Owner = new("fixture", "scm", "synthetic-first");
        internal long Generation = 1;
        internal bool Online = true;
        internal int HostEvents;
        private long _sequence, _id;

        internal Fixture(bool activationEnabled = true)
        {
            File.WriteAllText(Path.Combine(Root, "notification-settings.v1.json"),
                """{"schemaVersion":1,"revision":0,"inAppEnabled":true,"position":"bottomRight","preview":"sourceOnly","windowsEnabled":true,"tradeWindowsEnabled":true}""");
            Settings = new(Root, () => Generation, () => true, desktop: Desktop, time: Time,
                activationEvent: activationEnabled ? (g, payload) =>
                    BridgeEnvelope.Event("notificationSettings.activated", g, ++_sequence, payload) : null,
                hostEvent: (g, name, payload) => {
                    HostEvents++;
                    throw new InvalidOperationException("Trade must not use generic HostEvent");
                });
            Settings.EventReady += Events.Add;
        }

        internal async Task<DesktopNotification> Present(string? reference, bool chat = false)
        {
            var owner = Owner;
            await Settings.PresentTradeAsync(owner, Generation,
                new("fixture-event-" + ++_id, chat, reference, 4, "", "Aurora", "", ""),
                () => Online && Owner == owner);
            return Desktop.Cards.Last();
        }

        internal async Task<BridgeEnvelope> Consume(DesktopNotification card, long? generation = null)
            => (await Settings.DispatchAsync(BridgeEnvelope.Request("notificationSettings.consumeActivation",
                Guid.NewGuid().ToString("N"), generation ?? Generation,
                new { schemaVersion = 1, activationId = card.Id.ToString("N") }))).Response;

        public void Dispose()
        {
            Settings.Dispose();
            Directory.Delete(Root, true);
        }
    }

    internal static async Task<int> Run()
    {
        var checks = 0;
        void Check(bool valid, string label)
        {
            if (!valid) throw new InvalidOperationException("CX-T23d " + label);
            checks++;
        }
        static bool Absent(JsonElement payload, string key) =>
            !payload.TryGetProperty(key, out var value) || value.ValueKind == JsonValueKind.Null;
        void Empty(BridgeEnvelope response, string label) => Check(response.Status == "ok" &&
            response.Payload.GetProperty("schemaVersion").GetInt32() == 1 &&
            Absent(response.Payload, "destination") && Absent(response.Payload, "ref"), label);

        using (var f = new Fixture())
        {
            foreach (var (chat, reference, destination) in new[] {
                (false, new string('a', 32), "trade"),
                (true, new string('b', 32), "tradeChat"),
                (false, (string?)null, "myTrades"),
            })
            {
                var card = await f.Present(reference, chat);
                var before = f.Events.Count;
                Check(card.Activated is not null, "native card has activation callback");
                card.Activated!();
                card.Activated!();
                Check(f.Events.Count == before + 1 && f.HostEvents == 0, "one shared event per card, zero HostEvent calls");
                var click = f.Events.Last();
                Check(click.Name == "notificationSettings.activated" && click.AccountContext is null &&
                    click.SessionGeneration == f.Generation, "canonical device event envelope");
                Check(click.Payload.EnumerateObject().Select(p => p.Name).Order().SequenceEqual(new[] { "activationId", "schemaVersion" }) &&
                    click.Payload.GetProperty("schemaVersion").GetInt32() == 1 &&
                    click.Payload.GetProperty("activationId").GetString() == card.Id.ToString("N"),
                    "event carries only schemaVersion and activationId");
                var forged = (await f.Settings.DispatchAsync(BridgeEnvelope.Request("notificationSettings.consumeActivation",
                    "forged", f.Generation, new { schemaVersion = 1, activationId = new string('f', 32) }))).Response;
                Empty(forged, "forged id cannot consume or disclose pending ref");
                var response = await f.Consume(card);
                Check(response.Status == "ok" && response.AccountContext is null &&
                    response.Payload.GetProperty("schemaVersion").GetInt32() == 1 &&
                    response.Payload.GetProperty("destination").GetString() == destination, "compatible consume destination");
                if (reference is null) Check(Absent(response.Payload, "ref"), "myTrades omits ref");
                else Check(response.Payload.GetProperty("ref").GetString() == reference &&
                    reference.Length == 32 && reference.All(char.IsAsciiHexDigit), "consume returns opaque hex ref");
                Check(Absent(response.Payload, "transactionRef") && Absent(response.Payload, "conversationRef"),
                    "single ref field replaces direct-event routing fields");
                Empty(await f.Consume(card), "second consume returns no destination or ref");
                card.Activated!();
                Check(f.Events.Count == before + 1, "consumed card cannot recreate an activation");
                if (reference is not null)
                    Check(!Directory.EnumerateFiles(f.Root, "*", SearchOption.AllDirectories)
                        .Select(File.ReadAllText).Any(text => text.Contains(reference, StringComparison.Ordinal)),
                        "reference is never persisted in settings or diagnostic files");
            }

            var first = await f.Present(new string('c', 32)); first.Activated!();
            var second = await f.Present(new string('d', 32)); second.Activated!();
            first.Activated!();
            Empty(await f.Consume(first), "shared slot replaces old intent; old card cannot restore it");
            var concurrent = await Task.WhenAll(f.Consume(second), f.Consume(second));
            Check(concurrent.Count(r => !Absent(r.Payload, "destination")) == 1 &&
                concurrent.Count(r => !Absent(r.Payload, "ref")) == 1, "only one competing consume gets routing data");

            var nearExpiry = await f.Present(new string('e', 32)); nearExpiry.Activated!();
            f.Time.Seconds += 29;
            Check((await f.Consume(nearExpiry)).Payload.GetProperty("destination").GetString() == "trade", "valid before 30 seconds");
            foreach (var elapsed in new[] { 30, 31 })
            {
                var expired = await f.Present(new string('e', 32)); expired.Activated!();
                f.Time.Seconds += elapsed;
                Empty(await f.Consume(expired), "at or after 30 seconds activation is unavailable");
                Empty(await f.Consume(expired), "expired ref cannot reappear on retry");
            }

            var accountCard = await f.Present(new string('a', 32)); accountCard.Activated!();
            f.Owner = f.Owner with { Subject = "synthetic-second" };
            Empty(await f.Consume(accountCard), "account switch invalidates already-clicked intent through Current");

            var generationCard = await f.Present(new string('b', 32)); generationCard.Activated!();
            f.Generation++;
            Empty(await f.Consume(generationCard), "new generation cannot consume old activation even with same owner");
            var stale = await f.Consume(generationCard, f.Generation - 1);
            Check(stale.Status != "ok" && Absent(stale.Payload, "ref"), "stale request preserves protocol rejection");

            var resetCard = await f.Present(new string('c', 32)); resetCard.Activated!();
            f.Settings.Reset();
            Empty(await f.Consume(resetCard), "dispatcher reset clears pending routing data");
            var retiredCard = await f.Present(new string('d', 32)); retiredCard.Activated!();
            f.Settings.InvalidateTrade();
            Empty(await f.Consume(retiredCard), "trade retirement invalidates pending ref");
            var offlineCard = await f.Present(new string('e', 32)); offlineCard.Activated!();
            f.Online = false;
            Empty(await f.Consume(offlineCard), "source authority is checked again at consume");
            f.Online = true;
            Empty(await f.Consume(offlineCard), "restoring authority cannot revive rejected activation");
        }
        using (var f = new Fixture(activationEnabled: false))
        {
            var card = await f.Present(new string('a', 32));
            Check(card.Activated is null && f.HostEvents == 0 && f.Events.Count == 0,
                "missing activation owner never falls back to HostEvent");
        }
        Console.WriteLine($"PASS CX-T23d shared trade activation assertions: {checks} passed, 0 failed");
        return checks;
    }
}
