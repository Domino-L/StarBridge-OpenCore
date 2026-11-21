using System.Text.RegularExpressions;
using StarBridge.Core.Events;

namespace StarBridge.Core.Parsing;

public sealed partial class RegexLogEventParser
{
    // Formats audited in CONTRACT-{RESEARCH-REPORT,LOG-SURVEY,LOG-EXAMPLES}-20261103.
    // Specific tags only, never HUD playback/fade/remove or localized whole-mission completion.
    private const string GuidText = @"[a-fA-F0-9]{8}(?:-[a-fA-F0-9]{4}){3}-[a-fA-F0-9]{12}";
    // Partial type field initialization order is unspecified: do not read the other file's Options field here.
    private static Regex ContractPattern(string pattern) => new(pattern,
        RegexOptions.Compiled | RegexOptions.IgnoreCase | RegexOptions.CultureInvariant, TimeSpan.FromMilliseconds(100));
    private static readonly Regex ContractMission = ContractPattern(@"\bmission(?:_id|Id)\s*:?\s*\[?(?<id>" + GuidText + @")\b");
    private static readonly Regex ContractObjective = ContractPattern(@"\bobjective(?:_id|Id)\s*:?\s*\[?(?<id>(?:(?:phase|pickup|dropoff)_)?" + GuidText + @")\b");
    private static readonly Regex ContractCode = ContractPattern(@"\bcontract\s*\[(?<code>[A-Za-z0-9_][A-Za-z0-9_-]{0,127})\](?:\[(?<definition>" + GuidText + @")\])?");
    private static readonly Regex ContractDefinition = ContractPattern(@"\bcontractDefinitionId\s*\[(?<id>" + GuidText + @")\]");
    private static readonly Regex ContractHud = ContractPattern(@"<SHUDEvent_OnNotification>\s+Added notification ""(?<kind>已接受合约|Contract Accepted|新的任务|New Objective|任务完成|Objective Complete|Objective Completed)[:：]\s*(?<text>[^""]*)""");
    private static readonly Regex ObjectiveState = ContractPattern(@"\bstate\s+MISSION_OBJECTIVE_STATE_(?<state>[A-Z]+)\b");
    private static readonly Regex MissionState = ContractPattern(@"\bmission_state\s+MISSION_STATE_(?<state>[A-Z]+)\b");
    private static readonly Regex EndState = ContractPattern(@"\bCompletionType\[(?<state>Complete|Fail|Deactivate|Abandon)\]");
    private static readonly Regex EndPlayer = ContractPattern(@"\bPlayer\[(?<player>[^\]\r\n]{1,64})\]");
    private static readonly Regex CreatedObjective = ContractPattern(@"\bcreated\s+1\b");
    // Audited PlayerJoined push: player_id is a GEID, not a display name.
    private static readonly Regex ContractPlayer = ContractPattern(@"\bplayer_id\s+(?<id>[0-9]+)\b");

    private static FleetEvent? TryParseContract(string line)
    {
        if (!line.Contains("<Mission", StringComparison.Ordinal) && !line.Contains("<EndMission>", StringComparison.Ordinal) &&
            !line.Contains("<Objective", StringComparison.Ordinal) && !line.Contains("<CLocalMissionPhaseMarker::CreateMarker>", StringComparison.Ordinal) &&
            !line.Contains("<SHUDEvent_OnNotification>", StringComparison.Ordinal) &&
            !line.Contains("<PlayerJoined>", StringComparison.Ordinal)) return null;
        if (ParseTimestamp(line) is not { } at) return null;
        var mission = ContractMission.Match(line);
        if (!mission.Success || !Guid.TryParse(mission.Groups["id"].Value, out var id) || id == Guid.Empty) return null;
        var objective = ContractObjective.Match(line);
        var objectiveId = objective.Success ? objective.Groups["id"].Value.ToLowerInvariant() : null;
        var data = new ContractLogEvidence(id.ToString(), objectiveId);
        FleetEvent Event(FleetEventType type, ContractLogEvidence evidence, string player = "LocalPlayer") =>
            new(type, player, Timestamp: at, SourceLine: line, Contract: evidence);
        if (line.Contains("<MissionShared>", StringComparison.Ordinal)) return Event(FleetEventType.ContractShared, data);
        if (line.Contains("<PlayerJoined>", StringComparison.Ordinal))
        {
            var player = ContractPlayer.Match(line);
            return player.Success ? Event(FleetEventType.ContractPlayerJoined,
                data with { PlayerId = player.Groups["id"].Value }) : null;
        }
        if (line.Contains("<CLocalMissionPhaseMarker::CreateMarker>", StringComparison.Ordinal))
        {
            var code = ContractCode.Match(line); var definition = ContractDefinition.Match(line);
            if (!code.Success) return null;
            return Event(FleetEventType.ContractDefined, data with { Contract = code.Groups["code"].Value,
                DefinitionId = definition.Success ? definition.Groups["id"].Value.ToLowerInvariant() :
                    code.Groups["definition"].Success ? code.Groups["definition"].Value.ToLowerInvariant() : null });
        }
        if (line.Contains("<MissionEnded>", StringComparison.Ordinal))
        {
            var state = MissionState.Match(line);
            return state.Success ? Event(FleetEventType.ContractEnded, data with { State = state.Groups["state"].Value.ToUpperInvariant() }) : null;
        }
        if (line.Contains("<EndMission>", StringComparison.Ordinal))
        {
            var state = EndState.Match(line); var player = EndPlayer.Match(line);
            if (!state.Success || !player.Success) return null; // Exclude Couldn't find active mission errors.
            var outcome = state.Groups["state"].Value.ToLowerInvariant() switch {
                "complete" => "COMPLETED", "fail" => "FAILED", "deactivate" => "WITHDRAWN", _ => "ABANDONED" };
            return Event(FleetEventType.ContractEnded, data with { State = outcome }, player.Groups["player"].Value);
        }
        if (line.Contains("<ObjectiveUpserted>", StringComparison.Ordinal) || line.Contains("<ObjectiveComplete>", StringComparison.Ordinal))
        {
            var state = ObjectiveState.Match(line);
            return objectiveId is not null && state.Success ? Event(FleetEventType.ContractObjective,
                data with { State = state.Groups["state"].Value.ToUpperInvariant(), Created = CreatedObjective.IsMatch(line),
                    ObjectiveUpserted = line.Contains("<ObjectiveUpserted>", StringComparison.Ordinal) }) : null;
        }
        var hud = ContractHud.Match(line);
        if (!hud.Success) return null;
        var kind = hud.Groups["kind"].Value;
        if (kind is "已接受合约" || kind.Equals("Contract Accepted", StringComparison.OrdinalIgnoreCase))
            // Presentation only: retain the acceptance HUD name; it never identifies a template.
            return objectiveId is null ? Event(FleetEventType.ContractAccepted, data with { Text = hud.Groups["text"].Value.Trim().TrimEnd(':', '：', ' ') }) : null;
        if (objectiveId is null) return null;
        var completed = kind is "任务完成" || kind.StartsWith("Objective Complete", StringComparison.OrdinalIgnoreCase);
        return Event(FleetEventType.ContractObjective, data with { Created = !completed,
            State = completed ? "COMPLETED" : "INPROGRESS", Text = hud.Groups["text"].Value.Trim().TrimEnd(':', '：', ' ').TrimEnd(':', ' ') });
    }
}
