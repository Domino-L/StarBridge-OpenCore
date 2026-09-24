using System.Text.Json;
using StarBridge.Core.Profiles;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Presence;
using StarBridge.HostRuntime.Support;
using StarBridge.NativeBridge;

internal static class GameplayExportIntegrationTests
{
    internal static async Task ReusesAccountOwner()
    {
        var root = Directory.CreateTempSubdirectory("starbridge-export-integration-");
        try
        {
            var dataRoot = Path.Combine(root.FullName, "data");
            var host = new LocalAccountHost();
            using var account = new AccountBridgeRuntime(host, gameplayTime: new GameplayTimeStore(dataRoot));
            var picker = new Picker { Destination = Path.Combine(root.FullName, "output.json") };
            account.ConfigureGameplayExportPicker(picker, dataRoot);
            using var dispatcher = new CompositeBridgeDispatcher(new Reject(), account, new Reject());
            BridgeEnvelope Request(string name, object body) => BridgeEnvelope.Request(name,
                Guid.NewGuid().ToString("N"), host.Generation, body, host.CurrentContext);
            var read = await dispatcher.DispatchAsync(Request("gameplayTime.read", new { schemaVersion = 1 }));
            Check(read.Response.Status == "ok", "existing runtime reads");
            // Save a real preference through the existing owner, then export its projection.
            await dispatcher.DispatchAsync(Request("gameplayTime.setConsent", new { schemaVersion = 1, allowed = false }));
            var result = await dispatcher.DispatchAsync(Request("gameplayTime.export", new { schemaVersion = 1, locale = "en" }));
            Check(result.Response.Payload.GetProperty("outcome").GetString() == "saved", "exact export route reaches picker");
            using var json = JsonDocument.Parse(File.ReadAllText(picker.Destination));
            Check(json.RootElement.GetProperty("recordingConsent").GetString() == "declined", "existing owner projection");
            Check(json.RootElement.GetProperty("totalSeconds").GetInt64() == read.Response.Payload.GetProperty("seconds").GetInt64(), "same statistics");
            Check(host.NetworkCalls == 0, "no SCM or remote request");
            picker.Destination = Path.Combine(root.FullName, "cancelled.json");
            picker.Hold = true;
            var pending = dispatcher.DispatchAsync(Request("gameplayTime.export", new { schemaVersion = 1, locale = "en" })).AsTask();
            await picker.Started.Task.WaitAsync(TimeSpan.FromSeconds(3));
            host.Switch();
            var cancelled = await pending.WaitAsync(TimeSpan.FromSeconds(3));
            Check(cancelled.Response.Status == BridgeResponseStatuses.Cancelled, "account event closes pending picker");
            Check(!File.Exists(picker.Destination), "account switch never writes");
            picker.Started = new(TaskCreationOptions.RunContinuationsAsynchronously);
            var closing = dispatcher.DispatchAsync(Request("gameplayTime.export", new { schemaVersion = 1, locale = "en" })).AsTask();
            await picker.Started.Task.WaitAsync(TimeSpan.FromSeconds(3));
            dispatcher.Dispose();
            Check((await closing.WaitAsync(TimeSpan.FromSeconds(3))).Response.Status == BridgeResponseStatuses.Cancelled, "shutdown closes picker");
            Check(!File.Exists(picker.Destination), "shutdown never writes");
        }
        finally { root.Delete(recursive: true); } // Only the unique test fixture.
    }

    private static void Check(bool value, string message) { if (!value) throw new InvalidOperationException(message); }
    private sealed class Picker : IGameplayExportPicker
    {
        internal string Destination = "";
        internal bool Hold;
        internal TaskCompletionSource Started = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public async Task<string?> ChooseNewJsonFileAsync(string name, string locale, CancellationToken token)
        {
            if (!Hold) return Destination;
            Started.TrySetResult();
            await Task.Delay(Timeout.Infinite, token);
            return null;
        }
    }
    private sealed class Reject : IBridgeRequestDispatcher
    {
        public event Action<BridgeEnvelope>? EventReady { add { } remove { } }
        public ValueTask<BridgeDispatchBatch> DispatchAsync(BridgeEnvelope request, CancellationToken token = default) => throw new InvalidOperationException("Wrong domain route");
        public void Dispose() { }
    }
    private sealed class LocalAccountHost : IAccountBridgeHost
    {
        public long Generation { get; private set; } = 1;
        public BridgeAccountContext? CurrentContext => new("test", "starbridge-relay-fixture", "owner-" + Generation);
        public event Action<long>? AccountChanged;
        internal int NetworkCalls;
        internal void Switch() { Generation++; AccountChanged?.Invoke(Generation); }
        private Task<T> Block<T>() { NetworkCalls++; throw new InvalidOperationException("Unexpected network access"); }
        public Task<AccountBridgeSessionProjection> GetCurrentAsync(CancellationToken t) => Block<AccountBridgeSessionProjection>();
        public Task<AccountBridgeSessionProjection> LoginAsync(CancellationToken t) => Block<AccountBridgeSessionProjection>();
        public Task CancelLoginAsync() => Task.CompletedTask;
        public Task LogoutAsync(BridgeAccountContext c, CancellationToken t) => Block<bool>();
        public Task<AccountBridgeProfileProjection> GetProfileAsync(BridgeAccountContext c, CancellationToken t) => Block<AccountBridgeProfileProjection>();
        public Task<PersonalProfileDocumentContract> GetPersonalProfileAsync(BridgeAccountContext c, CancellationToken t) => Block<PersonalProfileDocumentContract>();
        public Task<PersonalProfileDocumentContract> UpdatePersonalProfileAsync(BridgeAccountContext c, PersonalProfilePresentationUpdateContract p, CancellationToken t) => Block<PersonalProfileDocumentContract>();
        public Task<AccountBridgeOfficialFleetProjection> GetOfficialFleetAsync(BridgeAccountContext c, CancellationToken t) => Block<AccountBridgeOfficialFleetProjection>();
        public Task<AccountBridgeCompatibilityProjection> GetCompatibilityStateAsync(BridgeAccountContext c, CancellationToken t) => Block<AccountBridgeCompatibilityProjection>();
        public Task<AccountBridgeCompatibilityProjection> LinkLegacyAccountAsync(BridgeAccountContext c, AccountBridgeLegacyCredential? p, CancellationToken t) => Block<AccountBridgeCompatibilityProjection>();
        public Task<AccountBridgeCompatibilityProjection> CreateCompatibilityIdentityAsync(BridgeAccountContext c, CancellationToken t) => Block<AccountBridgeCompatibilityProjection>();
        public Task<AccountBridgeProfileProjection> PatchPreferencesAsync(BridgeAccountContext c, AccountBridgePreferencePatch p, CancellationToken t) => Block<AccountBridgeProfileProjection>();
        public Task<bool> ClearProfileCacheAsync(BridgeAccountContext c, CancellationToken t) => Block<bool>();
        public Task<AccountBridgeIdentityProjection> GetGameIdentityPolicyAsync(BridgeAccountContext c, CancellationToken t) => Block<AccountBridgeIdentityProjection>();
    }
}
