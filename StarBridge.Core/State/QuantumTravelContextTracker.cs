using StarBridge.Core.Events;

namespace StarBridge.Core.State;

public sealed class QuantumTravelContextTracker
{
    private static readonly TimeSpan MaximumContextAge = TimeSpan.FromHours(1);
    private QuantumTravelContext? _activeContext;

    public FleetEvent Resolve(FleetEvent fleetEvent)
    {
        if (fleetEvent.Type == FleetEventType.PlayerNavigationTargetChanged)
        {
            var observedContext = ObserveNavigationTarget(fleetEvent);
            return observedContext is null
                ? fleetEvent
                : fleetEvent with
                {
                    NavigationTargetSelectedAt = observedContext.SelectedAt,
                    NavigationOriginLocation = observedContext.OriginLocation
                };
        }

        if (fleetEvent.Type != FleetEventType.PlayerLocationChanged ||
            !IsQuantumArrivalPlaceholder(fleetEvent.Location))
        {
            return fleetEvent;
        }

        var context = _activeContext;
        _activeContext = null;
        if (context is null ||
            !IsContextCurrent(context, fleetEvent) ||
            !ShipContextMatches(context, fleetEvent))
        {
            return fleetEvent;
        }

        return fleetEvent with
        {
            NavigationTarget = context.Target,
            NavigationTargetSelectedAt = context.SelectedAt,
            NavigationOriginLocation = context.OriginLocation
        };
    }

    public void Reset()
    {
        _activeContext = null;
    }

    private QuantumTravelContext? ObserveNavigationTarget(FleetEvent fleetEvent)
    {
        if (!HasKnownTarget(fleetEvent.NavigationTarget))
        {
            return null;
        }

        var target = fleetEvent.NavigationTarget!.Trim();
        if (_activeContext is not null &&
            _activeContext.Target.Equals(target, StringComparison.OrdinalIgnoreCase) &&
            ShipContextMatches(_activeContext, fleetEvent))
        {
            if (string.IsNullOrWhiteSpace(_activeContext.OriginLocation) &&
                HasKnownTarget(fleetEvent.Location))
            {
                _activeContext = _activeContext with { OriginLocation = fleetEvent.Location!.Trim() };
            }

            return _activeContext;
        }

        _activeContext = new QuantumTravelContext(
            target,
            fleetEvent.Timestamp ?? DateTimeOffset.Now,
            fleetEvent.Ship,
            fleetEvent.ShipInstanceId,
            HasKnownTarget(fleetEvent.Location) ? fleetEvent.Location!.Trim() : null);
        return _activeContext;
    }

    private static bool IsContextCurrent(QuantumTravelContext context, FleetEvent arrival)
    {
        var elapsed = (arrival.Timestamp ?? DateTimeOffset.Now) - context.SelectedAt;
        return elapsed >= TimeSpan.FromSeconds(-5) && elapsed <= MaximumContextAge;
    }

    private static bool ShipContextMatches(QuantumTravelContext context, FleetEvent arrival)
    {
        if (!string.IsNullOrWhiteSpace(context.ShipInstanceId) &&
            !string.IsNullOrWhiteSpace(arrival.ShipInstanceId))
        {
            return context.ShipInstanceId.Equals(arrival.ShipInstanceId, StringComparison.OrdinalIgnoreCase);
        }

        if (!string.IsNullOrWhiteSpace(context.Ship) &&
            !string.IsNullOrWhiteSpace(arrival.Ship))
        {
            return context.Ship.Equals(arrival.Ship, StringComparison.OrdinalIgnoreCase);
        }

        return true;
    }

    private static bool IsQuantumArrivalPlaceholder(string? location) =>
        location?.Equals("Arrived - awaiting location confirmation", StringComparison.OrdinalIgnoreCase) == true;

    private static bool HasKnownTarget(string? target) =>
        !string.IsNullOrWhiteSpace(target) &&
        !target.Equals("None", StringComparison.OrdinalIgnoreCase) &&
        !target.Equals("Unknown", StringComparison.OrdinalIgnoreCase);

    private sealed record QuantumTravelContext(
        string Target,
        DateTimeOffset SelectedAt,
        string? Ship,
        string? ShipInstanceId,
        string? OriginLocation);
}
