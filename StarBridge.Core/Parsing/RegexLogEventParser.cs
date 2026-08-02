using System.Globalization;
using System.Text.RegularExpressions;
using StarBridge.Core.Events;

namespace StarBridge.Core.Parsing;

public sealed class RegexLogEventParser : ILogEventParser
{
    private static readonly RegexOptions Options =
        RegexOptions.Compiled | RegexOptions.IgnoreCase | RegexOptions.CultureInvariant;
    private static readonly TimeSpan RespawnSequenceWindow = TimeSpan.FromSeconds(90);
    private static readonly TimeSpan RespawnRebindWindow = TimeSpan.FromSeconds(45);
    private static readonly TimeSpan DownedSequenceWindow = TimeSpan.FromMinutes(10);
    private static readonly Regex TimestampPattern = new(@"^<(?<timestamp>[^>]+)>", Options);
    private static readonly Regex PlayerRebindPattern = new(
        @"<Recv (?<action>Unbind|Bind) Batch (?:Add|End) Player>.*?playerGEID=(?<playerId>\d+).*?entityId=(?<entityId>\d+),\s*className=""Player"".*?parentEntityId=(?<parent>\d+)",
        Options);
    private static readonly Regex InventoryTerminatePattern = new(
        @"<(?:Inventory Terminate Location Container|Request Terminate Access To Inventory)>.*?Player\[(?<player>[^\]]+)\]",
        Options);
    private static readonly Regex AttachmentReceivedPattern = new(@"<AttachmentReceived>\s+Player\[(?<player>[^\]]+)\]", Options);
    private static readonly Regex RecoveredHandAttachmentPattern = new(
        @"<AttachmentReceived>\s+Player\[(?<player>[^\]]+)\].*?Port\[weapon_attach_hand_(?:left|right)\]",
        Options);
    private static readonly Regex InventoryLocationPattern = new(@"<Update Inventory Location>\s+Player\s+\[(?<player>[^\]]+)\]", Options);
    private static readonly Regex PersonalInventoryPattern = new(@"<RequestOrCreatePersonalInventoryData>\s+Player\[(?<player>[^\]]+)\]", Options);

    private readonly ParserRule[] _rules =
    [
        new(FleetEventType.PlayerEnteredShip, new Regex(@"<SHUDEvent_OnNotification>\s+Added notification ""[^""]*(?:joined|加入)[^""]*(?:channel|频道)\s+'(?<ship>[^:']+)\s+:\s+(?<player>[^']+)'", Options), PlayerIsShipOwner: true),
        new(FleetEventType.PlayerExitedShip, new Regex(@"<SHUDEvent_OnNotification>\s+Added notification ""[^""]*(?:left|退出|离开)[^""]*(?:channel|频道)\s+'(?<ship>[^:']+)\s+:\s+(?<player>[^']+)'", Options), PlayerIsShipOwner: true),
        new(FleetEventType.PlayerOnline, new Regex(@"nickname=""(?<player>[^""]+)""\s+playerGEID\s*=?\s*""?(?<playerId>\d+)?", Options)),
        new(FleetEventType.PlayerOffline, new Regex(@"PLAYER_OFFLINE\s+player=""?(?<player>[^""\s]+)""?", Options)),
        new(FleetEventType.PlayerLocationChanged, new Regex(@"<RequestLocationInventory>\s+Player\[(?<player>[^\]]+)\]\s+requested inventory for Location\[(?<location>[A-Za-z0-9_-]+)\]", Options), LocationEvidenceScore: 95, LocationEvidence: "Location inventory context"),
        new(FleetEventType.PlayerNavigationTargetChanged, new Regex(@"<Player Selected Quantum Target - Local>.*?\|\s*(?:NOT AUTH|AUTH)\s*\|\s*(?<ship>[A-Za-z0-9_]+)_(?<shipId>\d+)\[\d+\]\|.*?Player has selected point (?<target>[A-Za-z0-9_-]+) as their destination", Options)),
        new(FleetEventType.PlayerNavigationTargetChanged, new Regex(@"<Calculate Route>.*?\|\s*(?:NOT AUTH|AUTH)\s*\|\s*(?<ship>[A-Za-z0-9_]+)_(?<shipId>\d+)\[\d+\]\|.*?Projected Start Location is (?<location>.+?) for route to destination (?<target>[A-Za-z0-9_-]+)", Options)),
        new(FleetEventType.PlayerNavigationTargetChanged, new Regex(@"<Calculate Route>.*?\|\s*(?:NOT AUTH|AUTH)\s*\|\s*(?<ship>[A-Za-z0-9_]+)_(?<shipId>\d+)\[\d+\]\|.*?route to destination (?<target>[A-Za-z0-9_-]+)", Options)),
        new(FleetEventType.PlayerNavigationTargetChanged, new Regex(@"<Calculate Route>.*?\|\s*(?:NOT AUTH|AUTH)\s*\|\s*(?<ship>[A-Za-z0-9_]+)_(?<shipId>\d+)\[\d+\]\|.*?Successfully calculated route to (?<target>[A-Za-z0-9_-]+)", Options)),
        new(FleetEventType.PlayerLocationChanged, new Regex(@"<Quantum Drive Arrived - Arrived at Final Destination>.*?\|\s*(?:NOT AUTH|AUTH)\s*\|\s*(?<ship>[A-Za-z0-9_]+)_(?<shipId>\d+)\[\d+\]\|.*?CSCItemNavigation::OnQuantumDriveArrived", Options), DefaultLocation: "Arrived - awaiting location confirmation", LocationEvidenceScore: 45, LocationEvidence: "Quantum arrival"),
        new(FleetEventType.PlayerLocationChanged, new Regex(@"<Quantum Drive Arrived - Arrived at Final Destination>.*?CSCItemNavigation::OnQuantumDriveArrived", Options), DefaultLocation: "Arrived - awaiting location confirmation", LocationEvidenceScore: 45, LocationEvidence: "Quantum arrival"),
        new(FleetEventType.PlayerEnteredShip, new Regex(@"PLAYER_ENTER_SHIP\s+player=""?(?<player>[^""\s]+)""?\s+ship=""?(?<ship>[^""]+?)""?$", Options)),
        new(FleetEventType.PlayerExitedShip, new Regex(@"PLAYER_EXIT_SHIP\s+player=""?(?<player>[^""\s]+)""?\s+ship=""?(?<ship>[^""]+?)""?$", Options)),
        new(FleetEventType.PlayerLocationChanged, new Regex(@"PLAYER_LOCATION\s+player=""?(?<player>[^""\s]+)""?\s+location=""?(?<location>[^""]+?)""?$", Options), LocationEvidenceScore: 90, LocationEvidence: "Explicit player location"),
        new(FleetEventType.CombatStateChanged, new Regex(@"COMBAT_STATE\s+player=""?(?<player>[^""\s]+)""?\s+state=""?(?<combat>[^""\s]+)""?", Options)),
        new(FleetEventType.NetworkStateChanged, new Regex(@"NETWORK_STATE\s+player=""?(?<player>[^""\s]+)""?\s+state=""?(?<network>[^""\s]+)""?", Options)),
        new(FleetEventType.PlayerStoppedDrivingShip, new Regex(@"ClearDriver:.*?Local client node.*?'(?<ship>[A-Za-z0-9_]+)_(?<shipId>\d+)'", Options)),
        new(FleetEventType.PlayerControllingShip, new Regex(@"SetDriver:.*?Local client node.*?'(?<ship>[A-Za-z0-9_]+)_(?<shipId>\d+)'", Options)),
        new(FleetEventType.PlayerControllingShip, new Regex(@"Local client node.*?(acquiring|taking|received).*?control token.*?'(?<ship>[A-Za-z0-9_]+)_(?<shipId>\d+)'", Options)),
        new(FleetEventType.PlayerShipControlSignal, new Regex(@"<Failed to get starmap route data!>.*?\|\s*(?:NOT AUTH|AUTH)\s*\|\s*(?<ship>[A-Za-z0-9_]+)_(?<shipId>\d+)\[\d+\]\|CSCItemNavigation::GetStarmapRouteSegmentData", Options)),
        new(FleetEventType.PlayerShipControlSignal, new Regex(@"<Player (Requested Fuel to Quantum Target|Selected Quantum Target).*?\|\s*(?:NOT AUTH|AUTH)\s*\|\s*(?<ship>[A-Za-z0-9_]+)_(?<shipId>\d+)\[\d+\]\|CSCItemNavigation", Options)),
        new(FleetEventType.PlayerShipControlSignal, new Regex(@"<Calculate Route>.*?\|\s*(?:NOT AUTH|AUTH)\s*\|\s*(?<ship>[A-Za-z0-9_]+)_(?<shipId>\d+)\[\d+\]\|CSCItemNavigation::CalculateRoute", Options)),
    ];

    private readonly RespawnTracker _respawn = new();
    private string? _localPlayer;
    private string? _localPlayerId;

    public FleetEvent? TryParse(string line)
    {
        if (string.IsNullOrWhiteSpace(line))
        {
            return null;
        }

        var timestamp = ParseTimestamp(line) ?? DateTimeOffset.Now;
        var trackedStatusEvent = TrackRespawnEvidence(line, timestamp);
        if (trackedStatusEvent is not null)
        {
            return trackedStatusEvent;
        }

        var oneShotStatusEvent = TryParseOneShotStatusEvent(line, timestamp);
        if (oneShotStatusEvent is not null)
        {
            return oneShotStatusEvent;
        }

        foreach (var rule in _rules)
        {
            var match = rule.Pattern.Match(line);
            if (!match.Success)
            {
                continue;
            }

            var player = Value(match, "player");
            var ship = Value(match, "ship");
            var shipInstanceId = Value(match, "shipId");
            var location = Value(match, "location");
            var navigationTarget = Value(match, "target") ?? location;
            string? shipOwner = null;

            if (ship is not null)
            {
                ship = NormalizeShipName(ship);
            }

            if (rule.PlayerIsShipOwner)
            {
                shipOwner = player;
                player = "LocalPlayer";
            }

            if (string.IsNullOrWhiteSpace(player))
            {
                player = "LocalPlayer";
            }

            var playerId = Value(match, "playerId");
            if (rule.Type == FleetEventType.PlayerOnline)
            {
                _localPlayer = player;
                if (!string.IsNullOrWhiteSpace(playerId))
                {
                    _localPlayerId = playerId;
                }
            }

            if (!string.IsNullOrWhiteSpace(location) && !string.IsNullOrWhiteSpace(rule.LocationPrefix))
            {
                location = $"{rule.LocationPrefix}{location}";
            }

            if (string.IsNullOrWhiteSpace(location))
            {
                location = rule.DefaultLocation;
            }

            return new FleetEvent(
                rule.Type,
                player,
                Ship: ship,
                Location: location,
                CombatState: Value(match, "combat"),
                NetworkState: Value(match, "network"),
                Timestamp: timestamp,
                SourceLine: line,
                PlayerId: playerId,
                ShipOwner: shipOwner,
                ShipInstanceId: shipInstanceId,
                NavigationTarget: rule.Type == FleetEventType.PlayerNavigationTargetChanged ? navigationTarget : null,
                LocationEvidenceScore: GetLocationEvidenceScore(rule, location),
                LocationEvidence: GetLocationEvidence(rule, location));
        }

        return null;
    }

    private FleetEvent? TryParseOneShotStatusEvent(string line, DateTimeOffset timestamp)
    {
        if (IsClientSpawnCompleted(line) && IsRespawnSequenceConfirmed(timestamp))
        {
            _respawn.Clear();
            return new FleetEvent(
                FleetEventType.PlayerRespawned,
                "LocalPlayer",
                Timestamp: timestamp,
                SourceLine: line,
                PlayerId: _localPlayerId);
        }

        if (!IsAddedNotification(line))
        {
            return null;
        }

        var downedContext = ResolveDownedContext(line);
        if (downedContext != LifeEventContext.Unknown)
        {
            if (_respawn.IsSameDownedEpisode(timestamp))
            {
                if (downedContext != LifeEventContext.SafeZoneMedicalResponse ||
                    _respawn.DownedEventPublished)
                {
                    return null;
                }
            }
            else
            {
                _respawn.ResetForDowned(timestamp);
            }

            // Generic incapacitation remains internal evidence for the later
            // death/revival decision. Only an explicit local medical response
            // is reliable enough to publish as a safe-zone downed event.
            if (downedContext != LifeEventContext.SafeZoneMedicalResponse)
            {
                return null;
            }

            _respawn.DownedEventPublished = true;
            return new FleetEvent(
                FleetEventType.PlayerDowned,
                "LocalPlayer",
                Timestamp: timestamp,
                SourceLine: line,
                PlayerId: _localPlayerId,
                LifeContext: downedContext);
        }

        if (IsMedicalBedNotification(line) && IsRespawnSequenceConfirmed(timestamp))
        {
            _respawn.Clear();
            return new FleetEvent(
                FleetEventType.PlayerRespawned,
                "LocalPlayer",
                Timestamp: timestamp,
                SourceLine: line,
                PlayerId: _localPlayerId);
        }

        return null;
    }

    private FleetEvent? TrackRespawnEvidence(string line, DateTimeOffset timestamp)
    {
        if ((_respawn.DeathAt is not null &&
             timestamp - _respawn.DeathAt.Value > RespawnSequenceWindow) ||
            (_respawn.DeathAt is null &&
             _respawn.DownedAt is not null &&
             timestamp - _respawn.DownedAt.Value > DownedSequenceWindow))
        {
            _respawn.Clear();
        }

        if (_respawn.DeathAt is null && IsCorpseRecoveryRootEvidence(line))
        {
            _respawn.ConfirmDeath(timestamp);
            return new FleetEvent(
                FleetEventType.PlayerDied,
                "LocalPlayer",
                Timestamp: timestamp,
                SourceLine: line,
                PlayerId: _localPlayerId);
        }

        if (IsDownedNotificationRemoval(line) && _respawn.DownedAt is not null)
        {
            _respawn.DownedNotificationRemovedAt = timestamp;
            if (IsDeathConfirmingNotificationRemoval(line) && _respawn.DeathAt is null)
            {
                _respawn.ConfirmDeath(timestamp);
                return new FleetEvent(
                    FleetEventType.PlayerDied,
                    "LocalPlayer",
                    Timestamp: timestamp,
                    SourceLine: line,
                    PlayerId: _localPlayerId);
            }

            return null;
        }

        var rebind = PlayerRebindPattern.Match(line);
        if (rebind.Success && IsLocalPlayerId(Value(rebind, "playerId")))
        {
            var action = Value(rebind, "action");
            if (action?.Equals("Unbind", StringComparison.OrdinalIgnoreCase) == true)
            {
                _respawn.UnbindAt = timestamp;
                _respawn.PlayerId = Value(rebind, "playerId");
                _respawn.EntityId = Value(rebind, "entityId");
                _respawn.OldParentId = Value(rebind, "parent");
                if (_respawn.DownedAt is not null &&
                    _respawn.DeathAt is null &&
                    timestamp - _respawn.DownedAt.Value <= DownedSequenceWindow)
                {
                    _respawn.ConfirmDeath(timestamp);
                    return new FleetEvent(
                        FleetEventType.PlayerDied,
                        "LocalPlayer",
                        Timestamp: timestamp,
                        SourceLine: line,
                        PlayerId: _localPlayerId);
                }

                return null;
            }

            if (action?.Equals("Bind", StringComparison.OrdinalIgnoreCase) == true &&
                _respawn.UnbindAt is not null &&
                timestamp - _respawn.UnbindAt.Value <= RespawnRebindWindow &&
                IdsMatch(_respawn.PlayerId, Value(rebind, "playerId")) &&
                IdsMatch(_respawn.EntityId, Value(rebind, "entityId")))
            {
                var newParent = Value(rebind, "parent");
                if (!string.IsNullOrWhiteSpace(newParent) &&
                    !string.Equals(_respawn.OldParentId, newParent, StringComparison.OrdinalIgnoreCase))
                {
                    _respawn.BindAt = timestamp;
                    _respawn.NewParentId = newParent;
                }

                return null;
            }
        }

        if (_respawn.DownedAt is not null &&
            _respawn.DeathAt is null &&
            _respawn.DownedNotificationRemovedAt is not null &&
            timestamp - _respawn.DownedAt.Value <= DownedSequenceWindow &&
            RecoveredHandAttachmentPattern.Match(line) is { Success: true } recoveredActivity &&
            IsLocalPlayerName(Value(recoveredActivity, "player")))
        {
            _respawn.Clear();
            return new FleetEvent(
                FleetEventType.PlayerRevived,
                "LocalPlayer",
                Timestamp: timestamp,
                SourceLine: line,
                PlayerId: _localPlayerId);
        }

        if (InventoryTerminatePattern.Match(line) is { Success: true } inventoryTerminate &&
            IsLocalPlayerName(Value(inventoryTerminate, "player")))
        {
            _respawn.InventoryTerminatedAt = timestamp;
            if (IsLocationInventoryTermination(line) &&
                _respawn.DownedAt is not null &&
                _respawn.DeathAt is null &&
                timestamp - _respawn.DownedAt.Value <= DownedSequenceWindow)
            {
                _respawn.ConfirmDeath(timestamp);
                return new FleetEvent(
                    FleetEventType.PlayerDied,
                    "LocalPlayer",
                    Timestamp: timestamp,
                    SourceLine: line,
                    PlayerId: _localPlayerId);
            }

            return null;
        }

        if (line.Contains("<Initializing Haptic>", StringComparison.OrdinalIgnoreCase) &&
            _respawn.BindAt is not null &&
            timestamp - _respawn.BindAt.Value <= TimeSpan.FromSeconds(10))
        {
            _respawn.HapticInitialized = true;
            return null;
        }

        if (AttachmentReceivedPattern.Match(line) is { Success: true } attachment &&
            IsLocalPlayerName(Value(attachment, "player")) &&
            _respawn.BindAt is not null &&
            timestamp - _respawn.BindAt.Value <= TimeSpan.FromSeconds(10))
        {
            _respawn.AttachmentReceivedCount++;
            return null;
        }

        if (InventoryLocationPattern.Match(line) is { Success: true } inventoryLocation &&
            IsLocalPlayerName(Value(inventoryLocation, "player")) &&
            _respawn.BindAt is not null &&
            timestamp - _respawn.BindAt.Value <= TimeSpan.FromSeconds(15))
        {
            _respawn.InventoryLocationChanged = true;
            return null;
        }

        if (PersonalInventoryPattern.Match(line) is { Success: true } personalInventory &&
            IsLocalPlayerName(Value(personalInventory, "player")) &&
            _respawn.BindAt is not null &&
            timestamp - _respawn.BindAt.Value <= TimeSpan.FromSeconds(20))
        {
            _respawn.PersonalInventoryReady = true;
        }

        return null;
    }

    private bool IsRespawnSequenceConfirmed(DateTimeOffset timestamp)
    {
        if (_respawn.DeathAt is null ||
            _respawn.BindAt is null ||
            timestamp - _respawn.DeathAt.Value > RespawnSequenceWindow ||
            timestamp - _respawn.BindAt.Value > RespawnRebindWindow)
        {
            return false;
        }

        var hasRebindToDifferentParent = !string.IsNullOrWhiteSpace(_respawn.OldParentId) &&
                                         !string.IsNullOrWhiteSpace(_respawn.NewParentId) &&
                                         !_respawn.OldParentId.Equals(_respawn.NewParentId, StringComparison.OrdinalIgnoreCase);
        var hasPostBindLoadoutSignal = _respawn.HapticInitialized ||
                                       _respawn.AttachmentReceivedCount >= 10 ||
                                       _respawn.InventoryLocationChanged ||
                                       _respawn.PersonalInventoryReady;
        return hasRebindToDifferentParent && hasPostBindLoadoutSignal;
    }

    private bool IsLocalPlayerId(string? playerId)
    {
        return string.IsNullOrWhiteSpace(_localPlayerId) ||
               string.IsNullOrWhiteSpace(playerId) ||
               _localPlayerId.Equals(playerId, StringComparison.OrdinalIgnoreCase);
    }

    private bool IsLocalPlayerName(string? player)
    {
        return string.IsNullOrWhiteSpace(_localPlayer) ||
               string.IsNullOrWhiteSpace(player) ||
               _localPlayer.Equals(player, StringComparison.OrdinalIgnoreCase);
    }

    private static string? Value(Match match, string name)
    {
        var group = match.Groups[name];
        return group.Success ? group.Value.Trim() : null;
    }

    private static string NormalizeShipName(string raw)
    {
        var index = raw.LastIndexOf('_');

        if (index <= 0)
        {
            return raw;
        }

        var suffix = raw[(index + 1)..];

        return suffix.All(char.IsDigit)
            ? raw[..index]
            : raw;
    }

    private static DateTimeOffset? ParseTimestamp(string line)
    {
        var match = TimestampPattern.Match(line);
        if (!match.Success)
        {
            return null;
        }

        return DateTimeOffset.TryParse(
            match.Groups["timestamp"].Value,
            CultureInfo.InvariantCulture,
            DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal,
            out var timestamp)
            ? timestamp
            : null;
    }

    private static bool IsAddedNotification(string line)
    {
        return line.Contains("<SHUDEvent_OnNotification>", StringComparison.OrdinalIgnoreCase) &&
               line.Contains("Added notification", StringComparison.OrdinalIgnoreCase);
    }

    private static bool IsMedicalResponseNotification(string line)
    {
        return line.Contains("本地急救人员正在赶来的路上", StringComparison.Ordinal) ||
               (line.Contains("medical", StringComparison.OrdinalIgnoreCase) &&
                line.Contains("on the way", StringComparison.OrdinalIgnoreCase));
    }

    private static bool IsIncapacitatedNotification(string line)
    {
        return line.Contains("丧失行动能力", StringComparison.Ordinal) ||
               line.Contains("incapacitated", StringComparison.OrdinalIgnoreCase) ||
               line.Contains("incapacitation", StringComparison.OrdinalIgnoreCase);
    }

    private static LifeEventContext ResolveDownedContext(string line)
    {
        if (IsMedicalResponseNotification(line))
        {
            return LifeEventContext.SafeZoneMedicalResponse;
        }

        return IsIncapacitatedNotification(line)
            ? LifeEventContext.Incapacitated
            : LifeEventContext.Unknown;
    }

    private static bool IsDownedNotificationRemoval(string line)
    {
        return line.Contains("<UpdateNotificationItem>", StringComparison.OrdinalIgnoreCase) &&
               line.Contains("Remove", StringComparison.OrdinalIgnoreCase) &&
               ResolveDownedContext(line) != LifeEventContext.Unknown;
    }

    private static bool IsDeathConfirmingNotificationRemoval(string line)
    {
        return line.Contains("Action: RemoveIgnore", StringComparison.OrdinalIgnoreCase);
    }

    private static bool IsLocationInventoryTermination(string line)
    {
        return line.Contains("<Inventory Terminate Location Container>", StringComparison.OrdinalIgnoreCase);
    }

    private static bool IsCorpseRecoveryRootEvidence(string line)
    {
        return line.Contains(
                   "<Adding non kept item [CSCActorCorpseUtils::PopulateItemPortForItemRecoveryEntitlement]>",
                   StringComparison.OrdinalIgnoreCase) &&
               line.Contains("Class(body_01_noMagicPocket)", StringComparison.OrdinalIgnoreCase) &&
               line.Contains("Port Name 'Body_ItemPort'", StringComparison.OrdinalIgnoreCase);
    }

    private static bool IsClientSpawnCompleted(string line)
    {
        return line.Contains("[CSessionManager::OnClientSpawned]", StringComparison.OrdinalIgnoreCase) &&
               line.Contains("Spawned!", StringComparison.OrdinalIgnoreCase);
    }

    private static bool IsMedicalBedNotification(string line)
    {
        return (line.Contains("医疗床", StringComparison.Ordinal) &&
                line.Contains("恢复了你的健康", StringComparison.Ordinal)) ||
               (line.Contains("medical bed", StringComparison.OrdinalIgnoreCase) &&
                line.Contains("health", StringComparison.OrdinalIgnoreCase));
    }

    private static bool IdsMatch(string? left, string? right)
    {
        return string.IsNullOrWhiteSpace(left) ||
               string.IsNullOrWhiteSpace(right) ||
               left.Equals(right, StringComparison.OrdinalIgnoreCase);
    }

    private sealed record ParserRule(
        FleetEventType Type,
        Regex Pattern,
        bool PlayerIsShipOwner = false,
        string? LocationPrefix = null,
        string? DefaultLocation = null,
        int LocationEvidenceScore = 0,
        string? LocationEvidence = null);

    private static int GetLocationEvidenceScore(ParserRule rule, string? location)
    {
        if (rule.Type == FleetEventType.PlayerNavigationTargetChanged && !string.IsNullOrWhiteSpace(location))
        {
            return 60;
        }

        return rule.LocationEvidenceScore;
    }

    private static string? GetLocationEvidence(ParserRule rule, string? location)
    {
        if (rule.Type == FleetEventType.PlayerNavigationTargetChanged && !string.IsNullOrWhiteSpace(location))
        {
            return "Quantum route start location";
        }

        return rule.LocationEvidence;
    }

    private sealed class RespawnTracker
    {
        public DateTimeOffset? DownedAt { get; private set; }
        public DateTimeOffset? DeathAt { get; private set; }
        public bool DownedEventPublished { get; set; }
        public DateTimeOffset? DownedNotificationRemovedAt { get; set; }
        public DateTimeOffset? InventoryTerminatedAt { get; set; }
        public DateTimeOffset? UnbindAt { get; set; }
        public DateTimeOffset? BindAt { get; set; }
        public string? PlayerId { get; set; }
        public string? EntityId { get; set; }
        public string? OldParentId { get; set; }
        public string? NewParentId { get; set; }
        public bool HapticInitialized { get; set; }
        public int AttachmentReceivedCount { get; set; }
        public bool InventoryLocationChanged { get; set; }
        public bool PersonalInventoryReady { get; set; }

        public void ResetForDowned(DateTimeOffset timestamp)
        {
            Clear();
            DownedAt = timestamp;
        }

        public void ConfirmDeath(DateTimeOffset timestamp)
        {
            DeathAt = timestamp;
        }

        public bool IsSameDownedEpisode(DateTimeOffset timestamp)
        {
            return DownedAt is not null &&
                   timestamp >= DownedAt.Value &&
                   timestamp - DownedAt.Value <= DownedSequenceWindow;
        }

        public void Clear()
        {
            DownedAt = null;
            DeathAt = null;
            DownedEventPublished = false;
            DownedNotificationRemovedAt = null;
            InventoryTerminatedAt = null;
            UnbindAt = null;
            BindAt = null;
            PlayerId = null;
            EntityId = null;
            OldParentId = null;
            NewParentId = null;
            HapticInitialized = false;
            AttachmentReceivedCount = 0;
            InventoryLocationChanged = false;
            PersonalInventoryReady = false;
        }
    }
}
