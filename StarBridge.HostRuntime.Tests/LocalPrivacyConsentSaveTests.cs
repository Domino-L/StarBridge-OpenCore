using System.Security.Cryptography;
using System.Text.Json;
using StarBridge.Core.Presence;
using StarBridge.HostRuntime.Privacy;
using StarBridge.NativeBridge;

internal static class LocalPrivacyConsentSaveTests
{
    private static readonly BridgeAccountContext Owner = new("test", "https://privacy.invalid", "consent-save-fixture");
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);
    private static LocalPrivacySettings Settings(bool enabled) => new(enabled,
        new(PlayerSharedStateFields.None, false, false, []), new(PlayerSharedStateFields.None, false));

    public static Task OrganizationSave()
    {
        // No file has neither a saved publication flag nor a durable pause.
        CheckOrganizationSave(null, false, null, false);
        CheckOrganizationSave(null, true, null, false);
        foreach (int? consent in new int?[] { null, 0, 1 })
        foreach (var enabled in new[] { false, true })
        foreach (var paused in new[] { false, true })
            CheckOrganizationSave(1, enabled, consent, paused);
        Console.WriteLine("PASS CX-CONSENT-FIX organization matrix: 14 cases with identical-operation retries");
        return Task.CompletedTask;
    }

    public static Task GlobalTransitions()
    {
        foreach (int? consent in new int?[] { null, 0, 1 })
        foreach (var beforeEnabled in new[] { false, true })
        foreach (var afterEnabled in new[] { false, true })
        foreach (var paused in new[] { false, true })
        {
            using var fixture = new Fixture();
            fixture.Seed(Settings(beforeEnabled), consent, paused);
            var store = new LocalPrivacyStore(fixture.Root);
            var operation = Guid.NewGuid().ToString("N");
            var submitted = Settings(afterEnabled);
            var saved = Save(store, 1, operation, submitted);
            var expectedConsent = beforeEnabled && !afterEnabled ? 0 : consent;
            fixture.CheckMetadata(expectedConsent, paused);
            var bytes = File.ReadAllBytes(fixture.Path);
            var retried = Save(store, 1, operation, submitted);
            Require(retried.Revision == saved.Revision && retried.SavedAt == saved.SavedAt && retried.OperationId == saved.OperationId,
                "Global retry preserves the committed snapshot.");
            Require(bytes.SequenceEqual(File.ReadAllBytes(fixture.Path)), "Global retry does not rewrite metadata.");
            fixture.CheckMetadata(expectedConsent, paused);
        }
        Console.WriteLine("PASS CX-CONSENT-FIX global matrix: 24 transitions with identical-operation retries");
        return Task.CompletedTask;
    }

    private static void CheckOrganizationSave(long? revision, bool enabled, int? consent, bool paused)
    {
        using var fixture = new Fixture();
        var original = Settings(enabled);
        if (revision is not null) fixture.Seed(original, consent, paused);
        var store = new LocalPrivacyStore(fixture.Root);
        Require(store.Read(Owner).Revision == (revision ?? 0), "Fixture is readable before save.");
        var submitted = original with { Communities = [new("fixture-community", DateTimeOffset.UnixEpoch.AddDays(1),
            PlayerSharedStateFields.Presence, true, false, [])] };
        var operation = Guid.NewGuid().ToString("N");
        var saved = Save(store, revision ?? 0, operation, submitted);
        fixture.CheckMetadata(consent, paused);
        Require(saved.Settings!.PublicationEnabled == enabled && saved.Settings.Communities!.Single().Code == "fixture-community",
            "Only the organization choice changes.");
        var bytes = File.ReadAllBytes(fixture.Path);
        var retried = Save(store, revision ?? 0, operation, submitted);
        Require(retried.Revision == saved.Revision && retried.SavedAt == saved.SavedAt && retried.OperationId == saved.OperationId,
            "Lost-response retry returns the same snapshot.");
        Require(bytes.SequenceEqual(File.ReadAllBytes(fixture.Path)), "Organization retry leaves the entire file unchanged.");
        fixture.CheckMetadata(consent, paused);
        var reopened = new LocalPrivacyStore(fixture.Root);
        Require(reopened.Read(Owner).Revision == saved.Revision && reopened.IsPublicationPaused(Owner) == paused &&
            reopened.HasPublicationConsent(Owner) == (consent == 1) && reopened.IsPublicationRevoked(Owner) == (consent == 0),
            "Reopening preserves consent semantics, pause and the saved revision.");
    }

    private static LocalPrivacySnapshot Save(LocalPrivacyStore store, long revision, string operation, LocalPrivacySettings settings)
    {
        var dispatcher = new LocalPrivacyDispatcher(store, () => (Owner, 1));
        var request = BridgeEnvelope.Request("privacy.localSave", Guid.NewGuid().ToString("N"), 1,
            new { schemaVersion = 1, expectedRevision = revision, operationId = operation, settings }, Owner);
        var response = dispatcher.Dispatch(request).Response;
        Require(response.Error is null, "Real local-save dispatcher succeeds: " + response.Error?.Code);
        return store.Read(Owner);
    }

    private static void Require(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException(message);
    }

    private sealed class Fixture : IDisposable
    {
        public string Root { get; } = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "consent-save-" + Guid.NewGuid().ToString("N"));
        public string Path => Directory.GetFiles(System.IO.Path.Combine(Root, "privacy-local-v1"), "*.json").Single();

        public void Seed(LocalPrivacySettings settings, int? consent, bool paused)
        {
            // Create the real account hash/path, then encode an existing schema-1
            // record independently, including legacy null consent with sharing off.
            new LocalPrivacyStore(Root).Save(Owner, 0, Guid.NewGuid().ToString("N"), settings, () => true);
            using var source = JsonDocument.Parse(File.ReadAllBytes(Path));
            var owner = source.RootElement.GetProperty("ownerHash").GetString()!;
            var snapshot = source.RootElement.GetProperty("snapshot").Deserialize<LocalPrivacySnapshot>(Json)!;
            var integrity = LegacyIntegrity(owner, snapshot, consent, paused);
            var file = new Dictionary<string, object?> { ["schemaVersion"] = 1, ["ownerHash"] = owner,
                ["snapshot"] = snapshot, ["integrity"] = integrity };
            if (consent is not null) file["consentVersion"] = consent;
            if (paused) file["publicationPaused"] = true;
            File.WriteAllBytes(Path, JsonSerializer.SerializeToUtf8Bytes(file, Json));
            CheckMetadata(consent, paused);
        }

        public void CheckMetadata(int? consent, bool paused)
        {
            using var file = JsonDocument.Parse(File.ReadAllBytes(Path));
            var value = file.RootElement;
            int? actual = value.TryGetProperty("consentVersion", out var version) ? version.GetInt32() : null;
            Require(actual == consent, $"ConsentVersion must stay {consent?.ToString() ?? "null"}; got {actual?.ToString() ?? "null"}.");
            Require((value.TryGetProperty("publicationPaused", out var pause) && pause.GetBoolean()) == paused,
                "Durable publication pause is preserved.");
            Require(value.GetProperty("schemaVersion").GetInt32() == 1, "Schema version remains 1.");
            var owner = value.GetProperty("ownerHash").GetString()!;
            var snapshot = value.GetProperty("snapshot").Deserialize<LocalPrivacySnapshot>(Json)!;
            Require(value.GetProperty("integrity").GetString() == LegacyIntegrity(owner, snapshot, consent, paused),
                "Written record retains the existing schema-1 integrity encoding.");
        }

        private static string LegacyIntegrity(string owner, LocalPrivacySnapshot snapshot, int? consent, bool paused)
        {
            var bytes = paused
                ? JsonSerializer.SerializeToUtf8Bytes(new { schemaVersion = 1, owner, snapshot, consentVersion = consent, publicationPaused = true }, Json)
                : consent is null
                    ? JsonSerializer.SerializeToUtf8Bytes(new { schemaVersion = 1, owner, snapshot }, Json)
                    : JsonSerializer.SerializeToUtf8Bytes(new { schemaVersion = 1, owner, snapshot, consentVersion = consent }, Json);
            return Convert.ToHexString(SHA256.HashData(bytes));
        }

        public void Dispose()
        {
            if (Directory.Exists(Root)) Directory.Delete(Root, true);
        }
    }
}
