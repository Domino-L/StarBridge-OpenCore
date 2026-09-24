using System.Text.Json;
using StarBridge.Core.Presence;
using StarBridge.HostRuntime.Privacy;
using StarBridge.HostRuntime.Presence;
using StarBridge.NativeBridge;

internal static class PrivacyConsentTests
{
    public static async Task Verify()
    {
        var root = Directory.CreateTempSubdirectory("starbridge-privacy-consent-").FullName;
        try
        {
            var owner = new BridgeAccountContext("test", "presence.invalid", "consent");
            var input = new PrivacyPublicationInput(owner, 1, "Fixture", true, null, GameLogSessionSnapshot.Empty);
            var store = new LocalPrivacyStore(root);
            Check(store.NeedsFirstChoice(owner), "new account needs a choice, without creating a record");
            var settings = new LocalPrivacySettings(true, new(PlayerSharedStateFields.Presence, false, true, []),
                new(PlayerSharedStateFields.None, false));
            var snapshot = store.Save(owner, 0, Guid.NewGuid().ToString("N"), settings, () => true);
            var path = Directory.GetFiles(Path.Combine(root, "privacy-local-v1"), "*.json").Single();
            var oldFile = File.ReadAllText(path);
            Check(!oldFile.Contains("consentVersion") && !store.HasPublicationConsent(owner), "old settings have no implicit consent");
            Check(!store.NeedsFirstChoice(owner), "old local choices are not a new-user onboarding prompt");
            var declinedOwner = owner with { Subject = "declined" };
            store.Save(declinedOwner, 0, Guid.NewGuid().ToString("N"), settings with { PublicationEnabled = false }, () => true);
            var restartedStore = new LocalPrivacyStore(root);
            Check(!restartedStore.NeedsFirstChoice(declinedOwner) && !restartedStore.HasPublicationConsent(declinedOwner),
                "decline survives restart without granting publication");
            var sent = new List<JsonElement>();
            var mode = PlayerPresenceVisibilityMode.Online;
            Task Send(PrivacyPublicationInput _, JsonElement payload, CancellationToken token)
            { sent.Add(payload.Clone()); return Task.CompletedTask; }
            PrivacyPublication Create() => new(new LocalPrivacyStore(root), () => input, Send, startTimer: false, visibility: () => mode);
            using (var first = Create())
            {
                input = input with { IdentityConfirmed = false };
                await first.ApplyAsync(owner, 1, 1, default);
                Check(store.HasPublicationConsent(owner) && sent.Count == 0, "first confirmation is remembered while identity verification is pending, without network writes");
                Check(first.StatusFor(owner).FirstUseRequired == false && first.StatusFor(declinedOwner).FirstUseRequired == false,
                    "confirmed and declined accounts do not prompt again");
                input = input with { IdentityConfirmed = true };
                await first.TickAsync();
                Check(first.Status.State == "applied", "first verification completion needs no second confirmation");
            }
            Check(store.HasPublicationConsent(owner) && store.Read(owner).Revision == snapshot.Revision &&
                store.Read(owner).SavedAt == snapshot.SavedAt, "confirmation preserves the editor revision and settings");
            foreach (var other in new[] { owner with { Subject = "other" }, owner with { Authority = "other" }, owner with { Environment = "other" } })
                Check(!store.HasPublicationConsent(other), "consent is isolated by full account scope");
            var disconnected = true;
            mode = PlayerPresenceVisibilityMode.Invisible;
            input = input with { IdentityConfirmed = false };
            using (var invisibleOutage = new PrivacyPublication(store, () => input,
                (current, payload, token) => disconnected ? Task.FromException(new HttpRequestException()) : Send(current, payload, token),
                startTimer: false, visibility: () => mode))
            {
                await invisibleOutage.TickAsync();
                Check(store.HasPublicationConsent(owner), "transient invisible withdrawal failure does not revoke remembered consent");
                disconnected = false;
                await invisibleOutage.TickAsync();
                Check(!sent[^1].GetProperty("online").GetBoolean(), "invisible can withdraw without game identity evidence");
            }
            input = input with { IdentityConfirmed = true };
            mode = PlayerPresenceVisibilityMode.Invisible;
            using (var invisible = Create())
            {
                var count = sent.Count;
                await invisible.TickAsync();
                await invisible.TickAsync();
                Check(sent.Count == count + 1 && !sent[^1].GetProperty("online").GetBoolean(), "invisible restart withdraws once and never publishes online");
                await invisible.ChangeVisibilityAsync(owner, 1, _ => { mode = PlayerPresenceVisibilityMode.Online; return Task.CompletedTask; }, default);
                Check(sent[^1].GetProperty("online").GetBoolean(), "leaving invisible resumes confirmed account without another apply");
                await invisible.StopAsync(default, explicitRequest: true);
            }
            Check(!store.HasPublicationConsent(owner), "explicit stop revokes persistent consent");
            Check(!store.NeedsFirstChoice(owner), "explicit stop never restarts onboarding");
            using (var stopped = Create())
            {
                var count = sent.Count;
                await stopped.TickAsync();
                Check(sent.Count == count, "stopped sharing remains stopped after restart");
                await stopped.ApplyAsync(owner, 1, 1, default);
                store.Save(owner, 1, Guid.NewGuid().ToString("N"), settings with { PublicationEnabled = false }, () => true);
                store.Save(owner, 2, Guid.NewGuid().ToString("N"), settings, () => true);
                await stopped.TickAsync();
                Check(!store.HasPublicationConsent(owner) && !sent[^1].GetProperty("online").GetBoolean(), "off then on before tick cannot resurrect revoked consent");
                await stopped.ApplyAsync(owner, 1, 3, default);
            }
            input = input with { IdentityConfirmed = false };
            using (var identity = Create())
            {
                var count = sent.Count;
                await identity.TickAsync();
                Check(sent.Count == count && identity.Status.State == "identityRequired", "restart waits for verified game identity");
                input = input with { IdentityConfirmed = true };
                await identity.TickAsync();
                Check(identity.Status.State == "applied", "verified identity automatically resumes existing consent");
            }
            var confirmedFile = File.ReadAllText(path);
            File.WriteAllText(path, oldFile.Replace("\"schemaVersion\":1", "\"consentVersion\":1,\"schemaVersion\":1"));
            try { store.HasPublicationConsent(owner); throw new Exception("Injected consent accepted"); }
            catch (LocalPrivacyException e) when (e.Code == "privacy_local.read_failed") { }
            File.WriteAllText(path, confirmedFile);
            using (var locked = new FileStream(path + ".lock", FileMode.Open, FileAccess.ReadWrite, FileShare.None))
            {
                try { store.SetPublicationConsent(owner, 3, false, () => true); throw new Exception("Locked consent overwritten"); }
                catch (LocalPrivacyException e) when (e.Code == "privacy_local.write_failed") { }
            }
            Check(File.ReadAllText(path) == confirmedFile, "exclusive writer preserves consent record");
            var checks = 0;
            try { store.SetPublicationConsent(owner, 3, false, () => ++checks < 2); throw new Exception("Changed account committed consent"); }
            catch (LocalPrivacyException e) when (e.Code == "privacy_local.account_changed") { }
            Check(File.ReadAllText(path) == confirmedFile && !Directory.EnumerateFiles(Path.GetDirectoryName(path)!, "*.tmp").Any(),
                "account change before commit preserves record and removes only own temporary file");
        }
        finally { Directory.Delete(root, true); }
    }

    private static void Check(bool value, string label)
    { if (!value) throw new Exception(label); Console.WriteLine("PASS Consent " + label); }
}
