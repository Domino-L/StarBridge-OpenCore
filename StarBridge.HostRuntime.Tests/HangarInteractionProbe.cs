using System.Diagnostics;
using System.Text;
using System.Text.Json;
using StarBridge.Core.Hangar;
using StarBridge.Core.Identity;

// Test-only coordinator. No product IPC, credentials, HTTP client or save port.
// Synthetic about:blank is accepted ONLY here; the production origin guard remains unchanged.
internal sealed class HangarInteractionProbe
{
    private readonly Process _process;
    private readonly bool _interactive, _missingRuntime;
    private readonly Stopwatch _clock = Stopwatch.StartNew();
    private readonly ScmGameIdentitySnapshot _identity = new(ScmGameIdentityStatus.Verified, "Pilot_Alpha", "pilot_alpha");
    private readonly JsonSerializerOptions _json = new() { PropertyNameCaseInsensitive = true };
    private HangarScanSession? _scan;
    private Uri? _currentUri;
    private int _op, _generation, _page, _scenario, _capture, _pendingCapture, _case, _passed;
    private bool _active, _ready, _closed, _cancelSent, _runtimeRecovered;
    private long _pageStarted, _nextRead, _lastPing;

    private HangarInteractionProbe(Process process, bool interactive, bool missingRuntime)
    { _process = process; _interactive = interactive; _missingRuntime = missingRuntime; }

    public static async Task<int> RunAsync(string executable, bool interactive)
    {
        var passed = await RunProcess(executable, interactive, false);
        if (!interactive) passed += await RunProcess(executable, false, true);
        Console.WriteLine(interactive ? "Interactive hangar probe closed; no data saved." : $"PASS Dynamic WebView2 interaction: {passed} scenarios; no production account or saved hangar accessed");
        return 0;
    }

    private static async Task<int> RunProcess(string executable, bool interactive, bool missingRuntime)
    {
        var start = new ProcessStartInfo(executable) { UseShellExecute = false, CreateNoWindow = true,
            RedirectStandardInput = true, RedirectStandardOutput = true, RedirectStandardError = true,
            StandardInputEncoding = new UTF8Encoding(false), StandardOutputEncoding = Encoding.UTF8 };
        if (interactive) start.ArgumentList.Add("--visible");
        if (missingRuntime) start.ArgumentList.Add("--missing-runtime");
        using var process = Process.Start(start) ?? throw new InvalidOperationException("Native interaction probe did not start");
        using var deadline = new CancellationTokenSource(interactive ? TimeSpan.FromMinutes(15) : TimeSpan.FromMinutes(3));
        var errors = process.StandardError.ReadToEndAsync(deadline.Token);
        var coordinator = new HangarInteractionProbe(process, interactive, missingRuntime);
        try
        {
            var lineTask = process.StandardOutput.ReadLineAsync(deadline.Token).AsTask();
            var tickTask = Task.Delay(100, deadline.Token);
            while (!coordinator._closed)
            {
                await Task.WhenAny(lineTask, tickTask);
                deadline.Token.ThrowIfCancellationRequested();
                if (lineTask.IsCompleted)
                {
                    var line = await lineTask;
                    if (line is null) throw new InvalidOperationException("Native probe ended without close acknowledgement");
                    if (line.Length > 300 * 1024) throw new InvalidOperationException("Native probe output limit exceeded");
                    using var message = JsonDocument.Parse(line);
                    await coordinator.Event(message.RootElement);
                    if (!coordinator._closed) lineTask = process.StandardOutput.ReadLineAsync(deadline.Token).AsTask();
                }
                if (tickTask.IsCompleted)
                {
                    await coordinator.Tick();
                    tickTask = Task.Delay(100, deadline.Token);
                }
            }
            await process.WaitForExitAsync(deadline.Token);
            if (process.ExitCode != 0) throw new InvalidOperationException($"Native interaction exit {process.ExitCode}");
            if ((await errors).Length != 0) throw new InvalidOperationException("Unexpected native diagnostic output");
            if (!interactive && coordinator._passed != (missingRuntime ? 2 : 12))
                throw new InvalidOperationException("Incomplete dynamic interaction matrix");
            return coordinator._passed;
        }
        finally
        {
            coordinator._scan?.Cancel();
            if (!process.HasExited)
            {
                try { await process.StandardInput.WriteLineAsync("CLOSE"); await process.StandardInput.FlushAsync(); }
                catch (IOException) { }
                using var closeDeadline = new CancellationTokenSource(TimeSpan.FromSeconds(5));
                try { await process.WaitForExitAsync(closeDeadline.Token); }
                catch (OperationCanceledException) { if (!process.HasExited) process.Kill(entireProcessTree: true); }
            }
        }
    }

    private async Task Send(string command)
    { await _process.StandardInput.WriteLineAsync(command); await _process.StandardInput.FlushAsync(); }

    private async Task Event(JsonElement message)
    {
        var type = message.GetProperty("type").GetString();
        switch (type)
        {
            case "boot":
                Console.WriteLine("READY Local synthetic reader window");
                await Send("RESIZE 1000 760");
                if (!_interactive) await Send("TEST_START 0");
                break;
            case "layout":
                if (message.GetProperty("width").GetInt32() < 600 || message.GetProperty("height").GetInt32() < 350 || message.GetProperty("dpi").GetInt32() <= 0)
                    throw new InvalidOperationException("Invalid browser window bounds");
                break;
            case "start":
                var op = message.GetProperty("op").GetInt32();
                if (op <= _op) throw new InvalidOperationException("Replayed start event");
                _scan?.Cancel(); _scan = new HangarScanSession(); _op = op; _generation = 0; _capture = 0;
                _scenario = message.GetProperty("scenario").GetInt32(); _currentUri = null; _active = true; _cancelSent = false;
                if (!_interactive && !_missingRuntime && _case == 9) await Send("TEST_CANCEL");
                await Navigate(1);
                break;
            case "ready":
                if (!Current(message)) break;
                _ready = true; _nextRead = _clock.ElapsedMilliseconds + 200;
                if (!_interactive && !_missingRuntime && _case is 7 or 11 && _page == 2 && !_cancelSent)
                {
                    _cancelSent = true;
                    // Queue a read first to exercise cancellation with an in-flight callback.
                    await Send($"READ {_op} {_generation} {++_capture}");
                    await Send(_case == 7 ? "TEST_CANCEL" : "CLOSE");
                }
                break;
            case "observation":
                if (!Current(message) || message.GetProperty("capture").GetInt32() != _pendingCapture) break;
                _pendingCapture = 0;
                await Observe(message.GetProperty("body"));
                break;
            case "cancel":
                if (message.GetProperty("op").GetInt32() == _op) { _scan?.Cancel(); _active = false; _pendingCapture = 0; }
                break;
            case "error":
                if (message.GetProperty("code").GetString() == "runtime") break; // Window offers retry; automated branch below tests recovery.
                if (_active && message.GetProperty("op").GetInt32() == _op) await Stop(4);
                if (!_interactive) throw new InvalidOperationException("Native browser failed during synthetic matrix");
                break;
            case "state": await State(message); break;
            case "closed":
                _scan?.Cancel(); _active = false; _closed = true;
                if (!_interactive && !_missingRuntime && _case == 11)
                {
                    if (_scan?.Snapshot.State != HangarScanState.Cancelled) throw new InvalidOperationException("Closing did not cancel scan");
                    _passed++; Console.WriteLine("PASS Dynamic close during page load");
                }
                break;
            default: throw new InvalidOperationException("Unexpected native interaction message");
        }
    }

    private bool Current(JsonElement message) => _active && message.GetProperty("op").GetInt32() == _op && message.GetProperty("generation").GetInt32() == _generation;

    private async Task Navigate(int page)
    {
        var target = new Uri($"https://robertsspaceindustries.com/en/account/pledges?page={page}");
        var action = _generation == 0 ? HangarNavigationAction.Start :
            _scan!.Snapshot.State == HangarScanState.VerifyingFirstPage ? HangarNavigationAction.RecheckFirstPage : HangarNavigationAction.NextPage;
        if (!RsiHangarNavigationPolicy.Allows(action, _currentUri, target)) { await Stop(4); return; }
        _currentUri = target; _page = page; _generation++; _ready = false; _pendingCapture = 0; _pageStarted = _clock.ElapsedMilliseconds;
        // Only numeric fixture coordinates cross this test pipe, never the URL.
        await Send($"NAV {_op} {_generation} {_page} {_scenario}");
    }

    private async Task Observe(JsonElement body)
    {
        if (body.ValueKind != JsonValueKind.Object || body.EnumerateObject().Count() != 2) { await Stop(4); return; }
        var handles = body.GetProperty("identity").EnumerateArray().Select(h => h.ValueKind == JsonValueKind.String ? h.GetString() : null).ToArray();
        if (!RsiHangarIdentityPolicy.Evaluate(_identity, handles).CanContinue) { await Stop(7); return; }
        var page = body.GetProperty("page");
        if (page.EnumerateObject().Count() != 9 || page.GetProperty("schemaVersion").GetInt32() != 1 || page.GetProperty("documentUrl").GetString() != "about:blank") { await Stop(4); return; }
        var status = page.GetProperty("status").GetString();
        if (status == "unconfirmedEmpty") { _nextRead = _clock.ElapsedMilliseconds + 200; return; }
        if (status != "ready") { await Stop(4); return; }
        var observation = JsonSerializer.Deserialize<HangarPageObservation>(page.GetRawText(), _json)!;
        if (observation.Page != _page) { await Stop(4); return; }
        var snapshot = _scan!.Observe((ulong)_capture, observation);
        switch (snapshot.State)
        {
            case HangarScanState.Complete: await Stop(3); break;
            case HangarScanState.NeedsReview: await Stop(6); break;
            case HangarScanState.Invalid: await Stop(4); break;
            case HangarScanState.TimedOut: await Stop(10); break;
            default:
                await Send($"STATE {_op} {(snapshot.State == HangarScanState.VerifyingFirstPage ? 2 : 1)} {snapshot.Ships.Count}");
                if (snapshot.ExpectedPage != _page) await Navigate(snapshot.ExpectedPage);
                else _nextRead = _clock.ElapsedMilliseconds + 200;
                break;
        }
    }

    private async Task Stop(int phase)
    {
        if (!_active) return;
        _active = false; _ready = false; _pendingCapture = 0;
        if (phase is not (3 or 6)) _scan?.Cancel();
        await Send($"STATE {_op} {phase} {_scan?.Snapshot.Ships.Count ?? 0}");
    }

    private async Task Tick()
    {
        if (_closed) return;
        var now = _clock.ElapsedMilliseconds;
        if (now - _lastPing >= 1000) { _lastPing = now; await Send("PING"); }
        if (!_active) return;
        if (now - _pageStarted >= 6000) { await Stop(10); return; }
        if (_ready && _pendingCapture == 0 && now >= _nextRead)
        { _pendingCapture = ++_capture; await Send($"READ {_op} {_generation} {_capture}"); }
    }

    private async Task State(JsonElement message)
    {
        var phase = message.GetProperty("phase").GetInt32();
        if (phase is 0 or 1 or 2 or 9) return;
        Console.WriteLine($"STATE operation={message.GetProperty("op").GetInt32()} phase={phase} ships={message.GetProperty("ships").GetInt32()}");
        if (_interactive) return;
        if (_missingRuntime)
        {
            if (!_runtimeRecovered)
            {
                if (phase != 8) throw new InvalidOperationException("Missing-runtime path not shown");
                _runtimeRecovered = true; _passed++; await Send("TEST_START 0"); return;
            }
            if (phase != 3 || message.GetProperty("ships").GetInt32() != 3) throw new InvalidOperationException("Runtime retry did not recover");
            _passed++; await Send("CLOSE"); return;
        }
        var expected = new[] { 3, 3, 3, 4, 7, 4, 10, 5, 3, 5, 3 };
        if (_case >= expected.Length || phase != expected[_case]) throw new InvalidOperationException($"Dynamic case {_case} expected a different terminal state (actual {phase})");
        if (phase == 3 && (_scan?.Snapshot.Ships.Count != 3 || !_scan.Snapshot.IsComplete)) throw new InvalidOperationException("Incomplete scan shown as completed");
        if (phase == 5) {
            // Queued commands from a cancelled operation must not revive its UI/browser.
            await Send($"NAV {_op} {_generation + 1} 1 0");
            await Send($"STATE {_op} 3 999");
        }
        _passed++; Console.WriteLine($"PASS Dynamic case {_case}"); _case++;
        await Send(_case <= 6 ? $"TEST_START {_case}" : _case is 7 or 11 ? "TEST_START 1" : "TEST_START 0");
    }
}
