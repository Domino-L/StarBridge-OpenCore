using StarBridge.Core.Events;

namespace StarBridge.Core.State;

public sealed class FleetState
{
    private static readonly TimeSpan ShipEvidenceDecayWindow = TimeSpan.FromMinutes(5);
    private const int MaxShipInferenceScore = 100;
    private const int ShipSignalRefreshBonus = 25;
    private const double ShipScoreDecayPerMinute = 8;
    private const double PostControlSeatExitDecayPerMinute = 10;
    private const int MaxLocationInferenceScore = 100;
    private const double LocationScoreDecayPerMinute = 4;
    private static readonly TimeSpan PostQuantumArrivalShipRetentionWindow = TimeSpan.FromSeconds(15);
    private readonly Dictionary<string, FleetPlayer> _players = new(StringComparer.OrdinalIgnoreCase);
    public IReadOnlyCollection<FleetPlayer> Players => _players.Values
        .OrderByDescending(player => player.Online)
        .ThenBy(player => player.Name)
        .ToArray();

    public void Clear()
    {
        _players.Clear();
    }

    public void RemovePlayersExcept(IEnumerable<string?> playerNames)
    {
        var keep = playerNames
            .Where(name => !string.IsNullOrWhiteSpace(name))
            .Select(name => name!.Trim())
            .ToHashSet(StringComparer.OrdinalIgnoreCase);

        if (keep.Count == 0)
        {
            _players.Clear();
            return;
        }

        foreach (var name in _players.Keys.Where(name => !keep.Contains(name)).ToArray())
        {
            _players.Remove(name);
        }
    }

    public void Apply(FleetEvent fleetEvent)
    {
        var player = GetOrCreate(fleetEvent.Player);
        var timestamp = fleetEvent.Timestamp ?? DateTimeOffset.Now;
        player.LastSeen = timestamp;
        player.IsIdle = false;

        switch (fleetEvent.Type)
        {
            case FleetEventType.PlayerOnline:
                player.Online = true;
                RestoreLowConfidenceState(player, timestamp);
                break;
            case FleetEventType.PlayerOffline:
                player.Online = false;
                ClearActiveStateForOffline(player);
                break;
            case FleetEventType.PlayerEnteredShip:
                player.Online = true;
                AddShipEvidence(
                    player,
                    fleetEvent.Ship,
                    fleetEvent.ShipInstanceId,
                    MaxShipInferenceScore,
                    "Ship channel joined",
                    timestamp,
                    ShipEvidenceStrength.Channel,
                    confirmsShipChannel: true);
                break;
            case FleetEventType.PlayerExitedShip:
                ClearShipInferenceIfCurrentShip(player, fleetEvent.Ship, "Ship channel left");
                break;
            case FleetEventType.PlayerControllingShip:
                player.Online = true;
                if (AddShipEvidence(
                        player,
                        fleetEvent.Ship,
                        fleetEvent.ShipInstanceId,
                        90,
                        "Vehicle control token",
                        timestamp,
                        ShipEvidenceStrength.Strong))
                {
                    player.LastControlSeatLeftAt = null;
                }
                break;
            case FleetEventType.PlayerShipControlSignal:
                player.Online = true;
                AddShipEvidence(
                    player,
                    fleetEvent.Ship,
                    fleetEvent.ShipInstanceId,
                    35,
                    "Navigation system context",
                    timestamp,
                    ShipEvidenceStrength.Weak);
                break;
            case FleetEventType.PlayerStoppedDrivingShip:
                player.Online = true;
                ApplyControlSeatRelease(player, fleetEvent.Ship, fleetEvent.ShipInstanceId, timestamp);
                break;
            case FleetEventType.PlayerLocationChanged:
                player.Online = true;
                var location = fleetEvent.Location;
                var locationScore = fleetEvent.LocationEvidenceScore;
                var locationEvidence = fleetEvent.LocationEvidence ?? "Location signal";
                var isQuantumArrival = IsQuantumArrivalPlaceholder(location);
                var isLocationInventoryContext = IsLocationInventoryContext(locationEvidence);
                var retainShipForQuantumArrival = isLocationInventoryContext &&
                                                  IsWithinPostQuantumArrivalWindow(player, timestamp);
                var quantumArrivalTarget = HasKnownNavigationTarget(fleetEvent.NavigationTarget)
                    ? fleetEvent.NavigationTarget
                    : player.NavigationTarget;
                if (isQuantumArrival)
                {
                    player.ArrivalPendingConfirmation = true;
                    player.ArrivalTargetCode = HasKnownNavigationTarget(quantumArrivalTarget)
                        ? quantumArrivalTarget!.Trim()
                        : null;
                    player.LastQuantumArrivalAt = timestamp;
                }
                else
                {
                    AddLocationEvidence(
                        player,
                        location,
                        locationScore,
                        locationEvidence,
                        timestamp);
                }

                if (!isQuantumArrival && isLocationInventoryContext)
                {
                    if (!retainShipForQuantumArrival)
                    {
                        ClearShipInference(player, "Location inventory context");
                    }

                    if (player.LastQuantumArrivalAt is not null &&
                        timestamp - player.LastQuantumArrivalAt.Value > PostQuantumArrivalShipRetentionWindow)
                    {
                        player.LastQuantumArrivalAt = null;
                    }
                }

                break;
            case FleetEventType.PlayerNavigationTargetChanged:
                player.Online = true;
                ObserveNavigationJourney(player, fleetEvent, timestamp);
                AddShipEvidence(
                    player,
                    fleetEvent.Ship,
                    fleetEvent.ShipInstanceId,
                    45,
                    "Quantum route context",
                    timestamp,
                    ShipEvidenceStrength.Weak);
                break;
            case FleetEventType.CombatStateChanged:
                player.Online = true;
                player.CombatState = fleetEvent.CombatState ?? player.CombatState;
                break;
            case FleetEventType.NetworkStateChanged:
                player.NetworkState = fleetEvent.NetworkState ?? player.NetworkState;
                break;
        }
    }

    public void RefreshShipInferences(DateTimeOffset now)
    {
        foreach (var player in _players.Values)
        {
            DecayShipInference(player, now);
            DecayLocationInference(player, now);
        }
    }

    public void SetPlayerOnlineState(string name, bool online, DateTimeOffset timestamp)
    {
        if (string.IsNullOrWhiteSpace(name) || !_players.TryGetValue(name, out var player))
        {
            return;
        }

        if (online)
        {
            player.Online = true;
            RestoreLowConfidenceState(player, timestamp);
            return;
        }

        player.Online = false;
        ClearActiveStateForOffline(player);
    }

    public FleetSummary GetSummary()
    {
        var players = Players;
        return new FleetSummary(
            TotalPlayers: players.Count,
            OnlinePlayers: players.Count(player => player.Online),
            ShipsKnown: players.Count(player => player.Ship != "Unknown"),
            LocationsKnown: players.Count(player => player.Location != "Unknown"));
    }

    private FleetPlayer GetOrCreate(string name)
    {
        if (_players.TryGetValue(name, out var player))
        {
            return player;
        }

        player = new FleetPlayer { Name = name };
        _players.Add(name, player);
        return player;
    }

    private static bool IsQuantumArrivalPlaceholder(string? location)
    {
        return location?.Equals("Arrived - awaiting location confirmation", StringComparison.OrdinalIgnoreCase) == true;
    }

    private static bool IsLocationInventoryContext(string? evidence)
    {
        return evidence?.Equals("Location inventory context", StringComparison.OrdinalIgnoreCase) == true;
    }

    private static bool IsWithinPostQuantumArrivalWindow(FleetPlayer player, DateTimeOffset timestamp)
    {
        if (player.LastQuantumArrivalAt is not { } arrivedAt || timestamp < arrivedAt)
        {
            return false;
        }

        return timestamp - arrivedAt <= PostQuantumArrivalShipRetentionWindow;
    }

    private static bool HasKnownNavigationTarget(string? navigationTarget)
    {
        return !string.IsNullOrWhiteSpace(navigationTarget) &&
               !navigationTarget.Equals("None", StringComparison.OrdinalIgnoreCase) &&
               !navigationTarget.Equals("Unknown", StringComparison.OrdinalIgnoreCase);
    }

    private static void ObserveNavigationJourney(
        FleetPlayer player,
        FleetEvent fleetEvent,
        DateTimeOffset timestamp)
    {
        if (!HasKnownNavigationTarget(fleetEvent.NavigationTarget))
        {
            return;
        }

        var target = fleetEvent.NavigationTarget!.Trim();
        var isNewJourney = !player.NavigationTarget.Equals(target, StringComparison.OrdinalIgnoreCase) ||
                           player.NavigationTargetSelectedAt is null;
        if (isNewJourney)
        {
            player.NavigationTargetSelectedAt = fleetEvent.NavigationTargetSelectedAt ?? timestamp;
            player.NavigationOriginLocation = HasKnownNavigationTarget(fleetEvent.NavigationOriginLocation)
                ? fleetEvent.NavigationOriginLocation!.Trim()
                : HasKnownNavigationTarget(player.Location)
                    ? player.Location
                    : null;
        }

        player.NavigationTarget = target;
    }

    private static void ClearNavigationJourney(FleetPlayer player)
    {
        player.NavigationTarget = "None";
        player.NavigationTargetSelectedAt = null;
        player.NavigationOriginLocation = null;
    }

    private static bool AddShipEvidence(
        FleetPlayer player,
        string? ship,
        string? shipInstanceId,
        int score,
        string evidence,
        DateTimeOffset timestamp,
        ShipEvidenceStrength strength,
        bool confirmsShipChannel = false)
    {
        DecayShipInference(player, timestamp);

        var isDifferentShip = !string.IsNullOrWhiteSpace(ship) &&
                              !player.Ship.Equals("Unknown", StringComparison.OrdinalIgnoreCase) &&
                              !ShipNamesMatch(player.Ship, ship);
        var isDifferentShipInstance = !string.IsNullOrWhiteSpace(shipInstanceId) &&
                                      !string.IsNullOrWhiteSpace(player.ShipInstanceId) &&
                                      !player.ShipInstanceId.Equals(shipInstanceId, StringComparison.OrdinalIgnoreCase);

        if (isDifferentShip || isDifferentShipInstance)
        {
            if (!CanReplaceCurrentShip(player, strength))
            {
                return false;
            }

            player.ShipInferenceScore = 0;
            player.LastControlSeatLeftAt = null;
            player.ShipChannelMembershipConfirmed = false;
            player.LastShipChannelEventAt = null;
        }

        var sameShipInstanceSeenRecently = !string.IsNullOrWhiteSpace(shipInstanceId) &&
                                           player.ShipInstanceId?.Equals(shipInstanceId, StringComparison.OrdinalIgnoreCase) == true &&
                                           player.LastShipInstanceSeenAt is not null &&
                                           timestamp - player.LastShipInstanceSeenAt.Value <= ShipEvidenceDecayWindow;

        if (!string.IsNullOrWhiteSpace(ship))
        {
            player.Ship = ship;
        }

        if (!string.IsNullOrWhiteSpace(shipInstanceId))
        {
            player.ShipInstanceId = shipInstanceId;
            player.LastShipInstanceSeenAt = timestamp;
        }

        if (player.Ship.Equals("Unknown", StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }

        if (confirmsShipChannel)
        {
            player.ShipChannelMembershipConfirmed = true;
            player.LastShipChannelEventAt = timestamp;
        }

        player.ShipInferenceScore = Math.Min(
            MaxShipInferenceScore,
            strength == ShipEvidenceStrength.Channel
                ? MaxShipInferenceScore
                : player.ShipInferenceScore + score + (sameShipInstanceSeenRecently ? ShipSignalRefreshBonus : 0));
        player.ShipConfidence = GetShipConfidence(player);
        player.ShipEvidence = evidence;
        player.LastShipEvidenceAt = timestamp;
        player.LastShipScoreUpdatedAt = timestamp;
        return true;
    }

    private static bool CanReplaceCurrentShip(FleetPlayer player, ShipEvidenceStrength strength)
    {
        if (player.Ship.Equals("Unknown", StringComparison.OrdinalIgnoreCase))
        {
            return true;
        }

        if (strength == ShipEvidenceStrength.Channel)
        {
            return true;
        }

        if (player.ShipChannelMembershipConfirmed)
        {
            return false;
        }

        return strength != ShipEvidenceStrength.Weak ||
               player.ShipInferenceScore < 45;
    }

    private static void ClearShipInferenceIfCurrentShip(FleetPlayer player, string? ship, string evidence)
    {
        if (string.IsNullOrWhiteSpace(ship) ||
            player.Ship.Equals("Unknown", StringComparison.OrdinalIgnoreCase) ||
            ShipNamesMatch(player.Ship, ship))
        {
            ClearShipInference(player, evidence);

            // An authoritative vehicle exit must also revoke the reconnect fallback;
            // otherwise the next online presentation refresh restores the ship that
            // this event just cleared.
            if (string.IsNullOrWhiteSpace(ship) ||
                string.IsNullOrWhiteSpace(player.LastKnownShip) ||
                ShipNamesMatch(player.LastKnownShip, ship))
            {
                player.LastKnownShip = null;
                player.LastKnownShipInstanceId = null;
            }
        }
    }

    private static void ApplyControlSeatRelease(
        FleetPlayer player,
        string? ship,
        string? shipInstanceId,
        DateTimeOffset timestamp)
    {
        if (!ShipEventMatchesCurrent(player, ship, shipInstanceId))
        {
            return;
        }

        var releaseShip = string.IsNullOrWhiteSpace(ship) ? player.Ship : ship;
        if (ImmediateVehicleExitCatalog.Contains(releaseShip))
        {
            ClearShipInferenceIfCurrentShip(
                player,
                releaseShip,
                "Control seat release confirms vehicle exit");
            return;
        }

        if (AddShipEvidence(
                player,
                ship,
                shipInstanceId,
                20,
                "Left control seat; ship not confirmed left",
                timestamp,
                ShipEvidenceStrength.Weak))
        {
            player.LastControlSeatLeftAt = timestamp;
        }
    }

    private static bool ShipEventMatchesCurrent(FleetPlayer player, string? ship, string? shipInstanceId)
    {
        if (player.Ship.Equals("Unknown", StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }

        if (!string.IsNullOrWhiteSpace(ship) && !ShipNamesMatch(player.Ship, ship))
        {
            return false;
        }

        return string.IsNullOrWhiteSpace(shipInstanceId) ||
               string.IsNullOrWhiteSpace(player.ShipInstanceId) ||
               player.ShipInstanceId.Equals(shipInstanceId, StringComparison.OrdinalIgnoreCase);
    }

    private static bool ShipNamesMatch(string? left, string? right)
    {
        return ShipIdentityCanonicalizer.ComparisonKey(left) ==
               ShipIdentityCanonicalizer.ComparisonKey(right);
    }

    private static void ClearShipInference(FleetPlayer player, string evidence)
    {
        player.Ship = "Unknown";
        player.ShipConfidence = "None";
        player.ShipEvidence = evidence;
        player.ShipInferenceScore = 0;
        player.ShipInstanceId = null;
        player.ShipChannelMembershipConfirmed = false;
        player.LastShipEvidenceAt = null;
        player.LastShipScoreUpdatedAt = null;
        player.LastShipInstanceSeenAt = null;
        player.LastShipChannelEventAt = null;
        player.LastControlSeatLeftAt = null;
    }

    private static void ClearActiveStateForOffline(FleetPlayer player)
    {
        if (!player.Ship.Equals("Unknown", StringComparison.OrdinalIgnoreCase))
        {
            player.LastKnownShip = player.Ship;
            player.LastKnownShipInstanceId = player.ShipInstanceId;
        }

        if (!player.Location.Equals("Unknown", StringComparison.OrdinalIgnoreCase))
        {
            player.LastKnownLocation = player.Location;
        }

        ClearShipInference(player, "Player offline");
        ClearLocationInference(player, "Player offline");
        ClearNavigationJourney(player);
        player.LastQuantumArrivalAt = null;
    }

    private static void RestoreLowConfidenceState(FleetPlayer player, DateTimeOffset timestamp)
    {
        if (player.Ship.Equals("Unknown", StringComparison.OrdinalIgnoreCase) &&
            !string.IsNullOrWhiteSpace(player.LastKnownShip))
        {
            player.Ship = player.LastKnownShip;
            player.ShipInstanceId = player.LastKnownShipInstanceId;
            player.ShipInferenceScore = 15;
            player.ShipConfidence = "Low";
            player.ShipEvidence = "Restored after reconnect";
            player.LastShipEvidenceAt = timestamp;
            player.LastShipScoreUpdatedAt = timestamp;
        }

    }

    private static void ClearLocationInference(FleetPlayer player, string evidence)
    {
        player.Location = "Unknown";
        player.LocationConfidence = "None";
        player.LocationEvidence = evidence;
        player.LocationInferenceScore = 0;
        player.LastLocationEvidenceAt = null;
        player.LastLocationScoreUpdatedAt = null;
        player.ConfirmedLocationCode = "Unknown";
        player.ConfirmedAtUtc = null;
        player.ArrivalPendingConfirmation = false;
        player.ArrivalTargetCode = null;
        player.IsLocationStale = false;
    }

    private static void DecayShipInference(FleetPlayer player, DateTimeOffset now)
    {
        if (player.Ship.Equals("Unknown", StringComparison.OrdinalIgnoreCase))
        {
            return;
        }

        if (player.ShipChannelMembershipConfirmed)
        {
            player.ShipInferenceScore = MaxShipInferenceScore;
            player.ShipConfidence = "High";
            player.LastShipScoreUpdatedAt = now;
            return;
        }

        if (player.LastShipScoreUpdatedAt is not null)
        {
            var elapsedMinutes = Math.Max(0, (now - player.LastShipScoreUpdatedAt.Value).TotalMinutes);
            var decayPerMinute = ShipScoreDecayPerMinute +
                                 (player.LastControlSeatLeftAt is not null ? PostControlSeatExitDecayPerMinute : 0);
            var decayedScore = player.ShipInferenceScore - (int)Math.Floor(elapsedMinutes * decayPerMinute);
            player.ShipInferenceScore = Math.Max(0, decayedScore);
            player.LastShipScoreUpdatedAt = now;
        }

        var hasRecentSameShipSignal = player.LastShipInstanceSeenAt is not null &&
                                      now - player.LastShipInstanceSeenAt.Value < ShipEvidenceDecayWindow;

        if (player.LastControlSeatLeftAt is not null &&
            now - player.LastControlSeatLeftAt.Value >= ShipEvidenceDecayWindow &&
            !hasRecentSameShipSignal)
        {
            player.ShipInferenceScore = Math.Min(player.ShipInferenceScore, 44);
            player.ShipInferenceScore = Math.Max(player.ShipInferenceScore, 15);
            player.ShipEvidence = string.IsNullOrWhiteSpace(player.ShipInstanceId)
                ? "Left control seat over 5 minutes ago"
                : $"Ship ID {player.ShipInstanceId} not seen for 5+ minutes after leaving control seat";
        }

        player.ShipConfidence = GetShipConfidence(player);
        if (player.ShipConfidence.Equals("None", StringComparison.OrdinalIgnoreCase))
        {
            player.Ship = "Unknown";
            player.ShipEvidence = "Ship evidence expired";
            player.ShipInstanceId = null;
        }
    }

    private static string GetShipConfidence(FleetPlayer player)
    {
        if (player.ShipInferenceScore >= 80)
        {
            return "High";
        }

        if (player.ShipInferenceScore >= 45)
        {
            return "Medium";
        }

        if (player.ShipInferenceScore >= 15)
        {
            return "Low";
        }

        return "None";
    }

    private static void AddLocationEvidence(
        FleetPlayer player,
        string? location,
        int score,
        string evidence,
        DateTimeOffset timestamp)
    {
        if (string.IsNullOrWhiteSpace(location) || score <= 0)
        {
            return;
        }

        DecayLocationInference(player, timestamp);

        var isDifferentLocation = !player.Location.Equals("Unknown", StringComparison.OrdinalIgnoreCase) &&
                                  !player.Location.Equals(location, StringComparison.OrdinalIgnoreCase);

        if (isDifferentLocation)
        {
            player.LocationInferenceScore = 0;
        }

        player.Location = location;
        player.LocationInferenceScore = Math.Min(MaxLocationInferenceScore, player.LocationInferenceScore + score);
        player.LocationConfidence = GetLocationConfidence(player);
        player.LocationEvidence = evidence;
        player.LastLocationEvidenceAt = timestamp;
        player.LastLocationScoreUpdatedAt = timestamp;
        player.ConfirmedLocationCode = location;
        player.ConfirmedAtUtc = timestamp;
        player.IsLocationStale = false;
        if (player.ArrivalPendingConfirmation)
        {
            player.ArrivalPendingConfirmation = false;
            player.ArrivalTargetCode = null;
            ClearNavigationJourney(player);
        }
    }

    private static void DecayLocationInference(FleetPlayer player, DateTimeOffset now)
    {
        if (player.Location.Equals("Unknown", StringComparison.OrdinalIgnoreCase) ||
            player.LastLocationScoreUpdatedAt is null)
        {
            return;
        }

        var elapsedMinutes = Math.Max(0, (now - player.LastLocationScoreUpdatedAt.Value).TotalMinutes);
        var decayedScore = player.LocationInferenceScore - (int)Math.Floor(elapsedMinutes * LocationScoreDecayPerMinute);
        player.LocationInferenceScore = Math.Max(0, decayedScore);
        player.LastLocationScoreUpdatedAt = now;
        player.LocationConfidence = GetLocationConfidence(player);

        if (player.LocationConfidence.Equals("None", StringComparison.OrdinalIgnoreCase))
        {
            // Game.log has no reliable leave-region event. Preserve the last confirmed
            // location and lower only its trust state until an explicit session boundary.
            player.LocationConfidence = "Low";
            player.IsLocationStale = true;
        }
    }

    private static string GetLocationConfidence(FleetPlayer player)
    {
        if (player.LocationInferenceScore >= 80)
        {
            return "High";
        }

        if (player.LocationInferenceScore >= 45)
        {
            return "Medium";
        }

        if (player.LocationInferenceScore >= 15)
        {
            return "Low";
        }

        return "None";
    }

    private enum ShipEvidenceStrength
    {
        Weak,
        Strong,
        Channel
    }
}
