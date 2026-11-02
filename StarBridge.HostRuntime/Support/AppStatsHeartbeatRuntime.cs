using System.Diagnostics;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.Core.Presence;
using StarBridge.HostRuntime.Lifecycle;
using StarBridge.HostRuntime.Overlay;

namespace StarBridge.HostRuntime.Support;

/// <summary>App-wide usage heartbeat; visibility controls aggregate online counting only.</summary>
public sealed class AppStatsHeartbeatRuntime : IDisposable
{
    private static readonly TimeSpan Interval = TimeSpan.FromSeconds(30);
    private readonly Uri? _origin;
    private readonly IInformationOverlayUsageMeter? _meter;
    private readonly DeviceNetworkAdmission _network;
    private readonly Func<PlayerPresenceVisibilityMode> _visibility;
    private readonly string? _version;
    private readonly TimeProvider _time;
    private readonly string _dataRoot;
    private readonly HttpClient _client;
    private readonly Action<string> _diagnostic;
    private readonly CancellationTokenSource _stop = new();
    private readonly CancellationToken _stopToken;
    private readonly ITimer _timer;
    private string? _clientId;
    private long _pending;
    // Drop the first mixed interval after a rejected/cancelled/offline sample.
    private bool _sampleAllowed = true;
    private object? _sampleEpoch;
    private readonly RelayCapability _capability;
    private DateTimeOffset _v2RetryAtUtc;
    private int _busy;
    private int _disposed;

    public AppStatsHeartbeatRuntime(Uri? origin, IInformationOverlayUsageMeter? meter,
        DeviceNetworkAdmission network, string? version, TimeProvider timeProvider, string dataRoot,
        HttpMessageHandler? handler = null, Action<string>? diagnostic = null,
        Func<PlayerPresenceVisibilityMode>? visibility = null, RelayCapability? capability = null)
    {
        _origin = origin;
        _capability = capability ?? new RelayCapability();
        _meter = meter;
        _network = network;
        _visibility = visibility ?? (() => PlayerPresenceVisibilityMode.Online);
        _version = version;
        _time = timeProvider;
        _dataRoot = dataRoot;
        _diagnostic = diagnostic ?? (message => Trace.WriteLine(message));
        _client = new(handler ?? new HttpClientHandler { AllowAutoRedirect = false, UseCookies = false })
        { Timeout = TimeSpan.FromSeconds(10) };
        _stopToken = _stop.Token;
        // Busy ticks are skipped; the meter is drained by the next admitted tick.
        _timer = _time.CreateTimer(state => { _ = Task.Run(HeartbeatAsync); }, null, Interval, Interval);
    }

    private bool CountOnline() => PlayerPresence.DecideSharing(
        PlayerPresenceKind.AppOnline, _visibility()).CanPublishRealtime;

    internal async Task HeartbeatAsync()
    {
        if (Volatile.Read(ref _disposed) != 0 || Interlocked.CompareExchange(ref _busy, 1, 0) != 0) return;
        var previousPending = _pending;
        var sending = false;
        try
        {
            _stopToken.ThrowIfCancellationRequested();
            // Always drain, even when device admission forbids sending. Otherwise the
            // meter would carry excluded offline usage into a later connected request.
            var seconds = Math.Clamp(_meter?.TakeOpenSeconds() ?? 0, 0, 300);
            var includeSample = _sampleAllowed;
            _sampleAllowed = false;
            if (_origin is null) return;
            using var work = _network.Enter(_stopToken);
            if (work is null) return;
            includeSample &= _sampleEpoch is not null && ReferenceEquals(_sampleEpoch, work.Epoch);
            _sampleEpoch = work.Epoch;
            _sampleAllowed = true;
            using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(10), _time);
            using var deadline = CancellationTokenSource.CreateLinkedTokenSource(_stopToken, work.Token, timeout.Token);
            var countOnline = CountOnline();
            var now = _time.GetUtcNow();
            var useV2 = now >= _v2RetryAtUtc;
            if (!useV2 && !countOnline) return; // Drain new usage, retain earlier legal pending.
            _pending = Math.Min(300, previousPending + (includeSample ? seconds : 0));
            _clientId ??= AppStatsClientId.LoadOrCreate(_dataRoot);
            var delta = Math.Min(_pending, 300);
            deadline.Token.ThrowIfCancellationRequested();
            work.RequireCurrent();
            sending = true;
            using var modern = useV2 ? await SendHeartbeatAsync(2, delta, countOnline, deadline.Token)
                .ConfigureAwait(false) : null;
            deadline.Token.ThrowIfCancellationRequested();
            work.RequireCurrent();
            if (modern?.StatusCode == System.Net.HttpStatusCode.NotFound)
            {
                _v2RetryAtUtc = now.AddMinutes(10);
                useV2 = false;
            }
            // Only the new route can consume hidden usage. A cached GET/protocol
            // declaration never grants permission to send it to the legacy route.
            if (!useV2 && (!countOnline || !CountOnline()))
            {
                _pending = previousPending;
                return;
            }
            using var legacy = !useV2 ? await SendHeartbeatAsync(1, delta, true, deadline.Token)
                .ConfigureAwait(false) : null;
            var response = legacy ?? modern!;
            deadline.Token.ThrowIfCancellationRequested();
            work.RequireCurrent();
            // An HTTP error proves connectivity: keep the sample for a later retry.
            if (!response.IsSuccessStatusCode)
            {
                Diagnose("HttpStatus");
                return;
            }
            _capability.ObserveLegacy(); // An empty legacy success must also revoke a previous v2 capability.
            long accepted = delta; // Older servers acknowledged the whole request.
            var body = await response.Content.ReadAsStringAsync(deadline.Token).ConfigureAwait(false);
            if (!string.IsNullOrWhiteSpace(body))
            {
                using var json = JsonDocument.Parse(body);
                _capability.Observe(json.RootElement);
                if (useV2 && json.RootElement.TryGetProperty("overlayUsageSecondsAccepted", out var value) &&
                    value.ValueKind != JsonValueKind.Null)
                    accepted = Math.Clamp(value.GetInt64(), 0, delta);
            }
            deadline.Token.ThrowIfCancellationRequested();
            work.RequireCurrent();
            _pending -= accepted;
        }
        catch (Exception error)
        {
            // A transport failure invalidates only this sample, never prior connected
            // pending. Include read failures and cancellation during response bodies.
            if (error is HttpRequestException or OperationCanceledException || sending && error is IOException)
            {
                _pending = previousPending;
                _sampleAllowed = false;
            }
            Diagnose(error.GetType().Name);
        }
        finally { Volatile.Write(ref _busy, 0); }
    }

    private async Task<HttpResponseMessage> SendHeartbeatAsync(int protocol, long delta, bool countOnline,
        CancellationToken token)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, new Uri(_origin!,
            protocol == 2 ? "api/app-stats/v2/heartbeat" : "api/app-stats/heartbeat"))
        {
            Content = JsonContent.Create(new
            {
                clientId = _clientId, version = _version,
                overlayActive = _meter?.IsOverlayOpen ?? false,
                overlayUsageSecondsDelta = delta, countOnline, protocol
            })
        };
        return await _client.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, token).ConfigureAwait(false);
    }

    // Shared only by device-scoped heartbeat and read-only home stats for this
    // relay origin. No account identity, usage or presence is stored here.
    public sealed class RelayCapability
    {
        private int _protocol; // Zero means not yet observed.
        internal int? Protocol => Volatile.Read(ref _protocol) is var value && value != 0 ? value : null;
        internal void ObserveLegacy() => Volatile.Write(ref _protocol, 1);
        internal void Observe(JsonElement body)
        {
            var protocol = body.TryGetProperty("heartbeatProtocol", out var value) &&
                value.ValueKind == JsonValueKind.Number && value.TryGetInt32(out var parsed) ? parsed : 1;
            Volatile.Write(ref _protocol, Math.Max(1, protocol));
        }
    }

    private void Diagnose(string type)
    {
        // Never include a URI, body, client ID or exception message in diagnostics.
        if (Volatile.Read(ref _disposed) == 0)
            try { _diagnostic("app-stats heartbeat failed: " + type); } catch { }
    }

    public void Dispose()
    {
        if (Interlocked.Exchange(ref _disposed, 1) != 0) return;
        _timer.Dispose();
        try { _stop.Cancel(); } catch { }
        _client.Dispose();
        _stop.Dispose();
    }
}
