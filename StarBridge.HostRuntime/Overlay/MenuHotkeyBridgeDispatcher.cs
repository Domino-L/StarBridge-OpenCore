namespace StarBridge.HostRuntime.Overlay;

using System.Text.Json;
using StarBridge.NativeBridge;
using StarBridge.HostRuntime.Settings;

/// <summary>Authenticated primary-to-native lease; no polling or second input
/// listener. Raw input is only an intent, never authority to open a renderer.</summary>
public sealed class MenuHotkeyBridgeDispatcher(
    IMenuHotkeyRuntime runtime,
    Func<(string? OwnerKey, long Generation)> scope,
    Func<long, object, BridgeEnvelope> eventFactory,
    int clientProcessId,
    IMenuHotkeyPreferences? preferences = null) : IBridgeRequestDispatcher
{
    public const string Capability = "menuHotkey.runtime";
    public const string IntentEvent = "menuHotkey.intent";
    private readonly SemaphoreSlim _gate = new(1, 1);
    private Lease? _lease;
    private long _lastClient;
    private volatile bool _disposed;
    public event Action<BridgeEnvelope>? EventReady;
    public bool IsMenuVisible
    {
        get
        {
            var lease = Volatile.Read(ref _lease);
            return lease is not null && Current(lease) && lease.Presentation.Visible;
        }
    }

    private sealed class Lease(long client, string owner, long generation)
    {
        public readonly long Client = client;
        public readonly string Owner = owner;
        public readonly long Generation = generation;
        public MenuHotkeyRegistration Registration = null!;
        public readonly MenuWindowPresentationState Presentation = new();
    }

    private bool Current(Lease lease)
    {
        var current = scope();
        return !_disposed && ReferenceEquals(Volatile.Read(ref _lease), lease) &&
            current.OwnerKey == lease.Owner && current.Generation == lease.Generation;
    }

    public async ValueTask<BridgeDispatchBatch> DispatchAsync(BridgeEnvelope request,
        CancellationToken cancellationToken = default)
    {
        try { await _gate.WaitAsync(cancellationToken).ConfigureAwait(false); }
        catch (OperationCanceledException) { return new(BridgeEnvelope.CancelledResponse(request), []); }
        Lease? created = null;
        try
        {
            BridgeEnvelopeValidator.ValidateWireShape(request);
            BridgeEnvelopeValidator.RequireCurrentVersion(request);
            var current = scope();
            if (_disposed || current.OwnerKey is null || request.SessionGeneration != current.Generation)
                return Error(request, "menuHotkey.session_unavailable");
            var data = request.Payload;
            if (request.MessageType != BridgeMessageTypes.Request || request.AccountContext is not null ||
                data.ValueKind != JsonValueKind.Object || Number(data, "schemaVersion") != 1 ||
                Number(data, "client") is not (> 0 and <= 9007199254740991))
                return Error(request, BridgeErrorCodes.InvalidEnvelope);
            var client = Number(data, "client");
            if (request.Name == "menuHotkey.attach")
            {
                if (!Fields(data, "schemaVersion", "client", "binding", "enabled", "closeWithHotkey") ||
                    !data.TryGetProperty("binding", out var text) || text.ValueKind != JsonValueKind.String ||
                    text.GetString() is not { Length: > 0 and <= 64 } binding ||
                    !Boolean(data, "enabled", out var enabled) || !Boolean(data, "closeWithHotkey", out var close))
                    return Error(request, BridgeErrorCodes.InvalidEnvelope);
                if (preferences is not null)
                {
                    var saved = preferences.ReadHotkey().Options;
                    binding = saved.Binding;
                    enabled = saved.Enabled;
                    close = saved.CloseWithHotkey;
                }
                var lease = _lease;
                if (lease is null || lease.Client != client || !Current(lease))
                {
                    if (client <= _lastClient) return Error(request, "menuHotkey.stale_client");
                    lease = new(client, current.OwnerKey, current.Generation);
                    created = lease;
                    lease.Registration = new(binding, enabled, close, clientProcessId,
                        () => Current(lease), intent => Publish(lease, intent));
                    _lastClient = client;
                    Volatile.Write(ref _lease, lease);
                }
                else if (lease.Registration.Binding != binding || lease.Registration.Enabled != enabled ||
                    lease.Registration.CloseWithHotkey != close)
                    return Error(request, "menuHotkey.stale_client");
                var state = await runtime.ConfigureMenuHotkeyAsync(lease.Registration, cancellationToken).ConfigureAwait(false);
                if (!Current(lease)) return Error(request, "menuHotkey.session_unavailable");
                return new(BridgeEnvelope.Response(request, new { schemaVersion = 1, state }, preserveRequestAccountContext: false), []);
            }
            var active = _lease;
            if (active is null || active.Client != client || !Current(active))
                return Error(request, "menuHotkey.stale_client");
            if (request.Name is "menuHotkey.settings.get" or "menuHotkey.settings.update")
                return await SettingsAsync(request, active, cancellationToken).ConfigureAwait(false);
            if (request.Name == "menuHotkey.detach" && Fields(data, "schemaVersion", "client"))
            {
                Volatile.Write(ref _lease, null);
                await runtime.ConfigureMenuHotkeyAsync(null, cancellationToken).ConfigureAwait(false);
            }
            else if (request.Name == "menuHotkey.window" &&
                Fields(data, "schemaVersion", "client", "request", "phase", "window") &&
                Number(data, "request") is > 0 and <= 9007199254740991 &&
                Number(data, "window") is >= 0 and <= 9007199254740991 &&
                data.TryGetProperty("phase", out var phase) && phase.ValueKind == JsonValueKind.String &&
                phase.GetString() is "opening" or "visible" or "closed")
            {
                var opening = Number(data, "request");
                var state = phase.GetString()!;
                var window = Number(data, "window");
                // Closing revokes visibility even if native cleanup later fails.
                if (state == "closed") active.Presentation.Observe(opening, state, window);
                await runtime.UpdateMenuWindowAsync(active.Registration, Number(data, "request"),
                    phase.GetString()!, Number(data, "window"), cancellationToken).ConfigureAwait(false);
                if (Current(active) && !cancellationToken.IsCancellationRequested)
                    active.Presentation.Observe(opening, state, window);
            }
            else return Error(request, BridgeErrorCodes.InvalidEnvelope);
            return new(BridgeEnvelope.Response(request, new { schemaVersion = 1 }, preserveRequestAccountContext: false), []);
        }
        catch (OperationCanceledException)
        {
            RevokeFailedAttach(created);
            return new(BridgeEnvelope.CancelledResponse(request), []);
        }
        catch (BridgeProtocolException) { return Error(request, BridgeErrorCodes.InvalidEnvelope); }
        catch { RevokeFailedAttach(created); return Error(request, "menuHotkey.unavailable"); }
        finally { _gate.Release(); }
    }

    private async Task<BridgeDispatchBatch> SettingsAsync(BridgeEnvelope request, Lease lease, CancellationToken token)
    {
        if (preferences is null) return Error(request, "menuHotkey.preferences_unavailable");
        var data = request.Payload;
        var saved = preferences.ReadHotkey();
        if (request.Name == "menuHotkey.settings.get")
        {
            if (!Fields(data, "schemaVersion", "client")) return Error(request, BridgeErrorCodes.InvalidEnvelope);
            var state = await runtime.ConfigureMenuHotkeyAsync(lease.Registration, token).ConfigureAwait(false);
            return Current(lease) ? SettingsResponse(request, saved, state) : Error(request, "menuHotkey.session_unavailable");
        }
        if (!Fields(data, "schemaVersion", "client", "expectedRevision", "binding", "enabled", "closeWithHotkey") ||
            Number(data, "expectedRevision") < 0 || !data.TryGetProperty("binding", out var text) ||
            text.ValueKind != JsonValueKind.String || text.GetString() is not { } binding ||
            !Boolean(data, "enabled", out var enabled) || !Boolean(data, "closeWithHotkey", out var close))
            return Error(request, BridgeErrorCodes.InvalidEnvelope);
        var options = new MenuHotkeyOptions(binding, enabled, close);
        try { options.Validate(); }
        catch (ArgumentException) { return Error(request, "menuHotkey.invalid"); }
        if (Number(data, "expectedRevision") != saved.Revision) return Error(request, "menuPreferences.revision_conflict");
        var previous = lease.Registration;
        var next = previous with { Binding = binding, Enabled = enabled, CloseWithHotkey = close };
        var committed = false;
        try
        {
            var state = await runtime.ConfigureMenuHotkeyAsync(next, token).ConfigureAwait(false);
            token.ThrowIfCancellationRequested();
            if (!Current(lease)) return Error(request, "menuHotkey.session_unavailable");
            if (state is not ("registered" or "disabled")) return Error(request, "menuHotkey." + state);
            saved = preferences.SaveHotkey(saved.Revision, options);
            lease.Registration = next;
            committed = true;
            return SettingsResponse(request, saved, state);
        }
        catch (ApplicationPreferencesException error) { return Error(request, error.Code); }
        finally
        {
            // Runtime rejection, canceled saves and disk/CAS failures do not
            // replace the last working key. Cleanup must not use canceled token.
            if (!committed)
                await runtime.ConfigureMenuHotkeyAsync(Current(lease) ? previous : null).ConfigureAwait(false);
        }
    }

    private static BridgeDispatchBatch SettingsResponse(BridgeEnvelope request, MenuHotkeyPreferences saved, string state) =>
        new(BridgeEnvelope.Response(request, new { schemaVersion = 1, revision = saved.Revision,
            binding = saved.Options.Binding, enabled = saved.Options.Enabled,
            closeWithHotkey = saved.Options.CloseWithHotkey, state }, preserveRequestAccountContext: false), []);

    private void RevokeFailedAttach(Lease? created)
    {
        if (created is null) return;
        Interlocked.CompareExchange(ref _lease, null, created);
        _ = ResetAsync();
    }

    private void Publish(Lease lease, MenuHotkeyIntent intent)
    {
        if (!Current(lease)) return;
        var envelope = eventFactory(lease.Generation, new
        {
            schemaVersion = 1, client = lease.Client, action = intent.Action,
            request = intent.Request, targetWindow = intent.TargetWindow, targetProcessId = intent.TargetProcessId
        });
        if (Current(lease)) EventReady?.Invoke(envelope);
    }

    // AccountChanged calls this directly, even when no UI is watching events.
    // Revoke synchronously, then serialize native cleanup with any new attach.
    public void Invalidate()
    {
        Interlocked.Exchange(ref _lease, null);
        _ = ResetAsync();
    }
    private async Task ResetAsync()
    {
        await _gate.WaitAsync().ConfigureAwait(false);
        try { if (!_disposed) await runtime.ConfigureMenuHotkeyAsync(_lease?.Registration).ConfigureAwait(false); }
        catch { /* The runtime may already be shutting down. Authority is gone. */ }
        finally { _gate.Release(); }
    }
    private static bool Fields(JsonElement data, params string[] names) =>
        data.EnumerateObject().Count() == names.Length && data.EnumerateObject().All(p => names.Contains(p.Name));
    private static long Number(JsonElement data, string name) =>
        data.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.Number && value.TryGetInt64(out var number) ? number : -1;
    private static bool Boolean(JsonElement data, string name, out bool result)
    {
        result = data.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.True;
        return value.ValueKind is JsonValueKind.True or JsonValueKind.False;
    }
    private static BridgeDispatchBatch Error(BridgeEnvelope request, string code) =>
        new(BridgeEnvelope.ErrorResponse(request, new(code, "Menu shortcut is unavailable.", true)), []);
    public void Dispose()
    {
        _disposed = true;
        Interlocked.Exchange(ref _lease, null);
        // Native remains owned/disposed by the information-overlay dispatcher.
        try { runtime.ConfigureMenuHotkeyAsync(null).AsTask().GetAwaiter().GetResult(); }
        catch { }
    }
}
