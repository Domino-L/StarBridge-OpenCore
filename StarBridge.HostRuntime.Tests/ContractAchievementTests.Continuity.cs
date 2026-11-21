using System.Text;
using StarBridge.Core.Events;
using StarBridge.HostRuntime.Presence;

internal static partial class ContractAchievementTests
{
    // Existing real-format death/respawn excerpts from Core.Tests: medical response
    // (July 15) and non-safe-zone corpse recovery (July 24). Times and all identifiers
    // are synthetic so these sequences fit the contract timeline without personal data.
    private static string DeathSequence(bool corpse) => string.Join("\n", corpse ? new[] {
        "<2026-10-18T05:09:00Z> [Notice] <Adding non kept item [CSCActorCorpseUtils::PopulateItemPortForItemRecoveryEntitlement]> Item 'body_01_noMagicPocket_700 - Class(body_01_noMagicPocket) - Context(Streamable Runtime-spawned) - Socpak()', Recorded data is: Port Name 'Body_ItemPort', Class GUID: 'dbaa8a7d-755f-4104-8b24-7b58fd1e76f6', KeptId: '700' [Team_CoreGameplayFeatures][Unknown]",
        "<2026-10-18T05:09:10Z> [Notice] <Recv Unbind Batch Add Player> Unbind Batch Add sent for player in batch 10 playerGEID=12345 sessionId=\"fixture\" entityId=12345, className=\"Player\", classCrc=2961494058, parentEntityId=701",
        "<2026-10-18T05:09:11Z> [Notice] <Recv Bind Batch End Player> Bind Batch End enabled player in batch 11 playerGEID=12345 sessionId=\"fixture\" entityId=12345, className=\"Player\", classCrc=2961494058, parentEntityId=702",
        "<2026-10-18T05:09:12Z> [Notice] <Update Inventory Location> Player [Pilot_A] is changing location. Landing [0] -> [1]. Location [0] -> [2]. Pending [0]",
        "<2026-10-18T05:09:13Z> [CSessionManager::OnClientSpawned] Spawned!"
    } : new[] {
        "<2026-10-18T05:09:00Z> [Notice] <SHUDEvent_OnNotification> Added notification \"请等待，本地急救人员正在赶来的路上。: \" [4] to queue.",
        "<2026-10-18T05:09:10Z> [Notice] <Recv Unbind Batch Add Player> Unbind Batch Add sent for player playerGEID=12345 entityId=12345, className=\"Player\", parentEntityId=701",
        "<2026-10-18T05:09:11Z> [Notice] <Recv Bind Batch Add Player> Bind Batch Add received for player playerGEID=12345 entityId=12345, className=\"Player\", parentEntityId=702",
        "<2026-10-18T05:09:12Z> [Notice] <Initializing Haptic> Initializing haptic component of local player",
        "<2026-10-18T05:09:12.500Z> [Notice] <AttachmentReceived> Player[Pilot_A] Attachment[body_01, body_01, 703] Status[persistent] Port[Body_ItemPort]",
        "<2026-10-18T05:09:13Z> [CSessionManager::OnClientSpawned] Spawned!"
    }) + "\n";

    private static string ContractPrefix() => string.Join("\n", Lines().Where(l => l.Source == "L05").Select(l => l.Line)) + "\n";
    private static string ContractEnding() => string.Join("\n", Lines().Where(l => l.Source != "L05").Select(l => l.Line)) + "\n";
    private static void Reenter(ReaderHarness h)
    {
        h.ProcessState = "running"; h.Session = "synthetic-reentry";
        h.StartedAt = DateTimeOffset.Parse("2026-10-18T05:12:00Z");
        File.WriteAllText(h.Log, ReaderHarness.Header("2026-10-18T05:12:01Z") + ContractEnding(), new UTF8Encoding(false));
        h.Game.Sample();
    }

    private static Task UnreadDeathExit(bool corpse)
    {
        const string secondMission = "8db7ff56-42a9-479c-9597-1eb9d7da5091";
        using var h = new ReaderHarness(); h.Select();
        h.Append(ContractPrefix() + ContractPrefix().Replace(Mission, secondMission));
        File.AppendAllText(h.Log, DeathSequence(corpse), new UTF8Encoding(false));
        h.ProcessState = "notRunning"; h.Game.Sample();
        Require(Read(h.Store).Runs.Length == 2 && Read(h.Store).Runs.All(r => r.Deaths == 0),
            "exit never consumes or parses unread death bytes for either in-flight contract");
        File.Move(h.Log, h.Log + ".previous"); Reenter(h);
        h.Append(ContractEnding().Replace(Mission, secondMission));
        var o = Pending(h.Store);
        Require(!o.CompleteRun && o.Owner && o.Deaths == 0 &&
            !Cloud.Awards(o).Contains("contract-tsg-deathless"), "unread real-format death creates a gap before exit/reentry");
        Require(Read(h.Store).Runs.All(r => r.Pending is { CompleteRun: false }), "read gap invalidates all in-flight contracts");
        return Task.CompletedTask;
    }

    private static Task ConsumedDeathExit(bool corpse)
    {
        using var h = new ReaderHarness(); h.Select(); h.Append(ContractPrefix());
        h.Append(DeathSequence(corpse));
        Require(Read(h.Store).Runs.Single().Deaths == 1, "normal reader counts one death and its respawn once");
        if (corpse) h.Append("<2026-10-18T05:10:02Z> [Notice] <SystemQuit> CSystem::Quit\n");
        h.ProcessState = "notRunning"; h.Game.Sample();
        File.Move(h.Log, h.Log + ".previous"); Reenter(h);
        var o = Pending(h.Store);
        Require(o.CompleteRun && o.Owner && o.Deaths == 1, "normal EOF then exit/reentry retains completeRun and deaths");
        return Task.CompletedTask;
    }

    private static Task SameLengthReplacementExit(bool corpse)
    {
        const string secondMission = "8db7ff56-42a9-479c-9597-1eb9d7da5091";
        using var h = new ReaderHarness(); h.Select();
        h.Append(ContractPrefix() + ContractPrefix().Replace(Mission, secondMission));
        var consumedLength = new FileInfo(h.Log).Length;
        File.AppendAllText(h.Log, DeathSequence(corpse), new UTF8Encoding(false));
        File.Move(h.Log, h.Log + ".previous");
        // Keep the old file alive so the filesystem cannot reuse its file ID.
        // The replacement has exactly the consumed byte length, with no death evidence.
        using (var replacement = File.Create(h.Log)) replacement.SetLength(consumedLength);
        h.ProcessState = "notRunning"; h.Game.Sample();
        Require(Read(h.Store).Runs.Length == 2 && Read(h.Store).Runs.All(r => r.Deaths == 0),
            "exit must not read the old death tail or the replacement body");
        Reenter(h); h.Append(ContractEnding().Replace(Mission, secondMission));
        Require(Read(h.Store).Runs.All(r => r.Pending is { CompleteRun: false, Deaths: 0 }),
            "same-length replacement before exit invalidates every in-flight contract after reentry");
        Require(!Cloud.Awards(Pending(h.Store)).Contains("contract-tsg-deathless"),
            "unread death hidden by same-length replacement cannot earn deathless");
        return Task.CompletedTask;
    }

    private static Task MetadataOnlyExit()
    {
        using var h = new ReaderHarness(); h.Select(); h.Append(ContractPrefix());
        // Windows permits zero-data-access metadata opens while body reads are denied.
        using (var blocked = new FileStream(h.Log, FileMode.Open, FileAccess.ReadWrite, FileShare.None))
        {
            h.ProcessState = "notRunning"; h.Game.Sample();
        }
        File.Move(h.Log, h.Log + ".previous"); Reenter(h);
        Require(Pending(h.Store).CompleteRun && Pending(h.Store).Deaths == 0,
            "EOF identity and length can be confirmed without opening the log for body reads");
        return Task.CompletedTask;
    }

    private static Task BoundaryFileIdentity()
    {
        foreach (var strict in new[] { false, true })
        foreach (var switchPath in new[] { false, true })
        foreach (var replaced in new[] { false, true })
        {
            using var h = new ReaderHarness();
            var session = new GameLogSessionTracker();
            session.ContractEvidence += (_, _) => { };
            var reader = new GameLogIdentityReader(session, strictLocalEvidence: strict);
            var ended = new List<bool>();
            reader.ContractSourceEnded += (_, complete, _) => ended.Add(complete);
            reader.ReadCurrent(h.Log, new("running", h.Log, h.StartedAt, h.Session), Ended);
            if (replaced)
            {
                var length = new FileInfo(h.Log).Length;
                File.Move(h.Log, h.Log + ".previous");
                using var replacement = File.Create(h.Log); replacement.SetLength(length);
            }
            if (switchPath)
            {
                var other = Path.Combine(h.DirectoryRoot, "PTU", "Game.log");
                Directory.CreateDirectory(Path.GetDirectoryName(other)!);
                File.WriteAllText(other, ReaderHarness.Header("2026-10-18T03:00:02Z"), new UTF8Encoding(false));
                reader.ReadCurrent(other, new("running", other, h.StartedAt, "next-session"), Ended);
            }
            else reader.ReadCurrent(h.Log, new("notRunning"), Ended);
            Require(ended.SequenceEqual(new[] { !replaced }),
                $"old identity and length checked together: strict={strict}, switchPath={switchPath}, replaced={replaced}");
            // Every read and metadata query has closed its handle by the return boundary.
            using var exclusive = new FileStream(h.Log, FileMode.Open, FileAccess.ReadWrite, FileShare.None);
            reader.Reset();
        }
        return Task.CompletedTask;
    }

    private static Task EndOfFileExit()
    {
        using var h = new ReaderHarness(); h.Select(); h.Append(ContractPrefix());
        h.ProcessState = "notRunning"; h.Game.Sample();
        File.Move(h.Log, h.Log + ".previous"); Reenter(h);
        Require(Pending(h.Store).CompleteRun && Pending(h.Store).Deaths == 0,
            "fully read EOF then normal exit/reentry keeps the same complete run");
        return Task.CompletedTask;
    }

    private static Task SourceBoundaryGap(string boundary)
    {
        using var h = new ReaderHarness(); h.Select(); h.Append(ContractPrefix());
        File.AppendAllText(h.Log, DeathSequence(false), new UTF8Encoding(false));
        switch (boundary)
        {
            case "rotation": File.Move(h.Log, h.Log + ".previous"); break;
            case "truncation": File.WriteAllText(h.Log, "", new UTF8Encoding(false)); h.Game.Sample(); break;
            case "deletion": File.Delete(h.Log); h.ProcessState = "notRunning"; h.Game.Sample(); break;
        }
        Reenter(h);
        Require(!Pending(h.Store).CompleteRun && Pending(h.Store).Deaths == 0,
            boundary + " cannot certify an unread old source or read its contents");
        return Task.CompletedTask;
    }

    private static Task PartialLineExit()
    {
        using var h = new ReaderHarness(); h.Select(); h.Append(ContractPrefix());
        h.Append("<2026-10-18T05:10:01Z> unfinished");
        h.ProcessState = "notRunning"; h.Game.Sample();
        File.Move(h.Log, h.Log + ".previous"); Reenter(h);
        Require(!Pending(h.Store).CompleteRun, "byte EOF with an incomplete physical line is still a gap");
        return Task.CompletedTask;
    }

    private static Task NormalReaderSessionTransitions()
    {
        using var h = new ReaderHarness();
        var session = new GameLogSessionTracker(); var reader = new GameLogIdentityReader(session);
        var seen = new List<FleetEvent>(); session.ContractEvidence += (e, _) => seen.Add(e);
        var process = new GameProcessSession("running", h.Log, h.StartedAt, h.Session);
        reader.ReadCurrent(h.Log, process, Ended);
        File.AppendAllText(h.Log,
            "<2026-10-18T05:08:00Z> <Channel Disconnection> gamerules=\"SC_Default\" reason=\"Player requested disconnect\"\n" +
            DeathSequence(false), new UTF8Encoding(false));
        reader.ReadCurrent(h.Log, process, Ended);
        Require(seen.Count == 0, "disconnected death is rejected by the normal session tracker");
        File.AppendAllText(h.Log, ReaderHarness.Header("2026-10-18T05:08:00Z") + DeathSequence(true), new UTF8Encoding(false));
        reader.ReadCurrent(h.Log, process, Ended);
        Require(seen.Count(e => e.Type == FleetEventType.PlayerDied) == 1 &&
            seen.Count(e => e.Type == FleetEventType.PlayerRespawned) == 1, "rejoined normal path counts corpse death and respawn");
        reader.Reset();
        return Task.CompletedTask;
    }
}
