using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Net.NetworkInformation;
using System.Text.Json;

namespace StarBridge.HostRuntime.Sessions;

/// <summary>One generation of relay arbitration. No credentials are persisted here.
/// A pending claim gates writes until it succeeds; only a 404 enables old-relay
/// compatibility. Relay write guards arbitrate payloads without an extra read.</summary>
internal sealed class RelayDeviceSession : IDisposable
{
    private readonly TimeProvider _time;
    private static readonly TimeSpan ConnectedInterval = TimeSpan.FromSeconds(60);
    private static readonly TimeSpan FallbackInterval = TimeSpan.FromSeconds(15);
    private static readonly TimeSpan CompatibilityInterval = TimeSpan.FromMinutes(30);
    private readonly HttpClient _http;
    private readonly Uri _origin;
    private readonly SemaphoreSlim _gate = new(1, 1);
    private Run? _run;
    private Task _completion = Task.CompletedTask;
    internal Task StopCompletion => Volatile.Read(ref _completion);
    private bool _disposed;
    internal string DeviceId { get; }
    private sealed class Run(string mode, Func<string?> bearer, Action replaced, object? replacementGate)
    {
        // The Host supplies its realtime gate: callbacks and pause/stop share one
        // lock, without an inverse Host -> session / session -> Host lock order.
        internal readonly object StateGate = replacementGate ?? new object();
        internal volatile string? CredentialVersion;
        internal readonly string Mode = mode;
        internal readonly Func<string?> Bearer = bearer;
        internal readonly Action Replaced = replaced;
        internal readonly CancellationTokenSource Lifetime = new();
        internal readonly CancellationTokenSource MonitorStop = new();
        internal volatile bool Claimed, Unsupported, Ended, Unauthorized, Paused, Verified, RealtimeAvailable;
        internal long LastCheck;
        internal bool HasChecked;
        internal int ImmediateCheck;
        internal readonly SemaphoreSlim Wake = new(0, 1);
        internal long Epoch;
    }

    internal RelayDeviceSession(Uri origin, string deviceId, HttpMessageHandler? handler = null,
        TimeProvider? timeProvider = null)
    {
        if (!origin.IsAbsoluteUri || origin.UserInfo.Length != 0 || origin.Query.Length != 0 || origin.Fragment.Length != 0 ||
            (origin.Scheme != "https" && !(origin.Scheme == "http" && origin.IsLoopback))) throw new ArgumentException("Trusted origin required.");
        if (deviceId.Length is < 1 or > 128 || !deviceId.All(c => char.IsAsciiLetterOrDigit(c) || c is '_' or '-'))
            throw new ArgumentException("Invalid device ID.");
        _time = timeProvider ?? TimeProvider.System;
        NetworkChange.NetworkAvailabilityChanged += NetworkAvailabilityChanged;
        DeviceId = deviceId;
        _origin = origin;
        _http = new(handler ?? new HttpClientHandler { AllowAutoRedirect = false, UseCookies = false }, handler is null)
            { Timeout = TimeSpan.FromSeconds(2) };
    }

    internal void Start(string mode, Func<string?> bearer, Action replaced, object? replacementGate = null)
    {
        if (_disposed) return;
        Stop();
        var run = new Run(mode, bearer, replaced, replacementGate);
        Volatile.Write(ref _run, run);
        _completion = Task.WhenAll(_completion, Task.Run(() => MonitorAsync(run)));
    }
    internal void SetRealtimeAvailable(bool available)
    {
        var run = Volatile.Read(ref _run);
        if (run is null) return;
        run.RealtimeAvailable = available;
        Wake(run);
    }
    private void NetworkAvailabilityChanged(object? sender, NetworkAvailabilityEventArgs args)
    {
        if (args.IsAvailable) NetworkRestored();
    }
    internal void NetworkRestored()
    {
        var run = Volatile.Read(ref _run);
        if (run is null || !Current(run) || run.Paused) return;
        // Latch before waking, so recovery cannot send a payload before adjudication.
        if (!run.Unsupported) run.Verified = false;
        Interlocked.Exchange(ref run.ImmediateCheck, 1);
        Wake(run);
    }
    private static void Wake(Run run)
    {
        try { run.Wake.Release(); } catch (SemaphoreFullException) { }
    }
    private TimeSpan Remaining(Run run)
    {
        if (!run.HasChecked) return TimeSpan.Zero;
        var interval = run.Unsupported ? CompatibilityInterval : run.RealtimeAvailable ? ConnectedInterval : FallbackInterval;
        var remaining = interval - _time.GetElapsedTime(Interlocked.Read(ref run.LastCheck));
        return remaining > TimeSpan.Zero ? remaining : TimeSpan.Zero;
    }

    internal void Pause()
    {
        var run = Volatile.Read(ref _run);
        if (run is null) return;
        lock (run.StateGate)
        {
            if (!Current(run)) return;
            run.Paused = true;
            run.MonitorStop.Cancel();
        }
    }
    internal void Stop()
    {
        while (Volatile.Read(ref _run) is { } run)
        {
            lock (run.StateGate)
            {
                if (!ReferenceEquals(Volatile.Read(ref _run), run)) continue;
                Interlocked.Exchange(ref _run, null);
                run.Lifetime.Cancel();
                return;
            }
        }
    }
    private bool Current(Run run) => !_disposed && ReferenceEquals(Volatile.Read(ref _run), run) && !run.Ended;
    private void Replace(Run run)
    {
        lock (run.StateGate)
        {
            if (!Current(run) || run.Paused) return;
            run.Ended = true;
            run.Lifetime.Cancel();
            run.Replaced();
        }
    }

    internal Task<bool> CheckAsync(CancellationToken token = default) => CheckRunAsync(Volatile.Read(ref _run), token);
    private async Task<bool> CheckRunAsync(Run? run, CancellationToken token, bool onlyWhenDue = false)
    {
        if (run is null || !Current(run) || run.Paused) return false;
        using var lifetime = CancellationTokenSource.CreateLinkedTokenSource(token, run.Lifetime.Token);
        try
        {
            await _gate.WaitAsync(lifetime.Token).ConfigureAwait(false);
            try
            {
                if (!Current(run) || run.Paused) return false;
                // Explicit reconnect/network checks do not bypass the 30-minute
                // compatibility cooldown. Never GET current after claim returned 404.
                var immediate = Interlocked.Exchange(ref run.ImmediateCheck, 0) != 0;
                if (run.Unsupported && Remaining(run) > TimeSpan.Zero) return true;
                if (onlyWhenDue && !immediate && run.CredentialVersion == Version(run.Bearer()) && Remaining(run) > TimeSpan.Zero)
                    return run.Unsupported || run.Verified;
                var bearer = run.Bearer();
                if (string.IsNullOrWhiteSpace(bearer)) return false;
                // After a successful claim, never claim interactive again on reconnect.
                // A later manual login on another machine owns that decision.
                using var request = new HttpRequestMessage(run.Claimed ? HttpMethod.Get : HttpMethod.Post,
                    new Uri(_origin, run.Claimed ? "/api/session/v1/current" : "/api/session/v1/claim"));
                request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", bearer);
                if (!run.Claimed) request.Content = JsonContent.Create(new { schemaVersion = 1, deviceId = DeviceId, mode = run.Epoch > 0 ? "restore" : run.Mode });
                var version = Version(bearer);
                lock (run.StateGate)
                {
                    if (!Current(run) || run.Paused || version != Version(run.Bearer())) return false;
                    run.CredentialVersion = version;
                    run.Unauthorized = false;
                    run.Verified = false;
                }
                Interlocked.Exchange(ref run.LastCheck, _time.GetTimestamp());
                run.HasChecked = true;
                using var response = await _http.SendAsync(request, lifetime.Token).ConfigureAwait(false);
                lock (run.StateGate)
                {
                    if (!Current(run) || run.Paused || version != Version(run.Bearer())) return false;
                    run.Unauthorized = response.StatusCode == HttpStatusCode.Unauthorized;
                }
                if (response.StatusCode == HttpStatusCode.NotFound && !run.Claimed) { run.Unsupported = true; return true; }
                if (await IsReplacedAsync(response, lifetime.Token).ConfigureAwait(false)) { Replace(run); return false; }
                if (!response.IsSuccessStatusCode) return false;
                using var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync(lifetime.Token).ConfigureAwait(false));
                lock (run.StateGate)
                {
                    if (!Current(run) || run.Paused || version != Version(run.Bearer())) return false;
                    var root = json.RootElement;
                    if (root.ValueKind == JsonValueKind.Null)
                    {
                        // A released slot is not another device. Restore may acquire it.
                        run.Claimed = false;
                        return false;
                    }
                    if (root.ValueKind != JsonValueKind.Object || !root.TryGetProperty("epoch", out var epoch) ||
                        !epoch.TryGetInt64(out var value) || value < 1 || value < run.Epoch ||
                        !root.TryGetProperty("deviceId", out var device) || device.ValueKind != JsonValueKind.String) return false;
                    if (device.GetString() != DeviceId) { Replace(run); return false; }
                    run.Epoch = value;
                    run.Claimed = true;
                    run.Unsupported = false;
                    // A network recovery arriving during this request needs its own
                    // verification before writes resume.
                    run.Verified = Volatile.Read(ref run.ImmediateCheck) == 0;
                    return Current(run);
                }
            }
            finally { _gate.Release(); }
        }
        catch (Exception error) when (error is HttpRequestException or OperationCanceledException or JsonException or InvalidOperationException or KeyNotFoundException)
        {
            token.ThrowIfCancellationRequested();
            return false;
        }
    }

    internal void ObserveEvent(string type, JsonElement data)
    {
        var run = Volatile.Read(ref _run);
        if (type != "session.replaced" || run is null || !Current(run) || run.Unsupported || run.Paused || !run.Claimed ||
            data.ValueKind != JsonValueKind.Object || !data.TryGetProperty("deviceId", out var device) || device.ValueKind != JsonValueKind.String ||
            !data.TryGetProperty("epoch", out var epoch) || !epoch.TryGetInt64(out var value) || value <= run.Epoch) return;
        if (device.GetString() != DeviceId) Replace(run);
    }

    private async Task MonitorAsync(Run run)
    {
        try
        {
            // Reconnect and OS network recovery also wake/check immediately.
            // A change in gateway health recalculates the deadline from the last check.
            using var monitor = CancellationTokenSource.CreateLinkedTokenSource(run.Lifetime.Token, run.MonitorStop.Token);
            while (Current(run) && !run.Paused)
            {
                await CheckRunAsync(run, monitor.Token, onlyWhenDue: true).ConfigureAwait(false);
                var delay = Remaining(run);
                if (delay <= TimeSpan.Zero) delay = FallbackInterval; // no authenticated bearer yet
                using var waiting = CancellationTokenSource.CreateLinkedTokenSource(monitor.Token);
                var timer = Task.Delay(delay, _time, waiting.Token);
                var wake = run.Wake.WaitAsync(waiting.Token);
                await Task.WhenAny(timer, wake).ConfigureAwait(false);
                waiting.Cancel();
                try { await Task.WhenAll(timer, wake).ConfigureAwait(false); }
                catch (OperationCanceledException) when (!monitor.IsCancellationRequested) { }
            }
        }
        catch (OperationCanceledException) { }
    }

    internal async Task ReleaseAsync(CancellationToken token = default)
    {
        var run = Volatile.Read(ref _run);
        if (run is null || run.Ended || run.Unsupported || _disposed) { Stop(); return; }
        // End monitoring before release. A delayed monitor must not reclaim the slot.
        var bearer = run.Bearer();
        Stop();
        try
        {
            using var request = new HttpRequestMessage(HttpMethod.Post, new Uri(_origin, "/api/session/v1/release"));
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", bearer);
            request.Content = JsonContent.Create(new { schemaVersion = 1, deviceId = DeviceId });
            using var response = await _http.SendAsync(request, token).ConfigureAwait(false);
        }
        catch (Exception error) when (error is HttpRequestException or OperationCanceledException) { }
    }

    // Fingerprints are in-memory version stamps, never persisted or logged.
    private static string? Version(string? bearer) => string.IsNullOrWhiteSpace(bearer) ? null :
        Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(System.Text.Encoding.UTF8.GetBytes(bearer)));

    internal HttpMessageHandler CreateHandler(HttpMessageHandler? inner = null, bool decompress = false) => new DeviceHandler(this,
        inner ?? new HttpClientHandler { AllowAutoRedirect = false, UseCookies = false,
            AutomaticDecompression = decompress ? DecompressionMethods.GZip | DecompressionMethods.Deflate | DecompressionMethods.Brotli : DecompressionMethods.None });
    private sealed class DeviceHandler(RelayDeviceSession owner, HttpMessageHandler inner) : DelegatingHandler(inner)
    {
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            if (request.RequestUri is not { } uri || uri.Scheme != owner._origin.Scheme || uri.Host != owner._origin.Host ||
                uri.Port != owner._origin.Port || !uri.AbsolutePath.StartsWith("/api/", StringComparison.Ordinal))
                return await base.SendAsync(request, token).ConfigureAwait(false);
            var write = request.Method != HttpMethod.Get && request.Method != HttpMethod.Head && request.Method != HttpMethod.Options;
            var run = Volatile.Read(ref owner._run);
            if (write && run is not null)
            {
                // Never affect login/public requests or a request from a retired generation.
                var bearer = request.Headers.Authorization?.Parameter;
                if (string.IsNullOrWhiteSpace(bearer)) return await base.SendAsync(request, token).ConfigureAwait(false);
                if (bearer != run.Bearer()) throw new HttpRequestException("Retired relay credential.");
                var version = Version(bearer);
                // A refresh changes the authority's evidence. Re-adjudicate once for
                // that version before allowing its first body, not before every write.
                if (owner.Current(run) && !run.Unsupported && run.CredentialVersion != version)
                    await owner.CheckRunAsync(run, token, onlyWhenDue: true).ConfigureAwait(false);
                lock (run.StateGate)
                {
                    if (bearer != run.Bearer()) throw new HttpRequestException("Retired relay credential.");
                    if (!owner.Current(run) || !(run.Unsupported || run.Claimed && run.Verified && run.CredentialVersion == version))
                    {
                        if (run.Unauthorized && run.CredentialVersion == version) throw new Auth.ScmApiAuthenticationException("Relay authentication required.");
                        throw new HttpRequestException("Relay session unavailable.");
                    }
                    if (!owner.Current(run)) throw new HttpRequestException("Relay session ended.");
                    request.Headers.Remove("X-StarBridge-Device");
                    if (!run.Unsupported) request.Headers.TryAddWithoutValidation("X-StarBridge-Device", owner.DeviceId);
                }
            }
            else if (write && request.Headers.Authorization is not null)
                throw new HttpRequestException("Relay session ended.");
            var response = await base.SendAsync(request, token).ConfigureAwait(false);
            if (write && run is not null && !run.Unsupported && await IsReplacedAsync(response, token).ConfigureAwait(false)) owner.Replace(run);
            return response;
        }
    }
    internal static async Task<bool> IsReplacedAsync(HttpResponseMessage response, CancellationToken token)
    {
        if (response.StatusCode != HttpStatusCode.Conflict) return false;
        try
        {
            // Buffering preserves the response body for its original domain consumer.
            var bytes = await response.Content.ReadAsByteArrayAsync(token).ConfigureAwait(false);
            using var json = JsonDocument.Parse(bytes);
            return json.RootElement.ValueKind == JsonValueKind.Object && json.RootElement.TryGetProperty("code", out var code) &&
                code.ValueKind == JsonValueKind.String && code.GetString() == "session.replaced";
        }
        catch (JsonException) { return false; }
    }
    public void Dispose()
    {
        _disposed = true;
        NetworkChange.NetworkAvailabilityChanged -= NetworkAvailabilityChanged;
        Stop();
        _http.Dispose();
    }
}
