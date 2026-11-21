using System.Text.Json;
using StarBridge.Core.Presence;
using StarBridge.HostRuntime.Privacy;
using StarBridge.NativeBridge;

internal static class OfficialFirstDefaultConsentTests
{
    internal static async Task Run()
    {
        foreach (var scenario in new[] { "unasked", "revoked", "paused", "invisible", "disabled" })
        {
            var root = Path.Combine(Path.GetTempPath(), "consent-b-" + Guid.NewGuid().ToString("N"));
            var store = new LocalPrivacyStore(root);
            var owner = new BridgeAccountContext("test", "https://privacy.invalid", "consent-b-synthetic");
            var target = new OfficialFleetRealtimeTarget("synthetic", 7, "TEST", "scm-observed-membership-row-v1:1");
            if (scenario != "unasked")
            {
                store.Save(owner, 0, Guid.NewGuid().ToString("N"), new(scenario != "disabled",
                    new(PlayerSharedStateFields.None, false, false, []), new(PlayerSharedStateFields.None, false), []), () => true);
                if (scenario == "revoked") store.SetPublicationConsent(owner, 1, false, () => true);
                if (scenario == "paused") store.SetPublicationPaused(owner, 1, true, () => true);
            }
            var bridge = new OfficialFleetRealtimePrivacyBridge(store, () => (owner, 1L),
                (_, _, _) => Task.FromResult(new OfficialRealtimeContextWire(4, "officialFleet:7", target, null, "initial", true)), () => true);
            var first = (await bridge.DispatchAsync(BridgeEnvelope.Request("privacy.officialFleetRead",
                Guid.NewGuid().ToString("N"), 1, new { schemaVersion = 1 }, owner), default)).Response;
            Check(first.Payload.GetProperty("choiceRequired").GetBoolean(), "never-chosen member");
            var saved = (await bridge.DispatchAsync(BridgeEnvelope.Request("privacy.officialFleetSave",
                Guid.NewGuid().ToString("N"), 1, new { schemaVersion = 1,
                    contextRef = first.Payload.GetProperty("contextRef").GetString(), expectedRevision = store.Read(owner).Revision,
                    operationId = Guid.NewGuid().ToString("N"), fields = 15 }, owner), default)).Response;
            Check(saved.Status == "ok" && !store.HasPublicationConsent(owner), "default save alone does not consent");
            var before = store.ReadPublicationMetadata(owner);
            var sends = 0;
            var input = new PrivacyPublicationInput(owner, 1, "Synthetic", true, "LIVE",
                new(new("connected", "US", "synthetic"), new("confirmed", "Test"), new("confirmed", "Test", "Test")),
                AppPresenceConfirmed: true);
            using var publisher = new PrivacyPublication(store, () => input, (_, _, _) => { sends++; return Task.CompletedTask; },
                startTimer: false, visibility: () => scenario == "invisible" ? PlayerPresenceVisibilityMode.Invisible : PlayerPresenceVisibilityMode.Online);
            // The client does not apply while the saved publication switch is off.
            if (store.Read(owner).Settings!.PublicationEnabled)
                await publisher.ApplyAsync(owner, 1, store.Read(owner).Revision, default, preservePause: true, firstOfficialDefault: true);
            var after = store.ReadPublicationMetadata(owner);
            Check(sends == (scenario == "unasked" ? 1 : 0), scenario + " send count");
            Check(after.ConsentVersion == (scenario == "unasked" ? 1 : before.ConsentVersion) &&
                after.PublicationPaused == before.PublicationPaused, scenario + " consent and pause");
            Check((int)store.Read(owner).Settings!.OfficialFleet!.Fields == 15, "all four retained");
            if (scenario == "unasked" && Environment.GetEnvironmentVariable("STARBRIDGE_CONSENT_B_FIXTURE_ROOT") is { Length: > 0 } export)
            {
                Directory.CreateDirectory(Path.Combine(export, "privacy-local-v1"));
                var file = Directory.GetFiles(Path.Combine(root, "privacy-local-v1"), "*.json").Single();
                File.Copy(file, Path.Combine(export, "privacy-local-v1", Path.GetFileName(file)), true);
                File.WriteAllText(Path.Combine(export, "expected-settings.json"), JsonSerializer.Serialize(store.Read(owner).Settings, LocalPrivacyStore.Json));
            }
        }
    }

    private static void Check(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException(message);
    }
}
