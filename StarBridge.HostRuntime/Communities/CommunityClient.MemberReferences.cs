namespace StarBridge.HostRuntime.Communities;

internal sealed partial class CommunityClient
{
    // Retained identities are addresses, never authorization. Only publication
    // after a fully validated read writes the separate five-minute lease table.
    private readonly record struct MemberIdentity(string MemberId, string Code, string Scope);
    private sealed record RetainedMemberReference(MemberIdentity Identity, string Reference, DateTimeOffset Until);
    private const int MemberReferenceLimit = 10000;
    private static readonly TimeSpan MemberReferenceRetention = TimeSpan.FromHours(24);
    private readonly Dictionary<MemberIdentity, LinkedListNode<RetainedMemberReference>> _memberReferences = new();
    private readonly LinkedList<RetainedMemberReference> _memberReferenceOrder = new();
    // Retention-only test clock; authorization clocks and production defaults stay unchanged.
    internal Func<DateTimeOffset> MemberReferenceUtcNow { private get; set; } = () => DateTimeOffset.UtcNow;

    private string? MemberReferenceFor(string memberId, string code, string scope, bool create = true, string? preferredReference = null)
    {
        lock (_workspaceMemberGate)
        {
            var now = MemberReferenceUtcNow();
            while (_memberReferenceOrder.First is { } old && old.Value.Until <= now)
                RemoveMemberReference(old);
            var identity = new MemberIdentity(memberId, code, scope);
            if (_memberReferences.TryGetValue(identity, out var retained))
            {
                if (retained.Value.Until > now)
                {
                    if (create)
                    {
                        // Protect identities already used earlier in the current batch.
                        // Renew and move together so queue order remains expiry order.
                        retained.Value = retained.Value with { Until = now + MemberReferenceRetention };
                        _memberReferenceOrder.Remove(retained);
                        _memberReferenceOrder.AddLast(retained);
                    }
                    return retained.Value.Reference;
                }
                RemoveMemberReference(retained);
            }
            if (!create) return null;
            while (_memberReferences.Count >= MemberReferenceLimit)
                RemoveMemberReference(_memberReferenceOrder.First!);
            // A retained official message may already address this exact identity.
            // Reusing its address does not grant a lease; publication still does.
            var reference = preferredReference ?? Guid.NewGuid().ToString("N");
            _memberReferences.Add(identity, _memberReferenceOrder.AddLast(new RetainedMemberReference(identity, reference, now + MemberReferenceRetention)));
            return reference;
        }
    }

    private void PublishMemberTargets(IEnumerable<KeyValuePair<string, MemberTarget>> members)
    {
        lock (_workspaceMemberGate)
        {
            var pending = members.ToArray();
            var now = DateTimeOffset.UtcNow;
            foreach (var old in _memberTargets.Where(pair => pair.Value.Expires <= now).ToArray())
                _memberTargets.TryRemove(old.Key, out _);
            if (_memberTargets.Count + pending.Select(pair => pair.Key).Distinct().Count(reference => !_memberTargets.ContainsKey(reference)) > MemberReferenceLimit)
                throw new Account.AccountBridgeHostException("communities.refreshRequired");
            // Check that the whole batch still maps each identity to the same reference before renewing.
            // This does not reject an old batch if the same identity has re-adopted the same reference.
            foreach (var pair in pending)
                if (!_memberReferences.TryGetValue(new(pair.Value.MemberId, pair.Value.Code, pair.Value.Scope), out var retained) || retained.Value.Reference != pair.Key)
                    throw new Account.AccountBridgeHostException("communities.refreshRequired");
            var until = MemberReferenceUtcNow() + MemberReferenceRetention;
            foreach (var pair in pending)
            {
                var retained = _memberReferences[new(pair.Value.MemberId, pair.Value.Code, pair.Value.Scope)];
                retained.Value = retained.Value with { Until = until };
                _memberReferenceOrder.Remove(retained);
                _memberReferenceOrder.AddLast(retained);
                _memberTargets[pair.Key] = pair.Value;
            }
        }
    }

    private void RemoveMemberReference(LinkedListNode<RetainedMemberReference> node)
    {
        _memberReferences.Remove(node.Value.Identity);
        _memberReferenceOrder.Remove(node);
        // Count/retention eviction also retires any corresponding lease.
        _memberTargets.TryRemove(node.Value.Reference, out _);
    }

    private void ClearMemberReferences(string? scope = null, string? code = null)
    {
        lock (_workspaceMemberGate)
        {
            if (scope is null)
            {
                _memberReferences.Clear();
                _memberReferenceOrder.Clear();
                _memberTargets.Clear();
                return;
            }
            foreach (var node in _memberReferences.Where(pair => pair.Key.Scope == scope &&
                         pair.Key.Code.Equals(code, StringComparison.OrdinalIgnoreCase)).Select(pair => pair.Value).ToArray())
                RemoveMemberReference(node);
            foreach (var pair in _memberTargets.Where(pair => pair.Value.Scope == scope &&
                         pair.Value.Code.Equals(code, StringComparison.OrdinalIgnoreCase)).ToArray())
                _memberTargets.TryRemove(pair.Key, out _);
        }
    }
}
