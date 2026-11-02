using System.Net;

internal static partial class AccountPreferenceActionTests
{
    internal static async Task<string> PreferenceConfirmationWire()
    {
        using var f = new Fixture();
        async Task<StarBridge.NativeBridge.BridgeEnvelope> Read(string name) =>
            (await f.Send(name, new { schemaVersion = 1 })).Response;
        var current = await Read("account.getCurrent");
        var identity = await Read("gameIdentity.getPolicy");
        var live = await Read("profile.getSelf");
        var directoryReadsAfterPreparation = 0;
        f.Handler.DirectoryReply = (_, _) => {
            directoryReadsAfterPreparation++;
            throw new IOException("synthetic unavailable auxiliary directory");
        };
        var saved = (await f.Send("profile.patchPreferences", new { schemaVersion = 1, patch = new { locale = "en-US" } })).Response;
        var cachedAfterSaved = await Read("profile.readDisplayCache");
        Equal("ok", saved.Status, "wire must contain an actual confirmed save");
        Equal(0, directoryReadsAfterPreparation, "wire save cannot fetch auxiliary directory");
        return System.Text.Json.JsonSerializer.Serialize(new { current, identity, live, saved, cachedAfterSaved,
            counts = new { patches = f.Handler.Patches, authorizations = f.Authorization.Calls, directoryReadsAfterPreparation } },
            StarBridge.NativeBridge.BridgeProtocol.JsonOptions);
    }

    internal static async Task CancelledConfirmationDoesNotReplayWrite()
    {
        using var f = new Fixture();
        f.Cache.Save(f.Route, f.Handler.Profile, DateTimeOffset.UtcNow.AddHours(-1));
        using var cancelled = new CancellationTokenSource();
        f.Handler.ReadReply = (_, _) => {
            cancelled.Cancel();
            return Task.FromResult(JsonRead(f.Handler.Profile));
        };
        var request = StarBridge.NativeBridge.BridgeEnvelope.Request("profile.patchPreferences", "cancelled-confirmation", 7,
            new { schemaVersion = 1, patch = new { locale = "en-US" } }, f.Context);
        var response = (await f.Runtime.DispatchAsync(request, cancelled.Token)).Response;
        Equal("cancelled", response.Status, "caller cancellation during confirmation is not reported as success");
        Equal("zh-CN", f.Cache.Load(f.Route)?.Locale, "cancelled readback never claims confirmed durable data");
        Equal(1, f.Handler.Patches, "remote write is never automatically replayed after cancellation");
        f.Handler.ReadReply = null;
        var reconciled = (await f.Send("profile.getDisplayData", new { schemaVersion = 1 })).Response;
        Equal("en-US", reconciled.Payload.GetProperty("profile").GetProperty("locale").GetString(), "an ordinary read reconciles the committed remote value");
        Equal(1, f.Handler.Patches, "reconciliation is a read");
        Equal("refresh-kept", f.Vault.LoadRefreshToken("synthetic:owner"), "cancellation preserves credential");
        Equal(7L, f.Runtime.Generation, "cancellation is not an account transition");
    }

    internal static async Task ConfirmedWriteDoesNotReadDirectory()
    {
        using var f = new Fixture();
        Equal("ok", (await f.Send("profile.getTimeZoneDirectory", new { schemaVersion = 1 })).Response.Status, "reference options prepared before editing");
        var directoryReads = 0;
        f.Handler.DirectoryReply = (_, _) => {
            directoryReads++;
            throw new HttpRequestException("synthetic unavailable auxiliary directory", null, HttpStatusCode.ServiceUnavailable);
        };
        var response = (await f.Send("profile.patchPreferences", new { schemaVersion = 1, patch = new { locale = "en-US" } })).Response;
        Equal("ok", response.Status, "an auxiliary directory failure cannot hide confirmed remote data");
        Equal(0, directoryReads, "saving never starts another auxiliary directory request");
        Equal("en-US", response.Payload.GetProperty("profile").GetProperty("locale").GetString(), "return confirmed server value");
        var policy = response.Payload.GetProperty("preferencesPolicy");
        Equal(false, policy.GetProperty("directoryIncluded").GetBoolean(), "receipt explicitly omits independent reference options");
        Equal(0, policy.GetProperty("timeZones").GetArrayLength(), "receipt invents no reference directory");
        var observed = response.Payload.GetProperty("observedAtUtc").GetDateTimeOffset();
        Equal(observed, f.Cache.Load(f.Route)?.CachedAtUtc, "confirmation and durable display share observation time");
        Equal("en-US", f.Cache.Load(f.Route)?.Locale, "confirmed profile remains durable without directory IO");
        Equal(1, f.Handler.Patches, "one remote write");
        Equal(1, f.Authorization.Calls, "one explicit authorization");
        Equal(7L, f.Runtime.Generation, "no root account transition");
    }

    internal static async Task ConfirmedWriteSurvivesCacheFailure()
    {
        using var f = new Fixture();
        var previousTime = DateTimeOffset.UtcNow.AddHours(-1);
        f.Cache.Save(f.Route, f.Handler.Profile, previousTime);
        var cacheFile = Directory.GetFiles(Path.Combine(f.Root.FullName, "scm-profile-cache"), "*.json").Single();
        using (File.Open(cacheFile, FileMode.Open, FileAccess.Read, FileShare.Read))
        {
            var response = (await f.Send("profile.patchPreferences", new { schemaVersion = 1, patch = new { locale = "en-US" } })).Response;
            Equal("ok", response.Status, "a disk failure cannot hide a remotely confirmed preference write");
            Equal("en-US", response.Payload.GetProperty("profile").GetProperty("locale").GetString(), "show confirmed server value");
            var observed = response.Payload.GetProperty("observedAtUtc").GetDateTimeOffset();
            Equal(true, observed > previousTime, "confirmed write has a fresh observation");
            var retained = (await f.Send("profile.readDisplayCache", new { schemaVersion = 1 })).Response;
            Equal("en-US", retained.Payload.GetProperty("profile").GetProperty("locale").GetString(), "memory keeps the confirmation even when persistence failed");
            Equal(observed, retained.Payload.GetProperty("cachedAtUtc").GetDateTimeOffset(), "memory keeps original confirmation time");
        }
        Equal("zh-CN", f.Cache.Load(f.Route)?.Locale, "failed disk replacement does not claim durable success");
        Equal(previousTime, f.Cache.Load(f.Route)?.CachedAtUtc, "older disk timestamp is unchanged");
        f.Handler.ReadReply = (_, _) => Task.FromResult(new HttpResponseMessage(HttpStatusCode.ServiceUnavailable));
        var afterFailure = (await f.Send("profile.getSelf", new { schemaVersion = 1 })).Response;
        Equal("en-US", afterFailure.Payload.GetProperty("profile").GetProperty("locale").GetString(), "transient read never resurrects pre-write disk data");
        Equal(1, f.Handler.Patches, "cache failure never replays the remote write");
        Equal(1, f.Authorization.Calls, "cache failure never repeats interactive authorization");
        Equal(7L, f.Runtime.Generation, "confirmed write retains account generation");
        Equal("refresh-kept", f.Vault.LoadRefreshToken("synthetic:owner"), "confirmed write retains login credential");
    }
}
