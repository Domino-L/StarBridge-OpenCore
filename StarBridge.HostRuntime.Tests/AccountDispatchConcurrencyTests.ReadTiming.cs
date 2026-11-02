using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;

internal static partial class AccountDispatchConcurrencyTests
{
    internal static async Task ReadTiming()
    {
        var original = HostDataRoot.CurrentRoot;
        var root = Directory.CreateTempSubdirectory("sb-account-wait-").FullName;
        HostDataRoot.UsePreparedRoot(root);
        try
        {
            var (host, probe) = Create();
            probe.ConcurrentReads = false; // SCM's existing exclusive contract.
            using var dispatcher = new AccountBridgeDispatcher(host);
            var holder = dispatcher.DispatchAsync(Request(AccountBridgeRequestNames.ReadCommunities));
            await Until(() => probe.Reads == 1);
            var queued = dispatcher.DispatchAsync(Request(AccountBridgeRequestNames.GetCurrent));
            try
            {
                Check(!queued.IsCompleted && probe.Currents == 0, "Actual root read is queued behind the held exclusive request.");
#if STARBRIDGE_SESSION_PROBE
                var heldLog = Journal(root);
                Check(heldLog.Contains("operation=current phase=dispatch-wait event=start"),
                    "Opt-in evidence must expose the waiting root before it enters the host.");
                Check(!heldLog.Contains("operation=current phase=dispatch-work event=start"),
                    "A queued request must not be timed as executing in the host.");
#endif
                using var cancellation = new CancellationTokenSource();
                var cancelled = dispatcher.DispatchAsync(Request(AccountBridgeRequestNames.GetCurrent), cancellation.Token);
                cancellation.Cancel();
                try { await cancelled; throw new InvalidOperationException("Cancelled queued root entered the host."); }
                catch (OperationCanceledException) { }
                Check(probe.Currents == 0, "Cancellation must not promote a queued root into execution.");
            }
            finally
            {
                probe.ReadRelease.TrySetResult(new { schemaVersion = 1 });
                await Task.WhenAll(holder, queued).WaitAsync(TimeSpan.FromSeconds(5));
            }
            Check((await queued).Response.Status == "ok" && probe.Currents == 1,
                "Observation cannot bypass the barrier or duplicate the root read.");
#if STARBRIDGE_SESSION_PROBE
            var log = Journal(root);
            var start = log.IndexOf("operation=current phase=dispatch-wait event=start", StringComparison.Ordinal);
            var admitted = log.IndexOf("operation=current phase=dispatch-wait event=returned", StringComparison.Ordinal);
            var work = log.IndexOf("operation=current phase=dispatch-work event=start", StringComparison.Ordinal);
            var finished = log.IndexOf("operation=current phase=dispatch-work event=returned", StringComparison.Ordinal);
            Check(start >= 0 && admitted > start && work > admitted && finished > work,
                "Real gate admission must precede execution, with separate completed observations.");
            await AccountSessionRestoreTests.ColdFirstContent("token");
            log = Journal(root);
            foreach (var phase in new[] { "restore", "local-owner", "projection" })
                Check(log.Contains($"operation=current phase={phase} event=returned"), "Actual SCM root phase missing: " + phase);
            var runtimeEvidence = await MemberReadFailureTiming(root);
            await MemberReadProbeControls(root);
            await OfficialFleetReadTests.MemberCheckpointFailures();
            var resume = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
            Task late;
            using (AccountReadTiming.Begin("synthetic-account-and-token"))
            {
                using (var phase = AccountReadTiming.Measure(AccountReadPhase.Projection)) phase?.Returned();
                late = Task.Run(async () =>
                {
                    await resume.Task;
                    using var retired = AccountReadTiming.Measure(AccountReadPhase.Restore);
                    Check(retired is null, "A background task cannot inherit a retired request's timing identity.");
                });
            }
            resume.SetResult();
            await late.WaitAsync(TimeSpan.FromSeconds(5));
            log = Journal(root);
            Check(log.Contains("operation=other phase=projection event=returned") &&
                !log.Contains("operation=other phase=restore event=start"), "Unknown names are projected; retired contexts stay silent.");
            var probeLines = log.Split('\n').Where(line => line.Contains("[DEBUG-account-wait-20261017]")).ToArray();
            var ordinaryLines = probeLines.Where(line => !line.Contains("operation=official-fleet ")).ToArray();
            var memberLines = probeLines.Where(line => line.Contains("operation=official-fleet ")).ToArray();
            Check(probeLines.Length > 10 && ordinaryLines.All(line => System.Text.RegularExpressions.Regex.IsMatch(line,
                @"^\[[0-9 :.+-]+\] correlationId=account-wait step=account-wait outcome=observation \[DEBUG-account-wait-20261017\] pid=[0-9]+ span=[0-9]+ operation=(current|communities|friends|profile|compatibility|login|logout|other) phase=(dispatch-wait|dispatch-work|restore|local-owner|participation|projection) event=(start|returned|interrupted) elapsedUs=[0-9]+\r?$")) && memberLines.Length > 0 && memberLines.All(line => System.Text.RegularExpressions.Regex.IsMatch(line,
                @"^\[[0-9 :.+-]+\] correlationId=account-wait step=account-wait outcome=observation \[DEBUG-account-wait-20261017\] pid=[0-9]+ span=[0-9]+ operation=official-fleet phase=(dispatch-wait|dispatch-work|restore|local-owner|participation|projection) event=(start|returned|interrupted) elapsedUs=[0-9]+ command=officialFleet\.(getMembers|getRuntimeMembers) schema=(1|2|invalid) code=(pending|none|other|bridge\.(cancelled|host_error|protocol_incompatible|invalid_envelope|account_context_required|stale_generation|timeout|disconnected|backpressure|capability_unavailable)|account\.(reauthorization_required|operation_in_progress)|official_fleet\.(read_unavailable|read_transient|read_forbidden|data_invalid|identity_unavailable|runtime_unavailable)|privacy_publication\.(identity_unavailable|forbidden|identity_required|route_retired|temporarily_unavailable|unavailable|response_invalid)) checkpoint=(none|owner-fence|bootstrap|registered-page|g1-read|g1-deadline|relay|materialize) g1=(none|status-401|status-403|status-429|status-5xx|status-400|status-404|status-other|transport|timeout|contract|host-other|other)\r?$")),
                "Only fixed operation/phase labels and process-local numeric timing may leave the probe.");
            Check(runtimeEvidence.Length == 4 && runtimeEvidence.All(line => memberLines.Contains(line)),
                "Only the original four strict-whitelisted runtime503 span lines may be exported as test evidence");
            foreach (var line in runtimeEvidence) Console.WriteLine(line.TrimEnd('\r'));
            Console.WriteLine("PASS opt-in account timing: actual queue/execute split, real held SCM restore phases and existing owner barriers");
#elif STARBRIDGE_MEMBER_READ_PROBE
            Check(!Journal(root).Contains("[DEBUG-account-wait-20261017]"),
                "Member-only timing stays silent for real nonmember exclusive gate and cancellation reads");
            await AccountSessionRestoreTests.ColdFirstContent("token");
            Check(!Journal(root).Contains("[DEBUG-account-wait-20261017]"),
                "Member-only timing cannot enable current/restore/local-owner/projection account evidence");
            var runtimeEvidence = await MemberReadFailureTiming(root);
            await MemberReadProbeControls(root);
            await OfficialFleetReadTests.MemberCheckpointFailures();
            await MemberOnlyScopeAndConditionalControls(root);
            var log = Journal(root);
            var lines = log.Split('\n').Where(line => line.Contains("[DEBUG-account-wait-20261017]")).ToArray();
            const string pattern = @"^\[[0-9 :.+-]+\] correlationId=account-wait step=account-wait outcome=observation \[DEBUG-account-wait-20261017\] pid=[0-9]+ span=[0-9]+ operation=official-fleet phase=(dispatch-wait|dispatch-work|restore|local-owner|participation|projection) event=(start|returned|interrupted) elapsedUs=[0-9]+ command=officialFleet\.(getMembers|getRuntimeMembers) schema=(1|2|invalid) code=(pending|none|other|bridge\.(cancelled|host_error|protocol_incompatible|invalid_envelope|account_context_required|stale_generation|timeout|disconnected|backpressure|capability_unavailable)|account\.(reauthorization_required|operation_in_progress)|official_fleet\.(read_unavailable|read_transient|read_forbidden|data_invalid|identity_unavailable|runtime_unavailable)|privacy_publication\.(identity_unavailable|forbidden|identity_required|route_retired|temporarily_unavailable|unavailable|response_invalid)) checkpoint=(none|owner-fence|bootstrap|registered-page|g1-read|g1-deadline|relay|materialize) g1=(none|status-401|status-403|status-429|status-5xx|status-400|status-404|status-other|transport|timeout|contract|host-other|other)\r?\z";
            Check(lines.Length > 10 && lines.All(line => System.Text.RegularExpressions.Regex.IsMatch(line, pattern)),
                "Every member-only prefix line must obey the exact two-command/schema/phase/event/code closure");
            Check(runtimeEvidence.Length == 4 && runtimeEvidence.All(line => lines.Contains(line)),
                "Actual original runtime503 evidence must remain the same four tagged lines");
            Check(!log.Contains("[DEBUG-session-probe-20261011]") && !log.Contains("[DEBUG-friends-read-20261011]"),
                "Member-only mode cannot activate old session or friends diagnostic prefixes");
            foreach (var line in runtimeEvidence) Console.WriteLine(line.TrimEnd('\r'));
            Console.WriteLine("PASS member-only account timing: actual member failures and gates, two-command closure, old diagnostics disabled");
#else
            await OfficialFleetReadTests.Failures();
            Check(AccountReadTiming.Begin("officialFleet.getRuntimeMembers") is null &&
                AccountReadTiming.Measure(AccountReadPhase.DispatchWork) is null, "Ordinary member probe remains null/no-op");
            var evaluated = 0;
            string SensitiveArgument() { evaluated++; return "synthetic-sensitive-argument"; }
            AccountReadTiming.Response(SensitiveArgument(), SensitiveArgument(), SensitiveArgument());
            MemberReadCheckpoint SensitiveCheckpoint() { evaluated++; throw new InvalidOperationException("Unexpected checkpoint evaluation"); }
            AccountReadTiming.Checkpoint(SensitiveCheckpoint());
            Check(evaluated == 0, "Conditional response/checkpoint arguments must not execute in ordinary builds");
            Check(!Journal(root).Contains("[DEBUG-account-wait-20261017]"), "Ordinary builds must not write account timing evidence.");
            Console.WriteLine("PASS ordinary account timing: no probe writes; queued root still obeys existing barrier");
#endif
        }
        finally { HostDataRoot.UsePreparedRoot(original); Directory.Delete(root, recursive: true); }
    }

#if STARBRIDGE_SESSION_PROBE || STARBRIDGE_MEMBER_READ_PROBE
    private static async Task MemberReadProbeControls(string root)
    {
        const string member = "officialFleet.getMembers";
        const string runtime = "officialFleet.getRuntimeMembers";
        var offset = Journal(root).Length;
        var resume = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        Task late;
        using (AccountReadTiming.Begin(runtime, 2))
        {
            using var outer = AccountReadTiming.Measure(AccountReadPhase.DispatchWork);
            using (AccountReadTiming.Begin(member, 1))
            {
                using var inner = AccountReadTiming.Measure(AccountReadPhase.DispatchWork);
                AccountReadTiming.Checkpoint(MemberReadCheckpoint.Bootstrap);
                AccountReadTiming.Response(member, "error", "official_fleet.read_forbidden");
            }
            AccountReadTiming.Response("synthetic-sensitive-name", "error", "synthetic-sensitive-code");
            AccountReadTiming.Response(member, "error", "official_fleet.data_invalid");
            AccountReadTiming.Checkpoint(MemberReadCheckpoint.Relay);
            AccountReadTiming.Checkpoint((MemberReadCheckpoint)int.MaxValue);
            AccountReadTiming.Response(runtime, "error", "official_fleet.read_transient");
            late = Task.Run(async () => {
                await resume.Task;
                AccountReadTiming.Checkpoint(MemberReadCheckpoint.Materialize);
                AccountReadTiming.Response(runtime, "error", "synthetic-sensitive-code");
                Check(AccountReadTiming.Measure(AccountReadPhase.Projection) is null, "Retired member context cannot be revived");
            });
        }
        var nested = Journal(root)[offset..];
        Check(nested.Contains("command=officialFleet.getMembers schema=1 code=official_fleet.read_forbidden checkpoint=bootstrap") &&
            nested.Contains("command=officialFleet.getRuntimeMembers schema=2 code=official_fleet.read_transient checkpoint=relay") &&
            !nested.Contains("synthetic-sensitive"), "Nested member scopes must retain their own fixed result, not a sibling or unknown name");
        var beforeLate = Journal(root).Split('\n').Where(line => line.Contains("[DEBUG-account-wait-20261017]")).ToArray();
        resume.SetResult();
        await late.WaitAsync(TimeSpan.FromSeconds(5));
        var afterLate = Journal(root).Split('\n').Where(line => line.Contains("[DEBUG-account-wait-20261017]")).ToArray();
        Check(afterLate.SequenceEqual(beforeLate), "Late inherited context must not append or overwrite probe evidence");
        Console.WriteLine("PASS member probe nested command matching and retired inherited context");

        foreach (var name in new[] { member, runtime })
        {
            var schema = name == runtime ? 2 : 1;
            var start = Journal(root).Length;
            var host = System.Reflection.DispatchProxy.Create<IAccountBridgeHost, MemberTimingProbe>();
            var probe = (MemberTimingProbe)(object)host;
            probe.ConcurrentReads = false;
            using var dispatcher = new AccountBridgeDispatcher(host);
            var holder = dispatcher.DispatchAsync(Request(AccountBridgeRequestNames.ReadCommunities));
            await Until(() => probe.Reads == 1);
            using var cancellation = new CancellationTokenSource();
            var queued = dispatcher.DispatchAsync(MemberTimingRequest(name, schema), cancellation.Token);
            cancellation.Cancel();
            try { await queued; throw new InvalidOperationException("Cancelled member read entered Host"); }
            catch (OperationCanceledException) when (cancellation.IsCancellationRequested) { }
            finally { probe.ReadRelease.TrySetResult(new { schemaVersion = 1 }); await holder; }
            Check(probe.MemberCalls == 0, "Cancelled member read cannot pass the original exclusive gate");
            var rows = Journal(root)[start..].Split('\n').Where(line => line.Contains("command=" + name + " ")).ToArray();
            Check(rows.Length == 2 && rows.Any(line => line.Contains("phase=dispatch-wait event=start")) &&
                rows.Any(line => line.Contains("phase=dispatch-wait event=interrupted") && line.Contains("code=bridge.cancelled")) &&
                rows.All(line => !line.Contains("phase=dispatch-work")), "Queued member cancellation must close the original wait without work");
            Console.WriteLine("PASS member probe original gate cancellation " + name);
        }
        foreach (var name in new[] { member, runtime })
        {
            var start = Journal(root).Length;
            var host = System.Reflection.DispatchProxy.Create<IAccountBridgeHost, MemberTimingProbe>();
            var probe = (MemberTimingProbe)(object)host;
            using var dispatcher = new AccountBridgeDispatcher(host);
            var success = await dispatcher.DispatchAsync(MemberTimingRequest(name, name == runtime ? 2 : 1));
            Check(success.Response.Status == "ok" && probe.MemberCalls == 1, "Diagnostic must preserve synthetic Host success");
            var rows = Journal(root)[start..];
            Check(rows.Contains("phase=dispatch-work event=returned") && rows.Contains("code=none"), "Successful member terminal must stay returned/none");
            foreach (var code in new[] {
                "privacy_publication.identity_unavailable", "privacy_publication.forbidden", "privacy_publication.identity_required",
                "privacy_publication.route_retired", "privacy_publication.temporarily_unavailable", "privacy_publication.unavailable",
                "privacy_publication.response_invalid" })
            {
                probe.FailureCode = code;
                var privacy = await dispatcher.DispatchAsync(MemberTimingRequest(name, name == runtime ? 2 : 1));
                Check(privacy.Response.Error?.Code == code && Journal(root)[start..].Contains("code=" + code + " checkpoint=none"),
                    "Existing fixed privacy code is observed without changing the synthetic Host wire");
            }
            probe.FailureCode = "synthetic-sensitive-code";
            var denied = await dispatcher.DispatchAsync(MemberTimingRequest(name, name == runtime ? 2 : 1));
            Check(denied.Response.Error?.Code == probe.FailureCode, "Probe must not sanitize or change the original synthetic wire code");
            rows = Journal(root)[start..];
            Check(rows.Contains("code=other") && !rows.Contains("synthetic-sensitive-code"), "Unknown wire code must become only fixed other in diagnostics");
            Console.WriteLine("PASS member probe successful and unknown-code Host control " + name);
        }
        {
            var start = Journal(root).Length;
            var host = System.Reflection.DispatchProxy.Create<IAccountBridgeHost, MemberTimingProbe>();
            var probe = (MemberTimingProbe)(object)host;
            using var dispatcher = new AccountBridgeDispatcher(host);
            foreach (var schema in new object[] { "synthetic-sensitive-schema", 3 })
            {
                var response = await dispatcher.DispatchAsync(StarBridge.NativeBridge.BridgeEnvelope.Request(runtime,
                    Guid.NewGuid().ToString("N"), 1, new { schemaVersion = schema }, Probe.Owner));
                Check(response.Response.Status != "ok", "Bad schema must retain original rejection");
            }
            Check(probe.MemberCalls == 0, "Bad schema cannot reach the member Host");
            var rows = Journal(root)[start..];
            Check(rows.Contains("schema=invalid") && !rows.Contains("synthetic-sensitive-schema"), "Schema diagnostic must be closed and payload-free");
            using (AccountReadTiming.Begin(runtime, 2))
            {
                using var phase = AccountReadTiming.Measure(AccountReadPhase.DispatchWork);
                AccountReadTiming.Response(runtime, "synthetic-sensitive-status", "synthetic-sensitive-code");
            }
            Check(!Journal(root)[start..].Contains("synthetic-sensitive"), "Unknown status or error cannot be retained by the probe");
            Console.WriteLine("PASS member probe bad schema and status remain fixed diagnostic labels");
        }
    }

    private static StarBridge.NativeBridge.BridgeEnvelope MemberTimingRequest(string name, int schema) =>
        StarBridge.NativeBridge.BridgeEnvelope.Request(name, Guid.NewGuid().ToString("N"), 1,
            new { schemaVersion = schema, sourceRef = "officialFleet:7", search = "", filter = "all", pageNumber = 1, pageSize = 50 }, Probe.Owner);

    public class MemberTimingProbe : Probe
    {
        internal int MemberCalls;
        internal string? FailureCode;
        protected override object? Invoke(System.Reflection.MethodInfo? method, object?[]? args)
        {
            if (method is not null && method.Name is ("GetOfficialFleetMembersAsync" or "GetOfficialFleetRuntimeMembersAsync"))
            {
                Interlocked.Increment(ref MemberCalls);
                return FailureCode is { } code ? Task.FromException<object>(new AccountBridgeHostException(code)) :
                    Task.FromResult<object>(new { schemaVersion = method.Name == "GetOfficialFleetRuntimeMembersAsync" ? 2 : 1 });
            }
            return base.Invoke(method, args);
        }
    }

    private static async Task<string[]> MemberReadFailureTiming(string root)
    {
        var offset = Journal(root).Length;
        await OfficialFleetReadTests.Failures();
        Console.WriteLine("PASS actual runtime503 stable wire and original schema1 controls precede member probe assertion");
        var lines = Journal(root)[offset..].Split('\n')
            .Where(line => line.Contains("[DEBUG-account-wait-20261017]")).ToArray();
        var pattern = @"pid=(?<pid>[0-9]+) span=(?<span>[0-9]+) operation=official-fleet phase=(?<phase>dispatch-wait|dispatch-work) event=(?<event>start|returned|interrupted) elapsedUs=[0-9]+ command=(?<command>officialFleet\.getMembers|officialFleet\.getRuntimeMembers) schema=(?<schema>1|2|invalid) code=(?<code>[a-z0-9_.-]+) checkpoint=(?<checkpoint>none|owner-fence|bootstrap|registered-page|g1-read|g1-deadline|relay|materialize) g1=(?<g1>none|status-401|status-403|status-429|status-5xx|status-400|status-404|status-other|transport|timeout|contract|host-other|other)\r?$";
        var tagged = lines.Select(line => System.Text.RegularExpressions.Regex.Match(line, pattern))
            .Where(match => match.Success).ToArray();
        var workInterrupted = lines.Count(line => line.Contains("phase=dispatch-work event=interrupted"));
        Console.WriteLine($"OBSERVED member read probe: lines={lines.Length}, tagged={tagged.Length}, interruptedWork={workInterrupted}");
        Check(workInterrupted > 0, "Actual caught read failures must retain the original interrupted work terminal");
        var firstRuntime = tagged.FirstOrDefault(match => match.Groups["command"].Value == "officialFleet.getRuntimeMembers");
        if (firstRuntime is null)
            throw new InvalidOperationException("First runtime member read must expose fixed command/schema/final stable code in its original span");
        var runtimeSpan = tagged.Where(match => match.Groups["pid"].Value == firstRuntime.Groups["pid"].Value &&
            match.Groups["span"].Value == firstRuntime.Groups["span"].Value).ToArray();
        Check(runtimeSpan.All(match => match.Groups["command"].Value == "officialFleet.getRuntimeMembers" &&
                match.Groups["schema"].Value == "2") &&
            runtimeSpan.Count(match => match.Groups["phase"].Value == "dispatch-work" && match.Groups["event"].Value == "start") == 1 &&
            runtimeSpan.Count(match => match.Groups["phase"].Value == "dispatch-work" && match.Groups["event"].Value == "interrupted" &&
                match.Groups["code"].Value == "official_fleet.read_transient" && match.Groups["checkpoint"].Value == "registered-page") == 1,
            "The actual first runtime503 must keep one start/interrupted work pair and capture the final transient code before Dispose");
        Check(tagged.Any(match => match.Groups["command"].Value == "officialFleet.getMembers" &&
            match.Groups["schema"].Value == "1" && match.Groups["phase"].Value == "dispatch-work" &&
            match.Groups["event"].Value == "interrupted" && match.Groups["code"].Value == "official_fleet.read_transient"),
            "Existing schema1 member read must also expose its actual transient terminal");
        Check(lines.All(line => !line.Contains("runtime-private-detail") && !line.Contains("runtime-503-private-detail") &&
            !line.Contains("private-fault-detail") && !line.Contains("synthetic-access") && !line.Contains("fixture-owner")),
            "Only fixed diagnostic fields may leave the two member-read spans");
        Console.WriteLine("PASS actual member reads share fixed command/schema/final code and registered-page checkpoint with their original work terminal");
        return lines.Where(line => {
            var match = System.Text.RegularExpressions.Regex.Match(line, pattern);
            return match.Success && match.Groups["pid"].Value == firstRuntime.Groups["pid"].Value &&
                match.Groups["span"].Value == firstRuntime.Groups["span"].Value;
        }).ToArray();
    }
#endif

#if STARBRIDGE_MEMBER_READ_PROBE && !STARBRIDGE_SESSION_PROBE
    private static async Task MemberOnlyScopeAndConditionalControls(string root)
    {
        var evaluated = 0;
        T Unevaluated<T>() { evaluated++; throw new InvalidOperationException("Conditional diagnostic argument executed"); }
        StarBridge.HostRuntime.Auth.ScmSessionProbeDiagnostics.Configure(Unevaluated<System.Net.WebSockets.ClientWebSocket>());
        StarBridge.HostRuntime.Auth.ScmSessionProbeDiagnostics.Snapshot(StarBridge.HostRuntime.Auth.SessionProbeSnapshot.ValidatedResponse,
            Unevaluated<StarBridge.HostRuntime.Privacy.GameIdSettingsSnapshot>());
        StarBridge.HostRuntime.Auth.ScmSessionProbeDiagnostics.Realtime(StarBridge.HostRuntime.Auth.SessionProbePhase.Ticket,
            Unevaluated<Uri>(), Unevaluated<int>(), Unevaluated<int>(), Unevaluated<Exception>());
        StarBridge.HostRuntime.Friends.FriendsReadProbeDiagnostics.Record(StarBridge.HostRuntime.Friends.FriendsProbePhase.HostBoundary,
            Unevaluated<int>(), Unevaluated<Exception>());
        StarBridge.HostRuntime.Friends.FriendsReadProbeDiagnostics.DispatchFailure(Unevaluated<string>(), Unevaluated<Exception>());
        Check(evaluated == 0, "Old session/friends Conditional arguments must evaluate zero times in member-only mode");
        var offset = Journal(root).Length;
        var resume = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        Task late;
        using (AccountReadTiming.Begin(AccountBridgeRequestNames.GetOfficialFleetRuntimeMembers, 2))
        {
            using var outer = AccountReadTiming.Measure(AccountReadPhase.DispatchWork);
            using (AccountReadTiming.Begin(AccountBridgeRequestNames.GetCurrent, 0))
            {
                using var nested = AccountReadTiming.Measure(AccountReadPhase.Projection);
                AccountReadTiming.Checkpoint(MemberReadCheckpoint.Bootstrap);
                AccountReadTiming.Response(AccountBridgeRequestNames.GetOfficialFleetRuntimeMembers, "error", "official_fleet.data_invalid");
                nested?.Returned();
            }
            AccountReadTiming.Response(AccountBridgeRequestNames.GetOfficialFleetRuntimeMembers, "ok", null);
            outer?.Returned();
            late = Task.Run(async () => {
                await resume.Task;
                Check(AccountReadTiming.Measure(AccountReadPhase.Restore) is null, "Retired outer member scope remains retired");
            });
        }
        var nestedRows = Journal(root)[offset..].Split('\n').Where(line => line.Contains("[DEBUG-account-wait-20261017]")).ToArray();
        Check(nestedRows.Length == 2 && nestedRows.All(line => line.Contains("operation=official-fleet phase=dispatch-work ")) &&
            nestedRows[0].Contains("event=start") && nestedRows[1].Contains("event=returned") && nestedRows[1].Contains("code=none checkpoint=none"),
            "Nested nonmember scope must be silent and cannot inherit, tag or overwrite the outer member span");
        var beforeLate = Journal(root);
        resume.SetResult(); await late.WaitAsync(TimeSpan.FromSeconds(5));
        Check(Journal(root) == beforeLate, "Late inherited member context cannot append evidence");
        foreach (var assembly in new[] { typeof(AccountReadTiming).Assembly, typeof(AccountDispatchConcurrencyTests).Assembly })
        {
            var metadata = assembly.GetCustomAttributes(typeof(System.Reflection.AssemblyMetadataAttribute), false)
                .Cast<System.Reflection.AssemblyMetadataAttribute>().Single(value => value.Key == "StarBridgeMemberReadProbeEnabled");
            Check(metadata.Value == "true", "Actual Host and test assemblies must mark member-only diagnostics true");
        }
        Console.WriteLine("PASS member-only nested nonmember neutrality, old Conditional zero evaluation and actual build metadata");
    }
#endif

    private static string Journal(string root)
    {
        var path = Path.Combine(root, "scm-auth-diagnostics.log");
        return File.Exists(path) ? File.ReadAllText(path) : "";
    }
}
