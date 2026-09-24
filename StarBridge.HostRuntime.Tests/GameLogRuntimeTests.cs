using System.Text.Json;
using StarBridge.HostRuntime.Presence;
using StarBridge.NativeBridge;

internal static class GameLogRuntimeTests
{
    private static readonly BridgeAccountContext Owner = new("test", "scm", "synthetic-log-reader");
    private sealed class Clock : TimeProvider
    {
        internal DateTimeOffset Now = DateTimeOffset.Parse("2026-09-04T12:00:30Z");
        public override DateTimeOffset GetUtcNow() => Now;
    }
    private sealed class Harness : IDisposable
    {
        internal readonly string Root = Path.Combine(Path.GetTempPath(), "starbridge-log-test-" + Guid.NewGuid().ToString("N"));
        internal string Log => Path.Combine(Root, "StarCitizen", "LIVE", "Game.log");
        internal readonly Clock Time = new();
        internal (BridgeAccountContext? Context, long Generation) Current = (Owner, 1);
        internal GameProcessSession Process;
        internal GameLogRuntime Runtime;
        internal Harness()
        {
            Directory.CreateDirectory(Root);
            Directory.CreateDirectory(Path.GetDirectoryName(Log)!);
            File.WriteAllText(Log, Identity("Pilot_A"));
            Process = new("running", Log, Time.Now.AddSeconds(-30), "synthetic-process-1");
            Runtime = Create();
        }
        internal GameLogRuntime Create() => new(new GameLogSettingsStore(Root), () => Current,
            () => "Pilot_A", () => Process, Time, false, new GameLogLocator(() => [Path.Combine(Root, "StarCitizen")]));
        internal BridgeEnvelope Request(string command = "read", string? path = null) =>
            BridgeEnvelope.Request("gameLog." + command, Guid.NewGuid().ToString("N"), Current.Generation,
                path is null ? new { schemaVersion = 1 } : (object)new { schemaVersion = 1, path }, Current.Context);
        internal BridgeEnvelope Call(string command = "read", string? path = null) => Runtime.Dispatch(Request(command, path)).Response;
        public void Dispose() { Runtime.Dispose(); Directory.Delete(Root, true); }
    }
    private static string Identity(string handle, string id = "12345", string stamp = "2026-09-04T12:00:10Z") =>
        $"<{stamp}> [Notice] nickname=\"{handle}\" playerGEID={id}\n";
    private static string Line(string body, string stamp = "2026-09-04T12:00:20Z") =>
        $"<{stamp}> {body}\n";
    private static void Require(bool condition, string message) { if (!condition) throw new InvalidOperationException(message); }
    internal static Task DiagnosticsSelection()
    {
        using var h = new Harness();
        Require(h.Call("select", h.Log).Status == BridgeResponseStatuses.Ok, "select existing game log owner");
        Require(h.Call().Payload.GetProperty("observedAtUtc").GetDateTimeOffset() == h.Time.Now,
            "check timestamp comes from the existing Host observation clock");
        Require(h.Runtime.SelectedPathForDiagnostics == h.Log, "diagnostics borrows active selection");
        Require(h.Call().Status == BridgeResponseStatuses.Ok, "diagnostics did not acquire a competing store lease");
        h.Current = (Owner with { Subject = "another-owner" }, 2);
        try { _ = h.Runtime.SelectedPathForDiagnostics; throw new Exception("old account selection leaked"); }
        catch (InvalidOperationException) { }
        h.Current = (null, 3);
        Require(h.Runtime.SelectedPathForDiagnostics is null, "signed-out diagnostics has no old selection");
        return Task.CompletedTask;
    }

    internal static Task Recognition()
    {
        using var h = new Harness();
        GameLogIdentityObservation Read() => GameLogIdentityReader.Read(h.Log, h.Process, h.Time.Now);
        Require(Read() == new GameLogIdentityObservation("identified", "Pilot_A"), "Canonical nickname plus GEID identifies current game.");
        File.WriteAllText(h.Log, Identity("Old_Pilot", stamp: "2026-09-03T12:00:10Z") + Identity("Pilot_A") + Identity("pilot_a"));
        Require(Read().Handle == "Pilot_A", "Old sessions excluded, repeated same identity case-insensitive.");
        File.AppendAllText(h.Log, Identity("Pilot_B"));
        Require(Read().State == "ambiguous", "Two current identities never guessed.");
        File.WriteAllText(h.Log, "<2026-09-04T12:00:10Z> displayName=\"Pilot_A\"\n" + Identity("Pilot_A", "0"));
        Require(Read().State == "waiting", "Display names and zero GEID cannot establish identity.");
        File.WriteAllText(h.Log, Identity("Pilot_A").TrimEnd('\n'));
        Require(Read().State == "waiting", "Incomplete line not consumed.");
        File.AppendAllText(h.Log, "\n");
        Require(Read().State == "identified", "Completed line becomes available.");
        File.AppendAllText(h.Log, "<2026-09-04T12:00:20Z> SystemQuit CSystem::Quit\n");
        Require(Read().State == "waiting", "Quit does not retain current identity.");
        Require(GameLogIdentityReader.Read(h.Log, h.Process with { State = "notRunning" }, h.Time.Now).Handle is null,
            "Offline processes never retain identity.");
        Require(GameLogIdentityReader.Read(h.Log, h.Process with { LogPath = Path.Combine(h.Root, "Other", "Game.log") },
            h.Time.Now).State == "differentInstallation", "Selection must match the running game install.");
        return Task.CompletedTask;
    }
    internal static Task Lifecycle()
    {
        using var h = new Harness();
        Require(h.Call().Payload.GetProperty("channel").GetString() == "LIVE", "Automatic selection defaults to LIVE.");
        var selected = h.Call("select", h.Log);
        Require(selected.Status == "ok" && selected.Payload.GetProperty("match").GetString() == "match",
            "Selection persists then identifies. " +
            (selected.Error?.Code ?? selected.Payload.GetRawText()));
        Require(h.Runtime.DetectedHandle == "Pilot_A", "Existing account policy receives current identity.");
        Require(h.Runtime.IdentityPolicyState == StarBridge.Core.Identity.LocalIdentityCheckState.Match,
            "A matching check becomes the retained account policy input.");
        h.Time.Now = h.Time.Now.AddSeconds(11);
        Require(h.Runtime.DetectedHandle is null, "Unrefreshed identity expires.");
        Require(h.Runtime.IdentityPolicyState == StarBridge.Core.Identity.LocalIdentityCheckState.Match,
            "Current observation expiry cannot clear a completed identity check.");
        h.Runtime.Sample();
        Require(h.Runtime.DetectedHandle == "Pilot_A", "Host sampling works independently of page.");
        h.Runtime.Dispose(); h.Runtime = h.Create();
        Require(h.Call().Payload.GetProperty("match").GetString() == "match", "Path and listening choice reopen.");
        Require(h.Runtime.IdentityPolicyState == StarBridge.Core.Identity.LocalIdentityCheckState.Match,
            "A completed identity check reopens without storing the detected Handle.");
        h.Call("stop");
        Require(h.Runtime.DetectedHandle is null, "Stop clears identity.");
        Require(h.Runtime.IdentityPolicyState == StarBridge.Core.Identity.LocalIdentityCheckState.Match,
            "Stopping continuous recognition preserves the completed identity check.");
        h.Runtime.Dispose(); h.Runtime = h.Create();
        Require(h.Call().Payload.GetProperty("state").GetString() == "stopped", "Stop choice survives restart.");
        Require(h.Runtime.IdentityPolicyState == StarBridge.Core.Identity.LocalIdentityCheckState.Match,
            "Stopped recognition keeps the completed check after restart.");
        h.Call("select", h.Log);
        File.WriteAllText(h.Log, Identity("Pilot_B"));
        Require(h.Call().Payload.GetProperty("match").GetString() == "mismatch", "Account mismatch is explicit.");
        Require(h.Runtime.IdentityPolicyState == StarBridge.Core.Identity.LocalIdentityCheckState.Mismatch,
            "A different current Handle replaces the retained match.");
        h.Process = new("notRunning");
        h.Runtime.Sample();
        Require(h.Runtime.DetectedHandle is null, "Exit clears policy input.");
        Require(h.Runtime.IdentityPolicyState == StarBridge.Core.Identity.LocalIdentityCheckState.Mismatch,
            "Exiting the game cannot erase a mismatch before a later matching check.");
        h.Runtime.Dispose(); h.Runtime = h.Create();
        h.Call();
        Require(h.Runtime.IdentityPolicyState == StarBridge.Core.Identity.LocalIdentityCheckState.Mismatch,
            "A mismatch stays blocked after restart.");
        File.WriteAllText(h.Log, Identity("Pilot_A"));
        h.Process = new("running", h.Log, h.Time.Now.AddSeconds(-30), "synthetic-process-2");
        h.Call();
        Require(h.Runtime.IdentityPolicyState == StarBridge.Core.Identity.LocalIdentityCheckState.Match,
            "The next matching game session restores the completed check.");
        return Task.CompletedTask;
    }

    internal static Task MalformedUtf8Lines()
    {
        using var h = new Harness();
        // Game logs may contain non-UTF8 bytes in unrelated diagnostic lines.
        // Never copy a real player's log into the regression fixture.
        using (var append = new FileStream(h.Log, FileMode.Append, FileAccess.Write))
            append.Write([0xFF, 0xFE, (byte)'\n']);
        File.AppendAllText(h.Log, Line("<Join PU> connected to shard[pub_sc_alpha_apse1_123]"));
        var recovered = h.Call("select", h.Log);
        Require(recovered.Status == "ok" && recovered.Payload.GetProperty("state").GetString() == "identified",
            "Malformed unrelated line must not make a readable file unreadable.");
        Require(h.Runtime.DetectedHandle == "Pilot_A" &&
            recovered.Payload.GetProperty("session").GetProperty("server").GetProperty("state").GetString() == "connected",
            "Valid identity and later server evidence survive unrelated malformed bytes.");
        h.Runtime.Sample();
        Require(h.Runtime.DetectedHandle == "Pilot_A", "Background reads continue without manual refresh.");

        using (var append = new FileStream(h.Log, FileMode.Append, FileAccess.Write))
        {
            append.Write(System.Text.Encoding.UTF8.GetBytes(Identity("Pilot_B").TrimEnd('\n')));
            append.Write([0xFF, (byte)'\n']);
        }
        h.Runtime.Sample();
        Require(h.Runtime.DetectedHandle is null,
            "Malformed possible identity cannot be silently ignored to keep trusting an earlier identity.");
        Require(h.Call().Payload.GetProperty("state").GetString() != "unreadable",
            "Malformed evidence is not a filesystem access failure.");

        File.WriteAllText(h.Log, Identity("Pilot_A"));
        h.Process = h.Process with { SessionId = "synthetic-process-restarted" };
        h.Runtime.Sample();
        Require(h.Runtime.DetectedHandle == "Pilot_A", "A fresh valid session recovers without manual refresh.");
        using (var append = new FileStream(h.Log, FileMode.Append, FileAccess.Write))
        {
            append.Write(System.Text.Encoding.UTF8.GetBytes(Line("SystemQuit CSystem::Quit").TrimEnd('\n')));
            append.Write([0xFF, (byte)'\n']);
        }
        h.Runtime.Sample();
        Require(h.Runtime.DetectedHandle is null, "Malformed quit evidence cannot preserve current identity.");
        return Task.CompletedTask;
    }

    internal static Task SessionContext()
    {
        using var h = new Harness();
        File.WriteAllText(h.Log,
            Identity("Pilot_A") +
            Line("[Notice] server selected pub_sc_alpha_apse1_123") +
            Line("<SHUDEvent_OnNotification> Added notification \"You joined channel 'Anvil Arrow : Other_Pilot'\""));
        var guarded = h.Call("find").Payload.GetProperty("session");
        Require(guarded.GetProperty("state").GetString() == "ready" &&
            guarded.GetProperty("server").GetProperty("state").GetString() == "unknown" &&
            guarded.GetProperty("location").GetProperty("state").GetString() == "unknown" &&
            guarded.GetProperty("ship").GetProperty("state").GetString() == "unknown",
            "Generic server text and another player's ship channel are not treated as local session facts.");

        File.AppendAllText(h.Log,
            Line("<Join PU> connected to shard[pub_sc_alpha_apse1_123]") +
            Line("<RequestLocationInventory> Player[Other_Pilot] requested inventory for Location[Area04]") +
            Line("<RequestLocationInventory> Player[Pilot_A] requested inventory for Location[Stanton1_Lorville]") +
            Line("<SHUDEvent_OnNotification> Added notification \"You joined channel 'Anvil Arrow : Pilot_A'\""));
        var active = h.Call().Payload.GetProperty("session");
        Require(active.GetProperty("server").GetProperty("state").GetString() == "connected" &&
            active.GetProperty("server").GetProperty("region").GetString() == "ASIA" &&
            active.GetProperty("server").GetProperty("shard").GetString() == "pub_sc_alpha_apse1_123",
            "An authoritative shard join exposes the broad server and its canonical shard.");
        var ship = active.GetProperty("ship");
        Require(ship.GetProperty("state").GetString() == "confirmed" &&
            ship.GetProperty("key").GetString() == "ANVL_Arrow" &&
            ship.GetProperty("names").GetProperty("zhHans").GetString() == "箭矢",
            "The local ship channel confirms and localizes the current ship.");
        var location = active.GetProperty("location");
        var hasLocationPack = GameLogLocationCatalogTests.HasPack;
        Require(hasLocationPack
            ? location.GetProperty("state").GetString() == "confirmed" &&
              location.GetProperty("englishName").GetString() == "Lorville" &&
              location.GetProperty("names").GetProperty("zhHans").GetString() == "罗威尔"
            : location.GetProperty("state").GetString() == "unknown" &&
              !location.TryGetProperty("englishName", out _) &&
              !location.GetProperty("names").TryGetProperty("zhHans", out _),
            "The optional catalog localizes known locations; a missing catalog leaves public location unknown.");
        Require(!active.GetRawText().Contains("Stanton1_Lorville", StringComparison.Ordinal),
            "Raw location identifiers do not cross the host boundary.");

        File.AppendAllText(h.Log,
            Line("<Player Selected Quantum Target - Local> | AUTH | ANVL_Arrow_101[1]| Player has selected point Area04 as their destination"));
        var afterNavigation = h.Call().Payload.GetProperty("session").GetProperty("location");
        Require(hasLocationPack
            ? afterNavigation.GetProperty("englishName").GetString() == "Lorville"
            : afterNavigation.GetProperty("state").GetString() == "unknown" &&
              !afterNavigation.TryGetProperty("englishName", out _),
            "A navigation target cannot replace the current confirmed location.");

        File.AppendAllText(h.Log,
            Line("<SHUDEvent_OnNotification> Added notification \"You left channel 'Anvil Arrow : Other_Pilot'\""));
        Require(h.Call().Payload.GetProperty("session").GetProperty("ship").GetProperty("state").GetString() == "confirmed",
            "Another player's exit cannot clear the local ship.");
        File.AppendAllText(h.Log,
            Line("<SHUDEvent_OnNotification> Added notification \"You left channel 'Anvil Arrow : Pilot_A'\""));
        Require(h.Call().Payload.GetProperty("session").GetProperty("ship").GetProperty("state").GetString() == "unknown",
            "The local ship channel exit clears the ship.");

        File.AppendAllText(h.Log,
            Line("<RequestLocationInventory> Player[Pilot_A] requested inventory for Location[Future_Unmapped_Secret]"));
        var unmapped = h.Call().Payload.GetProperty("session").GetProperty("location");
        Require(unmapped.GetProperty("state").GetString() == "unknown" &&
            !unmapped.GetRawText().Contains("Future_Unmapped_Secret", StringComparison.Ordinal),
            "An unmapped location stays hidden instead of exposing the raw code.");

        File.AppendAllText(h.Log,
            Line("SetDriver: Local client node accepted 'ANVL_Arrow_101'") +
            Line("<Channel Disconnection> gamerules=\"SC_Default\" reason=\"Player requested disconnect\""));
        var disconnected = h.Call().Payload.GetProperty("session");
        var disconnectedServer = disconnected.GetProperty("server");
        Require(disconnectedServer.GetProperty("state").GetString() == "notConnected" &&
            !disconnectedServer.TryGetProperty("shard", out _) &&
            disconnected.GetProperty("location").GetProperty("state").GetString() == "unknown" &&
            disconnected.GetProperty("ship").GetProperty("state").GetString() == "unknown",
            "Leaving the server clears server, location and ship activity together.");

        File.AppendAllText(h.Log,
            Line("<Join PU> connected to shard[private shard value]"));
        var invalidServer = h.Call().Payload.GetProperty("session").GetProperty("server");
        Require(invalidServer.GetProperty("state").GetString() == "connected" &&
            !invalidServer.TryGetProperty("shard", out _),
            "Noncanonical shard text is never projected to Flutter.");

        File.AppendAllText(h.Log,
            Line("<Update Shard Id> New Shard Id: pub_use1b_12326004_040"));
        var usServer = h.Call().Payload.GetProperty("session").GetProperty("server");
        Require(usServer.GetProperty("state").GetString() == "connected" &&
            usServer.GetProperty("region").GetString() == "US" &&
            usServer.GetProperty("shard").GetString() == "pub_use1b_12326004_040",
            "The host publishes the complete canonical shard identifier.");

        File.WriteAllText(h.Log, Identity("Pilot_B"));
        h.Process = h.Process with { SessionId = "mismatched-process" };
        var mismatch = h.Call().Payload;
        Require(mismatch.GetProperty("match").GetString() == "mismatch" &&
            mismatch.GetProperty("session").GetProperty("state").GetString() == "unavailable" &&
            mismatch.GetProperty("session").GetProperty("location").GetProperty("state").GetString() == "unknown",
            "Session details remain hidden until the current Handle matches.");
        return Task.CompletedTask;
    }
    internal static Task OwnershipAndFailures()
    {
        using var h = new Harness();
        h.Call("find");
        var old = h.Request("stop");
        h.Current = (Owner with { Subject = "other" }, 2);
        Require(h.Runtime.DetectedHandle is null, "Account changes immediately invalidate identity.");
        Require(h.Call().Payload.GetProperty("selection").GetString() == "automatic", "New account has its own default choice.");
        Require(h.Runtime.Dispatch(old).Response.Error?.Code == "gameLog.accountChanged", "Stale commands rejected.");
        h.Current = (Owner, 3);
        Require(h.Call().Payload.GetProperty("match").GetString() == "match", "Original owner's settings preserved.");
        using (var second = h.Create())
            Require(second.Dispatch(h.Request()).Response.Error?.Code == "gameLog.storage", "Exclusive settings writer.");
        var bad = h.Request() with { Payload = JsonDocument.Parse("{\"schemaVersion\":1,\"schemaVersion\":1}").RootElement.Clone() };
        Require(h.Runtime.Dispatch(bad).Response.Status == "error", "Duplicate schema rejected.");
        using var cancel = new CancellationTokenSource(); cancel.Cancel();
        Require(h.Runtime.Dispatch(h.Request("stop"), cancel.Token).Response.Error?.Code == "gameLog.cancelled", "Cancelled mutation not saved.");
        Require(h.Call("select", Path.Combine(h.Root, "other.log")).Error?.Code == "gameLog.path", "Other files rejected.");
        Require(h.Call().Payload.GetProperty("path").GetString() == h.Log, "Failed selection preserves path.");
        var ownerHash = Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(
            JsonSerializer.SerializeToUtf8Bytes(new[] { Owner.Environment, Owner.Authority, Owner.Subject })));
        var settings = Path.Combine(h.Root, "game-log-local-v1", ownerHash + ".json");
        var original = File.ReadAllText(settings);
        Require(!original.Contains("playerGEID") && !original.Contains("Pilot_A"), "Store contains no log content or player identity.");
        File.WriteAllText(settings, "{}");
        Require(h.Call("retry").Status == "error", "Corrupt settings fail closed.");
        Require(File.ReadAllText(settings) == "{}", "Corruption is not silently replaced.");
        return Task.CompletedTask;
    }
    internal static Task LargeAndRotatedLogs()
    {
        using var h = new Harness();
        File.WriteAllText(h.Log, Identity("Pilot_A") + new string('x', 5 * 1024 * 1024) + "\n");
        Require(h.Call("find").Payload.GetProperty("handle").GetString() == "Pilot_A", "Bounded prefix finds startup identity in large log.");
        File.WriteAllText(h.Log, "new session without identity\n");
        h.Runtime.Sample();
        Require(h.Runtime.DetectedHandle is null, "Truncate/replace cannot retain stale identity.");
        File.WriteAllText(h.Log, Identity("Pilot_A", stamp: "2026-09-04T13:00:00Z"));
        Require(!h.Call().Payload.TryGetProperty("handle", out var future) || future.ValueKind == JsonValueKind.Null,
            "Future identity rejected.");
        File.WriteAllText(h.Log, Identity("Pilot_A") + new string('x', 18 * 1024 * 1024) + "\n" + Identity("Pilot_B"));
        var first = h.Call().Payload;
        Require(first.GetProperty("state").GetString() == "reading", "Large initial backlog is explicit, not skipped.");
        Require(h.Runtime.DetectedHandle is null, "No policy identity before complete initial scan.");
        var second = h.Call().Payload;
        Require(second.GetProperty("state").GetString() == "ambiguous", "Conflicting identity past the read budget is not lost.");
        return Task.CompletedTask;
    }

    internal static Task AutomaticVersions()
    {
        using var h = new Harness();
        var ptu = Path.Combine(h.Root, "StarCitizen", "PTU", "Game.log");
        Directory.CreateDirectory(Path.GetDirectoryName(ptu)!);
        File.WriteAllText(ptu, Identity("Pilot_B"));
        var liveProcess = h.Process;
        h.Process = new("notRunning");
        var first = h.Call().Payload;
        Require(first.GetProperty("channel").GetString() == "LIVE" && first.GetProperty("path").GetString() == h.Log &&
            first.GetProperty("state").GetString() == "notRunning", "First run auto-selects installed LIVE even before game starts.");
        BridgeEnvelope Configure(string channel) => h.Runtime.Dispatch(h.Request() with {
            Name = "gameLog.configure", Payload = JsonSerializer.SerializeToElement(new { schemaVersion = 1, channel })
        }).Response;
        BridgeEnvelope AddVersion(string path) => h.Runtime.Dispatch(h.Request() with {
            Name = "gameLog.addVersion", Payload = JsonSerializer.SerializeToElement(new { schemaVersion = 1, path })
        }).Response;
        BridgeEnvelope RemoveVersion(string channel) => h.Runtime.Dispatch(h.Request() with {
            Name = "gameLog.removeVersion", Payload = JsonSerializer.SerializeToElement(new { schemaVersion = 1, channel })
        }).Response;
        Require(Configure("PTU").Payload.GetProperty("path").GetString() == ptu, "Version switch finds PTU sibling.");
        var hotfix = Path.Combine(h.Root, "StarCitizen", "HOTFIX", "Game.log");
        Directory.CreateDirectory(Path.GetDirectoryName(hotfix)!);
        File.WriteAllText(hotfix, Identity("Pilot_C"));
        var custom = AddVersion(hotfix).Payload;
        Require(custom.GetProperty("channel").GetString() == "HOTFIX" &&
            custom.GetProperty("channels").EnumerateArray().Select(item => item.GetString()).Contains("HOTFIX") &&
            custom.GetProperty("path").GetString() == hotfix &&
            !custom.GetProperty("verifiedChannels").EnumerateArray().Any(),
            "A selected Game.log derives, remembers and locates an unconfirmed custom version.");
        Require(Configure("EPTU").Error?.Code == "gameLog.notFound",
            "A typed folder name cannot register an unselected version.");
        Configure("PTU");
        h.Runtime.Dispose(); h.Runtime = h.Create();
        Require(h.Call().Payload.GetProperty("channel").GetString() == "PTU", "Version choice survives restart.");
        Require(h.Call().Payload.GetProperty("channels").EnumerateArray()
            .Select(item => item.GetString()).Contains("HOTFIX"),
            "Custom version choices survive restart.");
        h.Process = liveProcess;
        Require(h.Call().Payload.GetProperty("state").GetString() == "otherVersion" && h.Runtime.DetectedHandle is null,
            "Running LIVE cannot supply PTU identity.");
        h.Process = liveProcess with { LogPath = ptu, SessionId = "ptu-process" };
        Require(h.Call().Payload.GetProperty("handle").GetString() == "Pilot_B", "PTU observes only the selected process log.");
        Require(!h.Call().Payload.GetProperty("verifiedChannels").EnumerateArray()
            .Select(item => item.GetString()).Contains("PTU"), "A mismatched Handle never confirms a version.");
        File.WriteAllText(ptu, Identity("Pilot_A"));
        h.Process = h.Process with { SessionId = "ptu-process-matching" };
        var confirmed = h.Call().Payload;
        Require(confirmed.GetProperty("verifiedChannels").EnumerateArray()
            .Select(item => item.GetString()).Contains("PTU") && h.Runtime.ConfirmedVersion == "PTU",
            "A refreshed running log with the verified Handle confirms the version for display.");
        h.Call("stop"); Configure("LIVE");
        Require(h.Call().Payload.GetProperty("state").GetString() == "stopped", "Changing version does not override stop.");
        h.Runtime.Dispose(); h.Runtime = h.Create(); h.Process = liveProcess;
        Require(h.Call().Payload.GetProperty("state").GetString() == "stopped", "Stopped automatic mode stays stopped after restart.");
        Require(h.Call("resume").Payload.GetProperty("match").GetString() == "match", "Resume keeps automatic selection.");
        Require(Configure("../PTU").Error?.Code == "gameLog.invalid", "Invalid channel rejected.");
        using (var cancel = new CancellationTokenSource())
        {
            cancel.Cancel();
            var request = h.Request() with { Name = "gameLog.configure",
                Payload = JsonSerializer.SerializeToElement(new { schemaVersion = 1, channel = "PTU" }) };
            Require(h.Runtime.Dispatch(request, cancel.Token).Response.Error?.Code == "gameLog.cancelled", "Cancelled version switch cannot save.");
        }
        h.Call("select", ptu);
        h.Runtime.Sample();
        Require(h.Call().Payload.GetProperty("selection").GetString() == "manual" &&
            h.Call().Payload.GetProperty("path").GetString() == ptu, "Automatic sampling never replaces an explicit manual path.");
        Configure("LIVE"); File.Delete(h.Log); h.Process = new("notRunning");
        var missing = h.Call("find").Payload;
        Require(missing.GetProperty("state").GetString() == "notFound" &&
            (!missing.TryGetProperty("path", out var missingPath) || missingPath.ValueKind == JsonValueKind.Null),
            "Missing LIVE never falls back to installed PTU.");
        File.WriteAllText(h.Log, Identity("Pilot_A"));
        h.Time.Now = h.Time.Now.AddSeconds(31); h.Runtime.Sample();
        Require(h.Call().Payload.GetProperty("path").GetString() == h.Log, "A log appearing later is found without another click.");
        var secondRoot = Path.Combine(h.Root, "SecondInstall", "StarCitizen");
        var secondLive = Path.Combine(secondRoot, "LIVE", "Game.log");
        Directory.CreateDirectory(Path.GetDirectoryName(secondLive)!); File.WriteAllText(secondLive, "");
        var locator = new GameLogLocator(() => [Path.Combine(h.Root, "StarCitizen"), secondRoot]);
        Require(locator.Find("LIVE", new("notRunning"), null).State == "multipleLogs", "Multiple installs require disambiguation.");
        Require(locator.Find("LIVE", liveProcess, null).Path == h.Log, "Current process disambiguates selected version.");
        Require(locator.Find("PTU", new("notRunning"), h.Log).Path == ptu, "Candidates and sibling hints are deduplicated.");
        Configure("HOTFIX");
        var removed = RemoveVersion("HOTFIX").Payload;
        Require(removed.GetProperty("channel").GetString() == "LIVE" &&
            !removed.GetProperty("channels").EnumerateArray().Select(item => item.GetString()).Contains("HOTFIX"),
            "Removing the active custom version hides it and returns to LIVE.");
        Require(RemoveVersion("LIVE").Error?.Code == "gameLog.requiredVersion",
            "The default LIVE version cannot be removed.");
        var removedPtu = RemoveVersion("PTU").Payload;
        Require(!removedPtu.GetProperty("channels").EnumerateArray().Select(item => item.GetString()).Contains("PTU"),
            "PTU can be hidden until its Game.log is selected again.");
        var fullVersionList = "LIVE|PTU";
        for (var index = 0; index < 16; index++)
            fullVersionList = GameLogLocator.AddChannel(fullVersionList, "CUSTOM" + index);
        var newestVersions = GameLogLocator.Channels(GameLogLocator.AddChannel(fullVersionList, "EPTU"));
        Require(newestVersions.Count == 16 && newestVersions.Contains("EPTU") &&
            newestVersions.Contains("LIVE") && newestVersions.Contains("PTU"),
            "A newly added version and both built-ins survive the bounded list.");

        // Read the previous schema without changing explicit paths or stopped choices.
        h.Call("select", ptu); h.Runtime.Dispose();
        var settingsFile = Directory.GetFiles(Path.Combine(h.Root, "game-log-local-v1"), "*.json").Single();
        var options = new JsonSerializerOptions(JsonSerializerDefaults.Web);
        var owner = Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(
            JsonSerializer.SerializeToUtf8Bytes(new[] { Owner.Environment, Owner.Authority, Owner.Subject }, options)));
        var settings = new { revision = 4L, path = ptu, enabled = false };
        var integrity = Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(
            JsonSerializer.SerializeToUtf8Bytes(new { owner, settings }, options)));
        var legacyBytes = JsonSerializer.Serialize(new { schemaVersion = 1, owner, settings, integrity }, options);
        File.WriteAllText(settingsFile, legacyBytes);
        h.Runtime = h.Create();
        var legacy = h.Call().Payload;
        Require(legacy.GetProperty("selection").GetString() == "manual" && legacy.GetProperty("channel").GetString() == "PTU" &&
            legacy.GetProperty("state").GetString() == "stopped", "Legacy manual PTU and stop choice preserved.");
        Require(File.ReadAllText(settingsFile) == legacyBytes, "Reading old settings does not rewrite them.");
        h.Call("resume");
        using var upgraded = JsonDocument.Parse(File.ReadAllText(settingsFile));
        Require(upgraded.RootElement.GetProperty("schemaVersion").GetInt32() == 5, "Explicit action safely upgrades settings schema.");

        h.Runtime.Dispose();
        var version4Settings = new {
            revision = 6L, path = ptu, enabled = false, channel = "PTU", selection = "automatic",
            channels = "LIVE|PTU", verifiedChannels = "PTU"
        };
        var version4Integrity = Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(
            JsonSerializer.SerializeToUtf8Bytes(new { owner, settings = version4Settings }, options)));
        var version4Bytes = JsonSerializer.Serialize(
            new { schemaVersion = 4, owner, settings = version4Settings, integrity = version4Integrity }, options);
        File.WriteAllText(settingsFile, version4Bytes);
        h.Runtime = h.Create();
        var version4 = h.Call().Payload;
        Require(version4.GetProperty("channel").GetString() == "PTU" &&
            version4.GetProperty("verifiedChannels").EnumerateArray()
                .Select(item => item.GetString()).Contains("PTU"),
            "Version-four paths, versions and confirmation state remain readable.");
        Require(File.ReadAllText(settingsFile) == version4Bytes, "Reading version-four settings does not rewrite them.");
        h.Call("resume");
        using var upgradedVersion4 = JsonDocument.Parse(File.ReadAllText(settingsFile));
        Require(upgradedVersion4.RootElement.GetProperty("schemaVersion").GetInt32() == 5,
            "The next explicit action safely upgrades version-four settings.");

        h.Runtime.Dispose();
        var version2Settings = new { revision = 8L, path = ptu, enabled = true, channel = "PTU", selection = "automatic" };
        var version2Integrity = Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(
            JsonSerializer.SerializeToUtf8Bytes(new { owner, settings = version2Settings }, options)));
        File.WriteAllText(settingsFile, JsonSerializer.Serialize(
            new { schemaVersion = 2, owner, settings = version2Settings, integrity = version2Integrity }, options));
        h.Runtime = h.Create();
        var version2 = h.Call().Payload;
        Require(version2.GetProperty("channel").GetString() == "PTU" &&
            version2.GetProperty("channels").EnumerateArray().Select(item => item.GetString()).SequenceEqual(["LIVE", "PTU"]),
            "Version-two settings remain readable with the built-in version list.");
        var eptu = Path.Combine(h.Root, "StarCitizen", "EPTU", "Game.log");
        Directory.CreateDirectory(Path.GetDirectoryName(eptu)!);
        File.WriteAllText(eptu, Identity("Pilot_A"));
        AddVersion(eptu);
        using var version5 = JsonDocument.Parse(File.ReadAllText(settingsFile));
        Require(version5.RootElement.GetProperty("schemaVersion").GetInt32() == 5 &&
            version5.RootElement.GetProperty("settings").GetProperty("channels").GetString()!.Contains("EPTU"),
            "Selecting a version log safely upgrades version-two settings.");
        return Task.CompletedTask;
    }
}
