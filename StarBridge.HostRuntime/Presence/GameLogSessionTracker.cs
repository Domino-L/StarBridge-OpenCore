using System.Reflection;
using System.Text.RegularExpressions;
using StarBridge.Core.Events;
using StarBridge.Core.Parsing;
using StarBridge.Core.Ships;
using StarBridge.Core.State;

namespace StarBridge.HostRuntime.Presence;

public sealed record GameLogServerSnapshot(
    string State,
    string? Region = null,
    string? Shard = null);

public sealed record GameLogShipSnapshot(
    string State,
    string? Key = null,
    string? EnglishName = null,
    string? ChineseName = null,
    string? TraditionalChineseName = null);

public sealed record GameLogLocationSnapshot(
    string State,
    string? EnglishName = null,
    string? ChineseName = null,
    [property: System.Text.Json.Serialization.JsonIgnore] bool CanSynchronize = true);

public sealed record GameLogSessionSnapshot(
    GameLogServerSnapshot Server,
    GameLogLocationSnapshot Location,
    GameLogShipSnapshot Ship)
{
    public static GameLogSessionSnapshot Empty { get; } =
        new(new("unknown"), new("unknown"), new("unknown"));
}

/// <summary>
/// Converts bounded, current-session Game.log lines into a small local snapshot.
/// Raw lines, unvalidated shard text, player IDs and vehicle instance IDs never
/// leave this module. A bounded canonical pub_* shard may be projected for display.
/// </summary>
internal sealed class GameLogSessionTracker(Support.GameLogJournalBatch? journal = null)
{
    private static readonly RegexOptions Options =
        RegexOptions.Compiled | RegexOptions.IgnoreCase | RegexOptions.CultureInvariant;
    private static readonly Regex JoinPuShard = new(
        @"<Join PU>.*?\bshard\[(?<shard>[^\]]+)\]",
        Options,
        TimeSpan.FromMilliseconds(100));
    private static readonly Regex UpdateShardId = new(
        @"<Update Shard Id>\s+New Shard Id:\s*(?<shard>[A-Z0-9_-]+)",
        Options,
        TimeSpan.FromMilliseconds(100));
    private static readonly Regex PublicShard = new(
        @"^pub_[a-z0-9]+(?:[_-][a-z0-9]+){2,15}$",
        Options,
        TimeSpan.FromMilliseconds(100));
    private static readonly Regex Disconnect = new(
        @"<Channel(?: Process)? (?:Disconnection|Disconnected)>(?=[^\r\n]*gamerules=""SC_Default"")(?=[^\r\n]*(?:reason=""[^""]*(?:Player requested disconnect|Remote Disconnect)[^""]*""|cause=30016))",
        Options,
        TimeSpan.FromMilliseconds(100));
    private static readonly Regex ReturnedToFrontend = new(
        @"<Change Server End>.*?IsPersistedInGameMode\[0\]",
        Options,
        TimeSpan.FromMilliseconds(100));
    private static readonly Lazy<ShipNameIndex> ShipNames = new(LoadShipNames);
    private static readonly Lazy<GameLogLocationNameIndex> LocationNames = new(GameLogLocationNameIndex.Load);

    private RegexLogEventParser _parser = new();
    private FleetState _fleet = new();
    private string? _localHandle;
    private string? _serverShard;
    private string _serverState = "unknown";
    private string? _serverRegion;
    private string? _publishedServerShard;

    internal static bool MightContainEvidence(string line) =>
        line.Contains("<Join PU>", StringComparison.OrdinalIgnoreCase) ||
        line.Contains("<Update Shard Id>", StringComparison.OrdinalIgnoreCase) ||
        line.Contains("<Channel Disconnection>", StringComparison.OrdinalIgnoreCase) ||
        line.Contains("<Channel Process Disconnection>", StringComparison.OrdinalIgnoreCase) ||
        line.Contains("<Channel Disconnected>", StringComparison.OrdinalIgnoreCase) ||
        line.Contains("<Change Server End>", StringComparison.OrdinalIgnoreCase) ||
        line.Contains("<RequestLocationInventory>", StringComparison.OrdinalIgnoreCase) ||
        line.Contains("<Player Selected Quantum Target - Local>", StringComparison.OrdinalIgnoreCase) ||
        line.Contains("<Calculate Route>", StringComparison.OrdinalIgnoreCase) ||
        line.Contains("<Quantum Drive Arrived - Arrived at Final Destination>", StringComparison.OrdinalIgnoreCase) ||
        line.Contains("PLAYER_LOCATION", StringComparison.OrdinalIgnoreCase) ||
        line.Contains("<SHUDEvent_OnNotification>", StringComparison.OrdinalIgnoreCase) ||
        line.Contains("SetDriver:", StringComparison.OrdinalIgnoreCase) ||
        line.Contains("ClearDriver:", StringComparison.OrdinalIgnoreCase) ||
        line.Contains("control token", StringComparison.OrdinalIgnoreCase);

    internal void Reset()
    {
        _parser = new();
        _fleet = new();
        _localHandle = null;
        _serverShard = null;
        _serverState = "unknown";
        _serverRegion = null;
        _publishedServerShard = null;
    }

    internal void Observe(string line)
    {
        if (Disconnect.IsMatch(line) ||
            (_serverState == "connected" && ReturnedToFrontend.IsMatch(line)))
        {
            var wasConnected = _serverState == "connected";
            _serverShard = null;
            _serverState = "notConnected";
            _serverRegion = null;
            _publishedServerShard = null;
            _fleet.Clear();
            if (wasConnected) journal?.Add(new(Support.LocalGameEventCategories.Server,
                "ServerLeft", "已离开游戏服务器", "服务器标识已清空"));
            return;
        }

        var shard = ExtractShard(line);
        if (shard is not null)
        {
            var changed = !string.Equals(_serverShard, shard, StringComparison.OrdinalIgnoreCase);
            if (_serverShard is not null &&
                !_serverShard.Equals(shard, StringComparison.OrdinalIgnoreCase))
            {
                _fleet.Clear();
            }
            _serverShard = shard;
            _serverState = "connected";
            _serverRegion = ResolveRegion(shard);
            _publishedServerShard = ResolvePublishedShard(shard);
            if (changed) journal?.Add(new(Support.LocalGameEventCategories.Server,
                "ServerJoined", "已连接游戏服务器",
                _publishedServerShard is null ? "服务器已连接" : $"{_serverRegion} / {_publishedServerShard}"));
        }

        var gameEvent = _parser.TryParse(line);
        if (gameEvent is null)
        {
            return;
        }

        if (gameEvent.Type == FleetEventType.PlayerOnline)
        {
            if (_localHandle is not null &&
                !_localHandle.Equals(gameEvent.Player, StringComparison.OrdinalIgnoreCase))
            {
                _fleet.Clear();
            }
            _localHandle = gameEvent.Player;
            Record(gameEvent);
            return;
        }

        // Local history uses the same parsed event, including one-shot life evidence.
        // It does not widen the existing public snapshot/ship-owner policy.
        if (_localHandle is not null &&
            (gameEvent.Player.Equals("LocalPlayer", StringComparison.OrdinalIgnoreCase) ||
             gameEvent.Player.Equals(_localHandle, StringComparison.OrdinalIgnoreCase)))
            Record(gameEvent);

        if (_localHandle is null ||
            gameEvent.Type is not (
                FleetEventType.PlayerEnteredShip or
                FleetEventType.PlayerExitedShip or
                FleetEventType.PlayerControllingShip or
                FleetEventType.PlayerShipControlSignal or
                FleetEventType.PlayerStoppedDrivingShip or
                FleetEventType.PlayerLocationChanged or
                FleetEventType.PlayerNavigationTargetChanged))
        {
            return;
        }

        if (gameEvent.ShipOwner is not null &&
            !gameEvent.ShipOwner.Equals(_localHandle, StringComparison.OrdinalIgnoreCase))
        {
            return;
        }

        if (!gameEvent.Player.Equals("LocalPlayer", StringComparison.OrdinalIgnoreCase) &&
            !gameEvent.Player.Equals(_localHandle, StringComparison.OrdinalIgnoreCase))
        {
            return;
        }

        _fleet.Apply(gameEvent with { Player = "LocalPlayer" });
    }


    private void Record(FleetEvent e)
    {
        if (journal is null) return;
        var local = e with { Player = _localHandle ?? e.Player };
        var player = _fleet.Players.FirstOrDefault(p => p.Name == "LocalPlayer");
        // Snapshot application follows this callback. The pending navigation target
        // is the arrival target here; do not reuse a stale prior arrival target.
        var title = Support.LocalGameEventPresentation.Title(local, ShipLabel, LocationLabel,
            player?.NavigationTarget is { } target && target != "None" ? target : null);
        if (title.Length != 0) journal.Add(new(Support.LocalGameEventJournal.Classify(local.Type),
            local.Type.ToString(), title, Support.LocalGameEventPresentation.Detail(local)));
    }

    private static string ShipLabel(string? raw)
    {
        if (string.IsNullOrWhiteSpace(raw) || raw is "Unknown" or "None") return "未知飞船";
        var name = ShipNames.Value.Find(raw);
        return name?.ChineseName ?? name?.EnglishName ?? raw;
    }
    private static string LocationLabel(string? raw)
    {
        if (string.IsNullOrWhiteSpace(raw) || raw is "Unknown" or "None") return "未知";
        var name = LocationNames.Value.Find(raw);
        return name?.ChineseName ?? name?.EnglishName ?? raw;
    }

    internal GameLogSessionSnapshot Snapshot(DateTimeOffset now)
    {
        _fleet.RefreshShipInferences(now);
        var player = _fleet.Players.FirstOrDefault(candidate =>
            candidate.Name.Equals("LocalPlayer", StringComparison.OrdinalIgnoreCase));
        var ship = player is null ||
                   player.Ship.Equals("Unknown", StringComparison.OrdinalIgnoreCase) ||
                   player.ShipConfidence.Equals("None", StringComparison.OrdinalIgnoreCase)
            ? new GameLogShipSnapshot("unknown")
            : PresentShip(player.Ship, player.ShipConfidence);
        var location = player is null ||
                       player.Location.Equals("Unknown", StringComparison.OrdinalIgnoreCase) ||
                       player.LocationConfidence.Equals("None", StringComparison.OrdinalIgnoreCase)
            ? new GameLogLocationSnapshot("unknown")
            : PresentLocation(player.Location, player.LocationConfidence);
        return new(
            new(_serverState, _serverRegion, _publishedServerShard),
            location,
            ship);
    }

    private static string? ExtractShard(string line)
    {
        var match = JoinPuShard.Match(line);
        if (!match.Success)
        {
            match = UpdateShardId.Match(line);
        }
        if (!match.Success)
        {
            return null;
        }
        var value = match.Groups["shard"].Value.Trim();
        return value.Length is > 0 and <= 256 && !value.Any(char.IsControl)
            ? value
            : null;
    }

    private static string? ResolveRegion(string shard)
    {
        var value = shard.ToLowerInvariant();
        if (ContainsCloudRegion(value, "ap-southeast-2") ||
            ContainsCloudRegion(value, "ap-southeast-4") ||
            ContainsCloudRegion(value, "ap-southeast-6") ||
            ContainsTokenStartingWith(value, "apse2") ||
            ContainsTokenStartingWith(value, "apse4") ||
            ContainsTokenStartingWith(value, "apse6") ||
            value.Contains("australia", StringComparison.Ordinal) ||
            value.Contains("sydney", StringComparison.Ordinal) ||
            value.Contains("_aus", StringComparison.Ordinal) ||
            value.Contains("_oce", StringComparison.Ordinal))
        {
            return "AU";
        }
        if (value.Contains("europe", StringComparison.Ordinal) ||
            value.Contains("_eu", StringComparison.Ordinal) ||
            value.StartsWith("eu-", StringComparison.Ordinal))
        {
            return "EU";
        }
        if (value.Contains("asia", StringComparison.Ordinal) ||
            value.Contains("singapore", StringComparison.Ordinal) ||
            value.Contains("hong kong", StringComparison.Ordinal) ||
            value.Contains("japan", StringComparison.Ordinal) ||
            ContainsCloudRegion(value, "ap-southeast-1") ||
            ContainsCloudRegion(value, "ap-northeast-1") ||
            ContainsCloudRegion(value, "ap-northeast-2") ||
            ContainsCloudRegion(value, "ap-northeast-3") ||
            ContainsCloudRegion(value, "ap-east-1") ||
            ContainsTokenStartingWith(value, "ape1") ||
            ContainsTokenStartingWith(value, "apse1") ||
            ContainsTokenStartingWith(value, "apse3") ||
            ContainsTokenStartingWith(value, "apse5") ||
            ContainsTokenStartingWith(value, "apse7") ||
            ContainsTokenStartingWith(value, "apse8") ||
            ContainsTokenStartingWith(value, "apne") ||
            value.Contains("_apse", StringComparison.Ordinal))
        {
            return "ASIA";
        }
        if (value.Contains("north america", StringComparison.Ordinal) ||
            value.Contains("pub_us", StringComparison.Ordinal) ||
            value.Contains("_use", StringComparison.Ordinal) ||
            value.Contains("_usw", StringComparison.Ordinal) ||
            value.StartsWith("us-", StringComparison.Ordinal) ||
            value.EndsWith("_us", StringComparison.Ordinal))
        {
            return "US";
        }
        return null;
    }

    private static string? ResolvePublishedShard(string shard)
    {
        var value = shard.Trim();
        return value.Length <= 96 && PublicShard.IsMatch(value)
            ? value.ToLowerInvariant()
            : null;
    }

    private static bool ContainsCloudRegion(string value, string region) =>
        value.Contains(region, StringComparison.Ordinal) ||
        value.Contains(region.Replace('-', '_'), StringComparison.Ordinal);

    private static bool ContainsTokenStartingWith(string value, string prefix) =>
        value.Split(['_', '-', '.', ' ', '/', '\\', ':'],
                StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Any(part => part.StartsWith(prefix, StringComparison.OrdinalIgnoreCase));

    private static GameLogShipSnapshot PresentShip(string raw, string confidence)
    {
        var name = ShipNames.Value.Find(raw);
        var state = confidence switch
        {
            "High" => "confirmed",
            "Medium" => "likely",
            "Low" => "possible",
            _ => "unknown"
        };
        return state == "unknown"
            ? new(state)
            : new(
                state,
                name?.RuntimeId ?? raw,
                name?.EnglishName ?? raw,
                name?.ChineseName,
                name?.TraditionalChineseName);
    }

    private static GameLogLocationSnapshot PresentLocation(string raw, string confidence)
    {
        var state = confidence switch
        {
            "High" => "confirmed",
            "Medium" => "likely",
            "Low" => "possible",
            _ => "unknown"
        };
        if (state == "unknown")
        {
            return new(state);
        }
        var name = LocationNames.Value.Find(raw);
        if (name is null)
        {
            return new("unknown");
        }
        return new(state, name.EnglishName, name.ChineseName, name.CanSynchronize);
    }

    private static ShipNameIndex LoadShipNames()
    {
        using var stream = Assembly.GetExecutingAssembly()
            .GetManifestResourceStream("StarBridge.ShipNamePack.json");
        if (stream is null)
        {
            return ShipNameIndex.Empty;
        }
        using var reader = new StreamReader(stream);
        return ShipNameIndex.Parse(reader.ReadToEnd());
    }
}
