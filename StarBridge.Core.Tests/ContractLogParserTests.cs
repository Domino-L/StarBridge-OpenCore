using StarBridge.Core.Events;
using StarBridge.Core.Parsing;

namespace StarBridge.Core.Tests;

internal static class ContractLogParserTests
{
    private const string M = "8db7ff56-42a9-479c-9597-1eb9d7da5090";
    private const string O = "a61907c8-f55b-a942-8123-abf36f3af484";
    private const string Stamp = "<2026-10-18T04:17:34.311Z> [Notice] ";
    private static string Hud(string text, string objective = "") => Stamp +
        $"<SHUDEvent_OnNotification> Added notification \"{text}: \" [58] to queue. New queue size: 1, MissionId: [{M}], ObjectiveId: [{objective}] [Team_CoreGameplayFeatures][Missions][Comms]";
    private static void Require(bool condition, string message) { if (!condition) throw new Exception(message); }
    internal static void RunAll()
    {
        // Sanitized excerpts: RESEARCH sections 3/4/5/9, SURVEY and EXAMPLES section 1.
        var parser = new RegexLogEventParser(); var cases = 0;
        foreach (var text in new[] { "已接受合约：需要战术打击群", "Contract Accepted: Tactical Strike Group" })
        {
            var e = parser.TryParse(Hud(text));
            Require(e?.Type == FleetEventType.ContractAccepted && e.Contract?.MissionId == M &&
                e.Contract.Text == (text.StartsWith("Contract", StringComparison.Ordinal) ? "Tactical Strike Group" : "需要战术打击群") && e.Timestamp == DateTimeOffset.Parse("2026-10-18T04:17:34.311Z"), $"local acceptance and log clock ({text}; {e?.Type}; {e?.Contract?.MissionId}; {e?.Timestamp})");
        }
        cases++;
        var shared = parser.TryParse(Stamp + $"<MissionShared> Received share push message: ownerId[X] - missionId[{M}] [Team_GameServices][Missions]");
        Require(shared?.Type == FleetEventType.ContractShared && shared.Contract?.MissionId == M, "real shared MissionId"); cases++;
        var joinedLine = Stamp + $"<PlayerJoined> Received PlayerJoined push message for: mission_id {M} - player_id 67890 [Team_GameServices][Missions]";
        var joined = parser.TryParse(joinedLine);
        Require(joined?.Type == FleetEventType.ContractPlayerJoined && joined.Contract?.MissionId == M &&
            joined.Contract.PlayerId == "67890" && joined.Timestamp == DateTimeOffset.Parse("2026-10-18T04:17:34.311Z"),
            "PlayerJoined retains mission, numeric GEID and log timestamp"); cases++;
        Require(parser.TryParse(joinedLine.Replace("67890", "invalid")) is null &&
            parser.TryParse(joinedLine.Replace(M, Guid.Empty.ToString())) is null &&
            parser.TryParse(joinedLine[Stamp.Length..]) is null &&
            parser.TryParse(joinedLine.Replace("<PlayerJoined>", "<PlayerLeft>")) is null,
            "invalid IDs, missing timestamp and PlayerLeft do not create joins"); cases++;
        var marker = Stamp + $"<CLocalMissionPhaseMarker::CreateMarker> Creating objective marker: missionId [{M}], generator name [InterSec_StationAssault], contract [InterSec_Nyx_TSG_FullStrikeOnStation], contractDefinitionId[24ac3c24-ed16-43f5-bb1c-626f0261fcb5], objectiveId [{O}], markerEntityId [3194], zoneHostId [X]";
        var defined = parser.TryParse(marker);
        Require(defined?.Type == FleetEventType.ContractDefined && defined.Contract?.DefinitionId == "24ac3c24-ed16-43f5-bb1c-626f0261fcb5" &&
            defined.Contract.Contract == "InterSec_Nyx_TSG_FullStrikeOnStation", "exact template identity"); cases++;
        foreach (var code in new[] { "a-b_C9", new string('x', 128) })
            Require(parser.TryParse(marker.Replace("InterSec_Nyx_TSG_FullStrikeOnStation", code))?.Contract?.Contract == code,
                "Java-compatible contract code survives parsing");
        foreach (var code in new[] { "-bad", "a.b", new string('x', 129), new string('x', 160) })
            Require(parser.TryParse(marker.Replace("InterSec_Nyx_TSG_FullStrikeOnStation", code)) is null,
                "invalid template ignored without guessing");
        cases++;
        foreach (var tag in new[] { "ObjectiveUpserted", "ObjectiveComplete" })
        foreach (var state in new[] { "COMPLETED", "WITHDRAWN", "INPROGRESS" })
        {
            var e = parser.TryParse(Stamp + $"<{tag}> Received {tag} push message for: mission_id {M} - objective_id phase_{O} - state MISSION_OBJECTIVE_STATE_{state} - created 1 - flags=Hidden|ShowInLog|");
            Require(e?.Type == FleetEventType.ContractObjective && e.Contract?.State == state && e.Contract.Created &&
                e.Contract.ObjectiveId == "phase_" + O, "objective states and prefixed IDs are not whole-mission outcomes");
        }
        cases++;
        foreach (var state in new[] { "COMPLETED", "FAILED", "WITHDRAWN", "UNKNOWN" })
        {
            var e = parser.TryParse(Stamp + $"<MissionEnded> Received MissionEnded push message for: mission_id {M} - mission_state MISSION_STATE_{state} [Team_GameServices][Missions]");
            Require(e?.Type == FleetEventType.ContractEnded && e.Contract?.State == state, "language-independent mission ending");
        }
        cases++;
        foreach (var (type, state) in new[] { ("Complete", "COMPLETED"), ("Fail", "FAILED"), ("Deactivate", "WITHDRAWN"), ("Abandon", "ABANDONED") })
        {
            var e = parser.TryParse(Stamp + $"<EndMission> Ending mission for player. MissionId[{M}] Player[Pilot_A] PlayerId[X] CompletionType[{type}] Reason[Mission Ended]");
            Require(e?.Type == FleetEventType.ContractEnded && e.Player == "Pilot_A" && e.Contract?.State == state, "explicit participant and result");
        }
        Require(parser.TryParse(Stamp + $"<EndMission> Couldn't find active mission for player. MissionId[{M}]") is null, "error variant"); cases++;
        foreach (var text in new[] { "新的任务：前往 QV 采矿站", "New Objective: Go to QV Mining Station", "任务完成：前往 QV 采矿站", "Objective Complete: Go to QV Mining Station" })
            Require(parser.TryParse(Hud(text, O))?.Type == FleetEventType.ContractObjective, "HUD phase stays a phase");
        Require(parser.TryParse(Hud("合约完成：需要战术打击群")) is null, "localized whole-mission HUD alone cannot complete"); cases++;
        Require(parser.TryParse(Hud("已接受合约：需要战术打击群").Replace(M, Guid.Empty.ToString())) is null &&
            parser.TryParse(Hud("已接受合约：需要战术打击群").Replace("Added notification", "Next notification")) is null &&
            parser.TryParse(Hud("已接受合约：需要战术打击群")[Stamp.Length..]) is null, "zero IDs, playback and missing clock rejected"); cases++;
        Require(parser.TryParse(Stamp + "PLAYER_LOCATION player=Pilot_A location=Stanton1_Lorville")?.Type == FleetEventType.PlayerLocationChanged &&
            parser.TryParse(Stamp + "<SHUDEvent_OnNotification> Added notification \"Joined channel 'AEGS_Avenger_Titan : Pilot_A'\"")?.Type == FleetEventType.PlayerEnteredShip,
            "existing specific location and HUD rules preserved"); cases++;
        // Contract HUD rules must leave the normal parser's local death state intact.
        // Real medical-response format, with synthetic identity and timeline.
        parser.TryParse(Stamp + "nickname=\"Pilot_A\" playerGEID=12345");
        parser.TryParse(Hud("Contract Accepted: Tactical Strike Group"));
        parser.TryParse(Stamp + "<SHUDEvent_OnNotification> Added notification \"请等待，本地急救人员正在赶来的路上。: \" [4] to queue.");
        var death = parser.TryParse("<2026-10-18T04:17:35.311Z> [Notice] <Recv Unbind Batch Add Player> Unbind Batch Add sent for player playerGEID=12345 entityId=12345, className=\"Player\", parentEntityId=701");
        parser.TryParse("<2026-10-18T04:17:36.311Z> [Notice] <Recv Bind Batch Add Player> Bind Batch Add received for player playerGEID=12345 entityId=12345, className=\"Player\", parentEntityId=702");
        parser.TryParse("<2026-10-18T04:17:36.500Z> [Notice] <Initializing Haptic> Initializing haptic component of local player");
        var respawn = parser.TryParse("<2026-10-18T04:17:37.311Z> [CSessionManager::OnClientSpawned] Spawned!");
        Require(death?.Type == FleetEventType.PlayerDied && respawn?.Type == FleetEventType.PlayerRespawned,
            "contract acceptance preserves normal death and respawn parsing"); cases++;
        Console.WriteLine($"SUMMARY CONTRACT CORE passed={cases} failed=0");
    }
}
