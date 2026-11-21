using System.Security.AccessControl;
using System.Security.Principal;
using System.Text.Json;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.Onboarding;
using StarBridge.HostRuntime.Presence;
using StarBridge.NativeBridge;

internal static class FirstUseLogSearchTests
{
    private static string Id() => Guid.NewGuid().ToString("N");
    private static void Check(bool value, string message) { if (!value) throw new InvalidOperationException(message); }
    private static string Log(string root, string version)
    {
        var path = Path.Combine(root, version, "Game.log");
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, ""); // Synthetic empty log; no personal game data.
        return path;
    }
    internal static async Task Run()
    {
        using var data = new LocalDeviceSetupReaderTests.Fixture();
        var root = Path.Combine(data.Root, "search"); Directory.CreateDirectory(root);
        var search = new LocalGameLogSearch(new(() => [root]), () => new("notRunning"));
        IReadOnlyList<LocalGameLogCandidate> Find() => search.Find([], () => { }, default).Candidates;
        Check(Find().Count == 0 && search.Find([], () => { }, default).Complete, "No file means no candidate, from a finished search");
        Console.WriteLine("PASS log search: no result");
        var live = Log(root, "LIVE");
        Check(Find() is [{ Version: "LIVE" }] && Find()[0].Path.Equals(Path.GetFullPath(live), StringComparison.OrdinalIgnoreCase), "One safe result");
        Console.WriteLine("PASS log search: one result");
        Log(root, "PTU"); Log(root, "EPTU"); Log(root, "HOTFIX"); Log(root, "bad version");
        Log(Path.Combine(root, "nested"), "LIVE");
        Check(Find().Select(c => c.Version).Order().SequenceEqual(new[] { "EPTU", "HOTFIX", "LIVE", "PTU" }),
            "Only legal immediate folders; never recurse");
        Console.WriteLine("PASS log search: multiple versions, invalid names and no recursion");
        var previous = Log(Path.Combine(data.Root, "previous"), "PTU");
        var running = Log(Path.Combine(data.Root, "running"), "LIVE");
        var prioritized = new LocalGameLogSearch(new(() => [root]), () => new("running", LogPath: running));
        var order = prioritized.Find([previous], () => { }, default).Candidates;
        Check(order[0].Path == Path.GetFullPath(running) && order[1].Path == Path.GetFullPath(previous), "Running then previous then common installs");
        Console.WriteLine("PASS log search: existing source priority and deduplication");
        // An earlier Game.log outside an install folder (e.g. Downloads) is offered
        // itself, but its sibling folders are not listed as game versions.
        var home = Path.Combine(data.Root, "home");
        var downloads = Log(home, "Downloads"); Log(home, "Desktop");
        var loose = prioritized.Find([downloads], () => { }, default).Candidates;
        Check(loose.Any(c => c.Path == Path.GetFullPath(downloads)) &&
            !loose.Any(c => c.Path.Contains(Path.Combine(home, "Desktop"), StringComparison.OrdinalIgnoreCase)),
            "Earlier loose log does not widen discovery to its siblings");
        Console.WriteLine("PASS log search: earlier loose log stays a single candidate");
        var linked = Path.Combine(root, "LINKED"); var target = Path.Combine(data.Root, "target"); Log(target, "LIVE");
        var start = new System.Diagnostics.ProcessStartInfo("cmd.exe") { UseShellExecute = false, CreateNoWindow = true };
        start.ArgumentList.Add("/c"); start.ArgumentList.Add("mklink"); start.ArgumentList.Add("/J");
        start.ArgumentList.Add(linked); start.ArgumentList.Add(Path.Combine(target, "LIVE"));
        using (var child = System.Diagnostics.Process.Start(start)!) { child.WaitForExit(); Check(child.ExitCode == 0, "Junction fixture setup"); }
        try { Check(Find().All(c => c.Version != "LINKED"), "Linked directories must be absent"); }
        finally { Directory.Delete(linked); }
        var hard = Path.Combine(root, "HARD", "Game.log"); Directory.CreateDirectory(Path.GetDirectoryName(hard)!);
        start.ArgumentList.Clear();
        foreach (var argument in new[] { "/c", "mklink", "/H", hard, live }) start.ArgumentList.Add(argument);
        using (var child = System.Diagnostics.Process.Start(start)!) { child.WaitForExit(); Check(child.ExitCode == 0, "Hard link fixture setup"); }
        try { Check(Find().All(c => c.Version is not ("HARD" or "LIVE")), "Hard-linked files cannot surface as candidates"); }
        finally { File.Delete(hard); }
        Check(search.Find([live + ":stream", @"\\invalid.example\LIVE\Game.log", Path.Combine(root, "LIVE", "..", "LIVE", "Game.log")], () => { }, default)
            .Candidates.All(c => !c.Path.Contains(":stream") && !c.Path.Contains("..")), "Illegal paths never surface");
        Console.WriteLine("PASS log search: checked directories and illegal paths excluded");
        for (var i = 0; i < 16; i++) Log(root, "BUILD_" + i);
        Check(Find().Count == 8, "Eight candidate cap");
        Console.WriteLine("PASS log search: eight candidate cap");
        var clock = new Clock();
        var timed = new LocalGameLogSearch(new(() => { clock.Tick = 3000; return [root]; }), () => new("running", LogPath: live), clock);
        Check(timed.Find([], () => { }, default) is { Complete: false, Candidates: [{ Path: var partial }] } && partial == Path.GetFullPath(live),
            "Deadline returns checked partial results, marked unfinished");
        Console.WriteLine("PASS log search: deadline returns partial results");
        using var cancelled = new CancellationTokenSource(); cancelled.Cancel();
        try { search.Find([], () => { }, cancelled.Token); throw new Exception("Cancellation ignored"); } catch (OperationCanceledException) { }
        Console.WriteLine("PASS log search: caller cancellation");
        await Protocol(data, root);
    }
    private static async Task Protocol(LocalDeviceSetupReaderTests.Fixture data, string root)
    {
        using var noNetwork = new NoNetwork();
        var origin = new Uri("https://synthetic.example.invalid/");
        var oauth = new OAuthPkceClient(new ScmHttpClient(noNetwork), new EmptyVault(),
            new("fixture", origin, origin, origin, "synthetic", "synthetic", "profile.read", "/callback"));
        using var host = new ScmAccountBridgeHost(oauth, new ScmProfileCacheStore(Path.Combine(data.Device, "cache")), "fixture", () => null);
        await host.GetCurrentAsync(default);
        using var runtime = new AccountBridgeRuntime(host, gameLog: new GameLogSettingsStore(data.Device));
        await AccountBridgeRuntime.CreateWithFirstUseModeAsync(data.Device, _ => Task.FromResult(runtime), localGameProbe: () => new("notRunning"));
        runtime.ConfigureFirstUseDeviceSetup(data.Application, data.Overlay, data.Notifications, data.Reminder);
        await using var native = new NativeAccountRuntimeBinding(runtime);
        var mode = runtime.FirstUseMode!; var held = false; var slow = false;
        using var entered = new ManualResetEventSlim(); using var release = new ManualResetEventSlim();
        var searchRoot = root; var clock = new Clock();
        // `slow`: the roots call returns at the third second, past the scan's own
        // 2-second budget but well inside the 5-second hard stop.
        var search = new LocalGameLogSearch(new(() =>
        {
            if (held) { entered.Set(); Check(release.Wait(FirstUseTestWait.Bound), "Search released"); }
            if (slow) clock.Tick += 3000;
            return [searchRoot];
        }), () => new("notRunning"), clock) { HardStop = Timeout.InfiniteTimeSpan };
        using var guide = new FirstUseBridgeDispatcher(data.Device, runtime, native,
            new(data.Device, () => new("fresh", "0.7.3")), new NoPicker(), _ => throw new Exception("No online business"), () => "en", search);
        async Task<JsonElement> Read()
        {
            var batch = await guide.DispatchAsync(BridgeEnvelope.Request("onboarding.read", Id(), mode.ControlGeneration, new { schemaVersion = 1 }));
            Check(batch.Response.Status == "ok", "Read current observation"); return batch.Response.Payload;
        }
        BridgeEnvelope Request(JsonElement read, string action, string step = "log", int? index = null, long? generation = null)
        {
            var facts = read.GetProperty("facts");
            var body = new Dictionary<string, object?> {
                ["schemaVersion"] = 1, ["expectedStateKey"] = read.GetProperty("stateKey").GetString(), ["action"] = action,
                ["checkpoint"] = new Dictionary<string, object?> { ["step"] = step, ["mode"] = "local", ["sourceKey"] = facts.GetProperty("sourceKey").GetString(), ["evidenceKey"] = facts.GetProperty("evidenceKey").GetString() } };
            if (index is not null) body["candidateIndex"] = index;
            return BridgeEnvelope.Request("onboarding.execute", Id(), generation ?? mode.ControlGeneration, body);
        }
        var read = await Read();
        Check((await guide.DispatchAsync(Request(read, "locateLogs"))).Response.Status == "error", "Discovery requires actual local mode");
        // The real bootstrap: the guide's log step asks Host to prepare a device
        // that has no mode and no account. Nothing is sent by hand here.
        Check(mode.Current is { State: "online", ActiveMode: "online" }, "Unchosen mode is projected as online");
        var prepared = (await guide.DispatchAsync(Request(read, "prepareLog"))).Response;
        Check(prepared.Status == "ok" && mode.LocalMode().Active &&
            prepared.Payload.GetProperty("facts").GetProperty("activeMode").GetString() == "local" &&
            prepared.Payload.GetProperty("facts").GetProperty("publicationSuspended").GetBoolean(),
            "prepareLog sets up local mode on a device without an account: " + prepared.Error?.Code);
        Check((await guide.DispatchAsync(Request(prepared.Payload, "prepareLog", "mode"))).Response.Status == "error", "prepareLog only at the log step");
        var again = (await guide.DispatchAsync(Request(prepared.Payload, "prepareLog"))).Response;
        Check(again.Status == "ok" && mode.LocalMode().Active, "prepareLog on local mode changes nothing");
        Console.WriteLine("PASS log search protocol: new device prepared through the real log-step action");
        data.Generation = mode.ControlGeneration;
        var before = data.Store.Read(); read = await Read();
        Check((await guide.DispatchAsync(Request(read, "locateLogs", "mode"))).Response.Status == "error", "Wrong step denied");
        Check((await guide.DispatchAsync(Request(read, "locateLogs", generation: mode.ControlGeneration + 1))).Response.Status == "error", "Wrong generation denied");
        Console.WriteLine("PASS log search protocol: mode, step and generation guards");
        searchRoot = Path.Combine(data.Root, "protocol-empty"); Directory.CreateDirectory(searchRoot);
        var located = (await guide.DispatchAsync(Request(read, "locateLogs"))).Response;
        Check(located.Status == "ok" && located.Payload.GetProperty("facts").GetProperty("logCandidates").GetArrayLength() == 0, "Action with no candidate");
        Log(searchRoot, "LIVE");
        located = (await guide.DispatchAsync(Request(located.Payload, "locateLogs"))).Response;
        Check(located.Status == "ok" && located.Payload.GetProperty("facts").GetProperty("logCandidates").GetArrayLength() == 1, "Action with one candidate");
        Log(searchRoot, "EPTU");
        located = (await guide.DispatchAsync(Request(located.Payload, "locateLogs"))).Response;
        Check(located.Status == "ok" && located.Payload.GetProperty("facts").GetProperty("logCandidates").GetArrayLength() == 2, "Action with multiple candidates");
        Console.WriteLine("PASS log search protocol: zero, one and multiple candidates");
        // The scan's own budget runs out before the hard stop. With nothing checked
        // yet, the page must say the search did not finish, not "no log found".
        slow = true;
        var budget = (await guide.DispatchAsync(Request(located.Payload, "locateLogs"))).Response;
        slow = false;
        Check(budget.Status == "ok" && budget.Payload.GetProperty("facts").GetProperty("logSearchBlocked").GetBoolean() &&
            budget.Payload.GetProperty("facts").GetProperty("logCandidates").GetArrayLength() == 0,
            "A scan ended by its own budget is reported as unfinished: " + budget.Status);
        var finished = (await guide.DispatchAsync(Request(budget.Payload, "locateLogs"))).Response;
        Check(finished.Status == "ok" && !finished.Payload.GetProperty("facts").GetProperty("logSearchBlocked").GetBoolean() &&
            finished.Payload.GetProperty("facts").GetProperty("logCandidates").GetArrayLength() == 2,
            "The next finished scan clears the hint and lists everything");
        located = finished;
        Console.WriteLine("PASS log search protocol: budget-ended scan with no candidate is unfinished, not empty");
        searchRoot = root;
        var reads = mode.ModeStoreReads;
        located = (await guide.DispatchAsync(Request(located.Payload, "locateLogs"))).Response;
        // Two full checks before and after, plus the dispatcher's own capture and
        // projection. The scan itself, over 8+ folders and their parents, reads none.
        Check(mode.ModeStoreReads - reads <= 40, "Scan keeps mode checks in memory: " + (mode.ModeStoreReads - reads));
        Console.WriteLine("PASS log search protocol: mode store reads for one scan = " + (mode.ModeStoreReads - reads));
        Check(located.Status == "ok" && located.Payload.GetProperty("facts").GetProperty("logCandidates").GetArrayLength() == 8, "Search response candidates: " + located.Payload.GetProperty("facts").GetProperty("logCandidates").GetArrayLength());
        Check(!located.Payload.GetProperty("facts").GetProperty("logSearchBlocked").GetBoolean(), "A finished search is not reported as blocked");
        Check(JsonSerializer.Serialize(data.Store.Read()) == JsonSerializer.Serialize(before) && noNetwork.Calls == 0, "Discovery cannot select, persist or contact services");
        Console.WriteLine("PASS log search protocol: no automatic selection, writes or network");
        Check((await guide.DispatchAsync(Request(read, "selectLog", index: 0))).Response.Status == "error", "Old candidate state denied");
        var chosen = located.Payload.GetProperty("facts").GetProperty("logCandidates")[0].GetProperty("path").GetString()!;
        var selected = (await guide.DispatchAsync(Request(located.Payload, "selectLog", index: 0))).Response;
        Check(selected.Status == "ok" && data.Store.Read().Sources.Any(s => s.SourceKey == data.Store.Read().SelectedSourceKey && s.LogPath == chosen),
            "Candidate selection uses real selectLog and evidence owner: " + selected.Error?.Code);
        Console.WriteLine("PASS log search protocol: explicit candidate uses selectLog");
        read = await Read(); located = (await guide.DispatchAsync(Request(read, "locateLogs"))).Response;
        var candidate = located.Payload.GetProperty("facts").GetProperty("logCandidates")[1].GetProperty("path").GetString()!;
        File.Delete(candidate); Directory.CreateDirectory(candidate);
        try { Check((await guide.DispatchAsync(Request(located.Payload, "selectLog", index: 1))).Response.Status == "error", "Candidate file revalidated on click"); }
        finally { Directory.Delete(candidate); File.WriteAllText(candidate, ""); }
        Console.WriteLine("PASS log search protocol: candidate is revalidated at selection");
        // Budget-ended after the selected log was checked: that candidate stays,
        // and the page still says the search did not finish.
        {
            var selectedPath = data.Store.Read().Sources.Single(s => s.SourceKey == data.Store.Read().SelectedSourceKey).LogPath;
            read = await Read(); slow = true;
            var partial = (await guide.DispatchAsync(Request(read, "locateLogs"))).Response;
            slow = false;
            Check(partial.Status == "ok" && partial.Payload.GetProperty("facts").GetProperty("logSearchBlocked").GetBoolean() &&
                partial.Payload.GetProperty("facts").GetProperty("logCandidates").EnumerateArray().Select(c => c.GetProperty("path").GetString()).SequenceEqual([selectedPath]),
                "A budget-ended scan keeps its checked candidates and is reported as unfinished");
            Console.WriteLine("PASS log search protocol: budget-ended scan keeps checked candidates and says unfinished");
        }
        // A disk call that blocks past the hard stop ends the wait with only
        // fully checked candidates; the read-only scan is left to finish unseen.
        search.HardStop = TimeSpan.FromMilliseconds(300);
        read = await Read(); held = true;
        var watch = System.Diagnostics.Stopwatch.StartNew();
        var stopped = (await guide.DispatchAsync(Request(read, "locateLogs"))).Response;
        watch.Stop();
        // Only the already selected log can be checked before the blocked roots call.
        Check(stopped.Status == "ok" && stopped.Payload.GetProperty("facts").GetProperty("logCandidates").EnumerateArray()
                .All(c => c.GetProperty("path").GetString() == data.Store.Read().Sources.Single(s => s.SourceKey == data.Store.Read().SelectedSourceKey).LogPath) &&
            watch.Elapsed < TimeSpan.FromSeconds(2), "Blocked search ends at the hard stop, whole request included: " + stopped.Status + " " + watch.Elapsed);
        Check(stopped.Payload.GetProperty("facts").GetProperty("logSearchBlocked").GetBoolean(), "An unfinished search is reported as blocked, not as nothing found");
        // The first scan is still blocked: a second request starts no new worker
        // and keeps what the page already showed instead of an empty list.
        entered.Reset(); watch.Restart();
        var reentered = (await guide.DispatchAsync(Request(stopped.Payload, "locateLogs"))).Response;
        watch.Stop();
        Check(reentered.Status == "ok" && !entered.IsSet && watch.Elapsed < TimeSpan.FromSeconds(2),
            "A blocked scan is not started twice: " + reentered.Status + " " + watch.Elapsed);
        Check(reentered.Payload.GetProperty("facts").GetProperty("logSearchBlocked").GetBoolean() &&
            reentered.Payload.GetProperty("facts").GetProperty("logCandidates").GetRawText() ==
            stopped.Payload.GetProperty("facts").GetProperty("logCandidates").GetRawText(), "A refused retry keeps earlier candidates and says it is blocked");
        held = false; release.Set();
        Console.WriteLine("PASS log search protocol: blocked disk call ends at the hard stop and is not re-entered");
        await Task.Delay(500);
        // Once the old scan has ended, the next search runs again and clears the hint.
        searchRoot = root; read = await Read();
        var resumed = (await guide.DispatchAsync(Request(read, "locateLogs"))).Response;
        Check(resumed.Status == "ok" && !resumed.Payload.GetProperty("facts").GetProperty("logSearchBlocked").GetBoolean() &&
            resumed.Payload.GetProperty("facts").GetProperty("logCandidates").GetArrayLength() > 0, "After the blocked scan ends, searching works again");
        Console.WriteLine("PASS log search protocol: search recovers after the blocked scan ends");
        // The start marker cannot be written: the guide saves nothing and reports
        // the data folder, then records the marker first once it can.
        {
            var folder = Path.Combine(data.Device, FirstUseStartupReader.MarkerDirectory);
            var marker = new[] { FirstUseStartupReader.StartedMarker, FirstUseStartupReader.ReturningMarker }
                .Select(name => Path.Combine(folder, name)).Single(File.Exists);
            File.Delete(marker);
            var info = new DirectoryInfo(folder);
            var denied = new DirectorySecurity();
            denied.SetSecurityDescriptorBinaryForm(info.GetAccessControl().GetSecurityDescriptorBinaryForm(), AccessControlSections.Access);
            using var identity = WindowsIdentity.GetCurrent();
            var rule = new FileSystemAccessRule(identity.User!, FileSystemRights.CreateFiles, AccessControlType.Deny);
            denied.AddAccessRule(rule);
            info.SetAccessControl(denied);
            var stored = JsonSerializer.Serialize(data.Store.Read());
            try
            {
                read = await Read();
                var refused = (await guide.DispatchAsync(Request(read, "locateLogs"))).Response;
                Check(refused.Status == "error" && refused.Error?.Code == "firstUse.storage_unavailable" && !File.Exists(marker) &&
                    JsonSerializer.Serialize(data.Store.Read()) == stored, "An unwritable marker is reported as storage: " + refused.Error?.Code);
            }
            finally
            {
                denied.RemoveAccessRuleSpecific(rule);
                info.SetAccessControl(denied);
            }
            read = await Read();
            Check((await guide.DispatchAsync(Request(read, "locateLogs"))).Response.Status == "ok" && File.Exists(marker),
                "Once writable, the next request records the marker first");
            Console.WriteLine("PASS log search protocol: unwritable marker reports the data folder and saves nothing");
        }
        entered.Reset(); release.Reset(); search.HardStop = Timeout.InfiniteTimeSpan;
        read = await Read(); held = true;
        var pending = guide.DispatchAsync(Request(read, "locateLogs")).AsTask();
        Check(entered.Wait(FirstUseTestWait.Bound), "Search entered worker");
        var retirement = guide.RetireAsync(); release.Set(); var late = await pending; await retirement;
        Check(late.Response.Status != "ok", "Retired request cannot publish late candidates");
        Console.WriteLine("PASS log search protocol: retirement drains and rejects late results");
    }
    private sealed class Clock : TimeProvider { internal long Tick; public override long TimestampFrequency => 1000; public override long GetTimestamp() => Tick; }
    private sealed class NoPicker : IFirstUseLogPicker { public Task<string?> PickAsync(string locale, CancellationToken token) => throw new Exception("Candidate selection must not open picker"); }
    private sealed class EmptyVault : ITokenVault
    {
        public string? LoadActiveAccountKey() => null;
        public string? LoadRefreshToken(string key) => null;
        public void SaveRefreshToken(string key, string token) => throw new Exception("No credential writes");
        public void DeleteRefreshToken(string key) => throw new Exception("No credential deletes");
    }
    private sealed class NoNetwork : HttpMessageHandler
    {
        internal int Calls;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        { Calls++; throw new Exception("No network in discovery"); }
    }
}