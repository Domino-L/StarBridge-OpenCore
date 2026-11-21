using StarBridge.HostRuntime.Notifications;

namespace StarBridge.HostRuntime.Communities;

internal sealed partial class CommunityClient
{
    private readonly object _notificationMembershipGate = new();
    private readonly Dictionary<string, (string? Source, long Epoch)> _notificationMemberships = new(StringComparer.Ordinal);
    internal event Action<string, string?>? OfficialNotificationMembershipObserved;

    // The current communication context has no server membership epoch/joinedAt.
    // This counter only detects races inside a read. Durable membership generations
    // belong to AnnouncementObservationStore, never to a process or relay scope.
    internal string ObserveOfficialNotificationMembership(string scope, string? source, out bool changed)
    {
        string identity;
        lock (_notificationMembershipGate) {
            var known = _notificationMemberships.TryGetValue(scope, out var prior);
            changed = known && prior.Source != source;
            if (!known || changed) {
                if (!known && _notificationMemberships.Count >= 128) _notificationMemberships.Remove(_notificationMemberships.Keys.First());
                prior = (source, known ? checked(prior.Epoch + 1) : 0);
                _notificationMemberships[scope] = prior;
            }
            identity = source + ":membership:" + prior.Epoch;
        }
        // Publish each confirmed context even if the enclosing multi-domain read
        // later fails. No transport operation or callback runs under this lock.
        OfficialNotificationMembershipObserved?.Invoke(scope, source);
        return identity;
    }

    internal (bool Known, string? Source) OfficialNotificationMembership(string scope)
    {
        lock (_notificationMembershipGate)
            return _notificationMemberships.TryGetValue(scope, out var value) ? (true, value.Source) : (false, null);
    }
}
