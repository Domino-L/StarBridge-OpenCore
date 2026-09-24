using System.Diagnostics;
using System.Text.Json;
using StarBridge.Core.Hangar;
using StarBridge.Core.Identity;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.Hangar;

internal static class HangarIdentityGuardTests
{
    private static readonly Uri Hangar = new("https://robertsspaceindustries.com/en/account/pledges?page=1");

    public static Task MatchesVerifiedSession()
    {
        var current = Context();
        var guard = Ready(() => current);
        Expect(HangarIdentityGuardState.Matched, guard.Assess(1, Hangar, Observation("Pilot_Alpha")));
        var mismatch = guard.Assess(1, Hangar, Observation("Pilot_Beta"));
        Expect(HangarIdentityGuardState.IdentityRejected, mismatch);
        if (mismatch.Identity?.State != RsiHangarIdentityState.Mismatch) throw new Exception("Mismatch was lost");
        var ambiguous = guard.Assess(1, Hangar, Observation("Pilot_Alpha", "Pilot_Beta"));
        if (ambiguous.Identity?.State != RsiHangarIdentityState.ReaderIdentityAmbiguous) throw new Exception("Ambiguous identity accepted");
        current = current with { Identity = current.Identity with { Status = ScmGameIdentityStatus.Revoked } };
        Expect(HangarIdentityGuardState.IdentityRejected, guard.Assess(1, Hangar, Observation("Pilot_Alpha")));
        return Task.CompletedTask;
    }

    public static Task NavigationInvalidatesObservation()
    {
        var guard = Ready(() => Context());
        guard.NavigationStarted(2);
        Expect(HangarIdentityGuardState.DocumentUnavailable, guard.Assess(1, Hangar, Observation("Pilot_Alpha")));
        guard.NavigationCompleted(1, Hangar, true);
        Expect(HangarIdentityGuardState.DocumentUnavailable, guard.Assess(2, Hangar, Observation("Pilot_Alpha")));
        guard.NavigationCompleted(2, Hangar, false);
        guard.NavigationCompleted(2, Hangar, true);
        Expect(HangarIdentityGuardState.DocumentUnavailable, guard.Assess(2, Hangar, Observation("Pilot_Alpha")));
        guard.NavigationStarted(2);
        guard.NavigationCompleted(2, Hangar, true);
        Expect(HangarIdentityGuardState.DocumentUnavailable, guard.Assess(2, Hangar, Observation("Pilot_Alpha")));
        guard.NavigationStarted(3);
        guard.NavigationCompleted(3, Hangar, true);
        Expect(HangarIdentityGuardState.Matched, guard.Assess(3, Hangar, Observation("Pilot_Alpha")));
        Expect(HangarIdentityGuardState.DocumentUnavailable, guard.Assess(2, Hangar, Observation("Pilot_Alpha")));
        var pageTwo = new Uri("https://robertsspaceindustries.com/en/account/pledges?page=2");
        Expect(HangarIdentityGuardState.DocumentUnavailable, guard.Assess(3, pageTwo, Observation("Pilot_Alpha")));
        return Task.CompletedTask;
    }

    public static Task AccountSwitchAndCancelInvalidateImport()
    {
        foreach (var change in new Func<HangarAccountIdentity, HangarAccountIdentity>[] {
            c => c with { Generation = c.Generation + 1 },
            c => c with { Account = c.Account with { Subject = "subject-b" } },
            c => c with { Account = c.Account with { Subject = "SUBJECT-A" } },
            c => c with { Account = c.Account with { Environment = "production" } },
            c => c with { Account = c.Account with { Authority = "other-issuer" } },
            c => c with { Identity = c.Identity with { Handle = "Pilot_Beta", NormalizedHandle = "pilot_beta" } }
        })
        {
            var current = Context();
            var guard = Ready(() => current);
            current = change(current);
            Expect(HangarIdentityGuardState.AccountChanged, guard.Assess(1, Hangar, Observation("Pilot_Alpha")));
            current = Context();
            Expect(HangarIdentityGuardState.AccountChanged, guard.Assess(1, Hangar, Observation("Pilot_Alpha")));
        }
        HangarAccountIdentity? maybeCurrent = Context();
        var signedOut = Ready(() => maybeCurrent);
        maybeCurrent = null;
        Expect(HangarIdentityGuardState.AccountChanged, signedOut.Assess(1, Hangar, Observation("Pilot_Alpha")));
        var cancelled = Ready(() => Context());
        cancelled.Cancel();
        cancelled.NavigationStarted(2);
        cancelled.NavigationCompleted(2, Hangar, true);
        Expect(HangarIdentityGuardState.Cancelled, cancelled.Assess(2, Hangar, Observation("Pilot_Alpha")));
        return Task.CompletedTask;
    }

    public static Task UntrustedDocumentsAndMessagesAreRejected()
    {
        foreach (var source in new[] {
            "http://robertsspaceindustries.com/account/pledges",
            "https://robertsspaceindustries.com.example.invalid/account/pledges",
            "https://example.invalid/account/pledges",
            "https://robertsspaceindustries.com:444/account/pledges",
            "https://user" + "@robertsspaceindustries.com/account/pledges",
            "https://robertsspaceindustries.com/en/citizens/Pilot_Alpha",
            "https://robertsspaceindustries.com/en/account/settings",
            "https://robertsspaceindustries.com/en/account/pledges-extra",
            "https://robertsspaceindustries.com/en/account/pledges#other",
            "https://sub.robertsspaceindustries.com/en/account/pledges"
        })
        {
            var uri = new Uri(source);
            if (HangarIdentityGuard.IsHangarDocument(uri)) throw new Exception("Unexpected trusted document");
            var guard = new HangarIdentityGuard(Context(), () => Context());
            guard.NavigationStarted(1); guard.NavigationCompleted(1, uri, true);
            Expect(HangarIdentityGuardState.DocumentUnavailable, guard.Assess(1, uri, Observation("Pilot_Alpha")));
        }
        if (!HangarIdentityGuard.IsHangarDocument(new("https://robertsspaceindustries.com/account/pledges")))
            throw new Exception("Existing hangar path rejected");
        var ready = Ready(() => Context());
        foreach (var malformed in new[] { "", "{", "[]", "null", new string('x', 4097),
            Observation("Pilot_Alpha").Replace("current-account", "public-profile"),
            Observation("Pilot_Alpha").Replace("page=1", "page=2"),
            Observation("Pilot_Alpha").Replace("[\"Pilot_Alpha\"]", "[true]"),
            Observation("Pilot_Alpha").Replace("\"schemaVersion\":1", "\"schemaVersion\":\"1\""),
            Observation("Pilot_Alpha").Replace("\"schemaVersion\":1", "\"schemaVersion\":1,\"schemaVersion\":1"),
            Observation("Pilot_Alpha").Replace("\"schemaVersion\":1", "\"schemaVersion\":1,\"cookie\":\"forbidden\"") })
            Expect(HangarIdentityGuardState.InvalidObservation, ready.Assess(1, Hangar, malformed));
        Expect(HangarIdentityGuardState.IdentityRejected, ready.Assess(1, Hangar, Observation()));
        return Task.CompletedTask;
    }

    // Optional separate executable exercises the real WebView2 DOM engine with synthetic data only.
    public static async Task<int> RunNativeProbe(string executable)
    {
        using var process = Process.Start(new ProcessStartInfo(executable) {
            UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true
        }) ?? throw new Exception("Probe did not start");
        using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(50));
        var outputTask = process.StandardOutput.ReadToEndAsync(deadline.Token);
        var errorTask = process.StandardError.ReadToEndAsync(deadline.Token);
        try { await process.WaitForExitAsync(deadline.Token); }
        catch { if (!process.HasExited) process.Kill(entireProcessTree: true); throw; }
        var output = await outputTask;
        var errors = await errorTask;
        if (process.ExitCode != 0) throw new Exception($"Native fixture probe failed ({process.ExitCode}): {errors}");
        using var payload = JsonDocument.Parse(output);
        var expected = new[] { RsiHangarIdentityState.Matched, RsiHangarIdentityState.Mismatch,
            RsiHangarIdentityState.ReaderIdentityUnavailable, RsiHangarIdentityState.ReaderIdentityAmbiguous,
            RsiHangarIdentityState.Matched, RsiHangarIdentityState.ReaderIdentityUnavailable,
            // Observed RSI account-panel shape: same name, wrong Handle, different display name.
            RsiHangarIdentityState.Matched, RsiHangarIdentityState.Mismatch, RsiHangarIdentityState.Matched,
            RsiHangarIdentityState.ReaderIdentityUnavailable, // Missing explicit field.
            RsiHangarIdentityState.Matched, RsiHangarIdentityState.ReaderIdentityAmbiguous, // Duplicate fields.
            RsiHangarIdentityState.ReaderIdentityUnavailable, // Doubled @.
            RsiHangarIdentityState.ReaderIdentityUnavailable, // Space after @.
            RsiHangarIdentityState.ReaderIdentityUnavailable, // Empty field.
            RsiHangarIdentityState.ReaderIdentityUnavailable, // Display name with a misleading field marker.
            RsiHangarIdentityState.ReaderIdentityUnavailable, // Public profile outside the panel.
            RsiHangarIdentityState.ReaderIdentityUnavailable, // Two panel roots.
            RsiHangarIdentityState.ReaderIdentityUnavailable, // Valid and invalid explicit fields.
            RsiHangarIdentityState.Matched, // Explicit field with no presentation prefix.
            RsiHangarIdentityState.ReaderIdentityUnavailable }; // id must not be confused with data-cy-id.
        var expectedClaimCounts = new[] { 1, 1, 0, 2, 2, 0, 1, 1, 1, 1, 2, 2, 1, 1, 1, 1, 0, 0, 2, 1, 0 };
        var results = payload.RootElement.GetProperty("identity").EnumerateArray().ToArray();
        if (results.Length != expected.Length) throw new Exception("Incomplete native fixture results");
        for (var index = 0; index < results.Length; index++)
        {
            var item = results[index];
            if (item.EnumerateObject().Count() != 4 ||
                item.GetProperty("schemaVersion").GetInt32() != 1 ||
                item.GetProperty("sourceKind").GetString() != "current-account" ||
                item.GetProperty("documentUrl").GetString() != "about:blank")
                throw new Exception($"Native fixture {index} returned an unexpected envelope");
            var values = results[index].GetProperty("handles").EnumerateArray().Select(h => h.GetString()).ToArray();
            if (values.Length != expectedClaimCounts[index]) throw new Exception($"Native fixture {index} collected non-Handle fields");
            var result = RsiHangarIdentityPolicy.Evaluate(Context().Identity, values);
            if (result.State != expected[index]) throw new Exception($"Native fixture {index} failed");
            // A synthetic document can exercise parsing, but can never authorize real import.
            Expect(HangarIdentityGuardState.InvalidObservation, Ready(() => Context()).Assess(1, Hangar, results[index].GetRawText()));
        }
        Console.WriteLine($"PASS Native WebView2 DOM -> Core Handle comparison: {results.Length}/{results.Length}; synthetic origin cannot authorize import");
        HangarPageProbeTests.Verify(payload.RootElement.GetProperty("pages"));
        HangarReaderDispatcherTests.VerifyNativeCaptures(payload.RootElement.GetProperty("runnerCaptures"));
        HangarReaderDispatcherTests.VerifyNativeContinuousScan(payload.RootElement.GetProperty("runnerPaging"));
        HangarReaderDispatcherTests.VerifyNativePreparation(payload.RootElement.GetProperty("runnerPreparation"));
        return 0;
    }

    private static HangarAccountIdentity Context() => HangarAccountIdentity.FromSession("development", 7,
        new ScmOAuthSession("synthetic-issuer", "subject-a", "NotAHandle", "synthetic-only", DateTimeOffset.MaxValue, [],
            GameIdentityHandle: "Pilot_Alpha", GameIdentityStatus: ScmGameIdentityStatus.Verified, GameIdentityNormalizedHandle: "pilot_alpha"));

    private static HangarIdentityGuard Ready(Func<HangarAccountIdentity?> current)
    {
        var guard = new HangarIdentityGuard(Context(), current);
        guard.NavigationStarted(1); guard.NavigationCompleted(1, Hangar, true);
        return guard;
    }

    private static string Observation(params string[] handles) => JsonSerializer.Serialize(new {
        schemaVersion = 1, sourceKind = "current-account", documentUrl = Hangar.AbsoluteUri, handles
    });

    private static void Expect(HangarIdentityGuardState expected, HangarIdentityCheck result)
    {
        if (result.State != expected || result.CanContinue != (expected == HangarIdentityGuardState.Matched))
            throw new Exception($"Guard expected {expected}, actual {result.State}");
    }
}
