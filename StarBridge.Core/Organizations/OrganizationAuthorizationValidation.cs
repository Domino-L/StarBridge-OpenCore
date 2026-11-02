namespace StarBridge.Core.Organizations;

public static class OrganizationAuthorizationValidation
{
    // Structure only: this never observes members or root eligibility and grants no authority.
    public static OrganizationAuthorizationDecision ValidateSnapshotShape(OrganizationAuthorizationSnapshot snapshot)
    {
        if (!Enum.IsDefined(snapshot.ReadState) || snapshot.Revision < 0)
            return Decision(OrganizationAuthorizationOutcome.Invalid, "invalidSnapshot");
        if (snapshot.ReadState == OrganizationPolicyReadState.Unavailable)
            return Decision(OrganizationAuthorizationOutcome.Unavailable, "policyUnavailable");
        if (!ValidScope(snapshot.Scope))
            return Decision(OrganizationAuthorizationOutcome.Invalid, "scopeMismatch");
        if (!OrganizationRankPermissions.Valid(snapshot.RankPermissions))
            return Decision(OrganizationAuthorizationOutcome.Invalid, "invalidRankPermissions");
        var activations = snapshot.Activations ?? [];
        if (activations.Any(a => !Text(a.Id) || a.Version <= 0 || !Text(a.Subject) ||
            !Text(a.MembershipEpoch) || !Text(a.Basis) || !Text(a.ProofDefinition)) ||
            activations.Select(a => a.Id).Distinct(StringComparer.Ordinal).Count() != activations.Count ||
            activations.Where(a => !a.Revoked && a.ProofDefinition != OrganizationRankAuthority.Definition).Count() > 1 ||
            activations.Where(a => !a.Revoked && a.ProofDefinition == OrganizationRankAuthority.Definition)
                .GroupBy(a => a.Subject, StringComparer.Ordinal).Any(g => g.Count() > 1))
            return Decision(OrganizationAuthorizationOutcome.Invalid, "invalidActivationGraph");
        return PolicyGraph(snapshot);
    }

    internal static OrganizationAuthorizationDecision ContextState(OrganizationAuthorizationContext context)
    {
        var shape = ValidateSnapshotShape(context.Policy);
        if (shape.Outcome != OrganizationAuthorizationOutcome.Allowed) return shape;
        if (context.Now.Offset != TimeSpan.Zero || context.Actor.Scope != context.Policy.Scope)
            return Decision(OrganizationAuthorizationOutcome.Invalid, "scopeMismatch");
        var members = (context.RequiredMembers ?? []).Append(context.Actor).ToArray();
        if (members.Select(m => m.Subject).Distinct(StringComparer.Ordinal).Count() != members.Length ||
            members.Any(m => m.Scope != context.Policy.Scope || !Text(m.Subject)))
            return Decision(OrganizationAuthorizationOutcome.Invalid, "invalidPolicyGraph");
        var roots = context.RequiredRoots ?? [];
        if (roots.Select(r => r.Subject).Distinct(StringComparer.Ordinal).Count() != roots.Count ||
            roots.Any(r => r.Subject == context.Actor.Subject))
            return Decision(OrganizationAuthorizationOutcome.Invalid, "invalidRootObservations");
        return Membership(context.Actor, context.Actor.Subject, context.Actor.MembershipEpoch, context);
    }

    internal static OrganizationAuthorizationDecision Membership(OrganizationMembershipEvidence member,
        string subject, string epoch, OrganizationAuthorizationContext context)
    {
        if (!Enum.IsDefined(member.State) || !Text(member.Subject) || member.Subject != subject ||
            member.Scope != context.Policy.Scope)
            return Decision(OrganizationAuthorizationOutcome.Invalid, "membershipBindingInvalid");
        if (member.State == OrganizationMembershipState.Unavailable)
            return Decision(OrganizationAuthorizationOutcome.Unavailable, "membershipUnavailable");
        if (member.State == OrganizationMembershipState.NotCurrent)
            return Decision(OrganizationAuthorizationOutcome.Denied, "notCurrentMember");
        if (!Text(member.MembershipEpoch) || !Text(member.SourceDefinition))
            return Decision(OrganizationAuthorizationOutcome.Invalid, "membershipEvidenceInvalid");
        if (member.MembershipEpoch != epoch)
            return Decision(OrganizationAuthorizationOutcome.Denied, "membershipEpochChanged");
        return Fresh(member.ObservedAt, member.ValidUntil, context.Now, "membership");
    }

    internal static OrganizationAuthorizationDecision Root(OrganizationRootEligibilityEvidence root,
        OrganizationMembershipEvidence member, OrganizationAuthorizationContext context)
    {
        if (root.Reason == OrganizationRankAuthority.StaleReason)
            return Decision(OrganizationAuthorizationOutcome.Unavailable, OrganizationRankAuthority.StaleReason);
        if (!Enum.IsDefined(root.State))
            return Decision(OrganizationAuthorizationOutcome.Invalid, "rootEvidenceInvalid");
        if (root.State is OrganizationRootEligibilityState.Unconfigured or OrganizationRootEligibilityState.Unavailable)
            return Decision(OrganizationAuthorizationOutcome.Unavailable, "rootAuthorityUnavailable");
        if (root.State == OrganizationRootEligibilityState.Ineligible)
            return Decision(OrganizationAuthorizationOutcome.Denied, "rootNotEligible");
        if (!Text(root.Basis) || !Text(root.Subject) || !Text(root.MembershipEpoch) ||
            !Text(root.ProofDefinition) || !root.ObservedAt.HasValue || !root.ValidUntil.HasValue ||
            root.Scope != context.Policy.Scope)
            return Decision(OrganizationAuthorizationOutcome.Invalid, "rootEvidenceInvalid");
        if (root.Subject != member.Subject || root.MembershipEpoch != member.MembershipEpoch)
            return Decision(OrganizationAuthorizationOutcome.Denied, "rootBindingChanged");
        if (root.ProofDefinition == OrganizationRankAuthority.Definition &&
            (root.Basis != OrganizationRankAuthority.Basis || root.RankValue != 1))
            return Decision(OrganizationAuthorizationOutcome.Denied, "rootNotEligible");
        return Fresh(root.ObservedAt.Value, root.ValidUntil.Value, context.Now, "rootAuthority");
    }

    internal static OrganizationAuthorizationDecision Fresh(DateTimeOffset observed, DateTimeOffset until,
        DateTimeOffset now, string kind)
    {
        if (observed.Offset != TimeSpan.Zero || until.Offset != TimeSpan.Zero || until <= observed || observed > now)
            return Decision(OrganizationAuthorizationOutcome.Invalid, kind + "TimeInvalid");
        return until <= now ? Decision(OrganizationAuthorizationOutcome.Unavailable, kind + "Expired") :
            Decision(OrganizationAuthorizationOutcome.Allowed, "current");
    }

    internal static bool ValidScope(OrganizationAuthorizationScope? scope) => scope is not null &&
        Text(scope.AuthorityNamespace) && scope.OrganizationId > 0 && Text(scope.Sid);
    internal static bool Text(string? value) => !string.IsNullOrWhiteSpace(value) &&
        value.Length <= 256 && value == value.Trim() && !value.Any(char.IsControl);
    internal static OrganizationAuthorizationDecision Decision(OrganizationAuthorizationOutcome outcome, string reason) => new(outcome, reason);

    internal static bool PermissionsValid(IReadOnlyList<OrganizationCapabilityPermission> permissions) =>
        permissions.All(p => OrganizationCapabilityCatalog.IsSupported(p.Capability) && (!p.CanDelegate || p.CanUse)) &&
        permissions.Select(p => p.Capability).Distinct(StringComparer.Ordinal).Count() == permissions.Count;

    private static OrganizationAuthorizationDecision PolicyGraph(OrganizationAuthorizationSnapshot snapshot)
    {
        var roles = snapshot.Roles ?? [];
        var grants = snapshot.Grants ?? [];
        var roots = snapshot.Activations ?? [];
        if (roles.Select(r => r.Key).Distinct(StringComparer.Ordinal).Count() != roles.Count ||
            roles.Any(r => !Text(r.Key) || r.Scope != snapshot.Scope || r.PermissionVersion <= 0 ||
                r.MetadataRevision < 0 || !PermissionsValid(r.Permissions)) ||
            grants.Select(g => g.Id).Distinct(StringComparer.Ordinal).Count() != grants.Count)
            return Decision(OrganizationAuthorizationOutcome.Invalid, "invalidPolicyGraph");
        foreach (var grant in grants)
        {
            var parented = grant.ParentGrantId is not null;
            if (!Text(grant.Id) || grant.Version <= 0 || grant.Scope != snapshot.Scope ||
                !Text(grant.Subject) || !Text(grant.MembershipEpoch) || grant.RolePermissionVersion <= 0 ||
                !roles.Any(r => r.Key == grant.RoleKey) || !PermissionsValid(grant.Ceiling) ||
                parented == (grant.RootActivationId is not null) ||
                parented != grant.ParentGrantVersion.HasValue ||
                (!parented) != grant.RootActivationVersion.HasValue ||
                (parented && (grant.ParentGrantVersion <= 0 || !grants.Any(g => g.Id == grant.ParentGrantId))) ||
                (!parented && (grant.RootActivationVersion <= 0 || !roots.Any(a => a.Id == grant.RootActivationId))) ||
                grant.ExpiresAt is { Offset: var offset } && offset != TimeSpan.Zero)
                return Decision(OrganizationAuthorizationOutcome.Invalid, "invalidGrantGraph");
        }
        foreach (var grant in grants)
        {
            var visited = new HashSet<string>(StringComparer.Ordinal);
            var current = grant;
            while (true)
            {
                if (!visited.Add(current.Id)) return Decision(OrganizationAuthorizationOutcome.Invalid, "cyclicGrantGraph");
                if (current.ParentGrantId is null) break;
                current = grants.Single(g => g.Id == current.ParentGrantId);
            }
        }
        return Decision(OrganizationAuthorizationOutcome.Allowed, "validPolicyGraph");
    }

    public static OrganizationPolicyChangeValidation ValidateGrant(OrganizationAuthorizationContext context,
        long expectedRevision, OrganizationGrant proposed, OrganizationMembershipEvidence target)
    {
        var state = ChangeState(context, expectedRevision);
        if (state.Outcome != OrganizationAuthorizationOutcome.Allowed) return Change(state, expectedRevision);
        if ((context.Policy.Grants ?? []).Any(g => g.Id == proposed.Id))
            return Change(Decision(OrganizationAuthorizationOutcome.Conflict, "grantAlreadyExists"), expectedRevision);
        if (proposed.Subject != target.Subject || proposed.Scope != context.Policy.Scope || proposed.Version != 1)
            return Change(Decision(OrganizationAuthorizationOutcome.Invalid, "grantTargetInvalid"), expectedRevision);
        if (proposed.MembershipEpoch != target.MembershipEpoch)
            return Change(Decision(OrganizationAuthorizationOutcome.Denied, "targetEpochChanged"), expectedRevision);
        var candidate = context with { Policy = context.Policy with { Grants = [.. context.Policy.Grants ?? [], proposed] } };
        state = ValidateSnapshotShape(candidate.Policy);
        if (state.Outcome != OrganizationAuthorizationOutcome.Allowed) return Change(state, expectedRevision);
        var role = (context.Policy.Roles ?? []).Single(r => r.Key == proposed.RoleKey);
        if (!role.Enabled || role.PermissionVersion != proposed.RolePermissionVersion ||
            proposed.ExpiresAt is { } until && until <= context.Now)
            return Change(Decision(OrganizationAuthorizationOutcome.Denied, "grantBindingNotCurrent"), expectedRevision);
        if (proposed.Ceiling.Any(p => !role.Permissions.Any(r => r.Capability == p.Capability && r.CanUse && (!p.CanDelegate || r.CanDelegate))))
            return Change(Decision(OrganizationAuthorizationOutcome.Invalid, "grantExceedsTemplate"), expectedRevision);
        if (proposed.ParentGrantId is { } parentId)
        {
            if ((context.Policy.Grants ?? []).Single(g => g.Id == parentId).Version != proposed.ParentGrantVersion)
                return Change(Decision(OrganizationAuthorizationOutcome.Conflict, "delegationParentChanged"), expectedRevision);
        }
        else
        {
            var root = (context.Policy.Activations ?? []).Single(a => a.Id == proposed.RootActivationId);
            if (root.Version != proposed.RootActivationVersion || root.Subject != context.Actor.Subject ||
                root.MembershipEpoch != context.Actor.MembershipEpoch || root.Revoked ||
                context.Root.State == OrganizationRootEligibilityState.Eligible &&
                (root.Basis != context.Root.Basis || root.ProofDefinition != context.Root.ProofDefinition))
                return Change(Decision(OrganizationAuthorizationOutcome.Denied, "rootProvenanceNotOwned"), expectedRevision);
        }
        state = OrganizationAuthorizationPolicy.EvaluateDelegation(context, target, proposed.Ceiling, proposed.ParentGrantId);
        return Change(state, expectedRevision);
    }

    public static OrganizationPolicyChangeValidation ValidateRevoke(OrganizationAuthorizationContext context,
        long expectedRevision, string grantId)
    {
        var state = ChangeState(context, expectedRevision);
        if (state.Outcome != OrganizationAuthorizationOutcome.Allowed) return Change(state, expectedRevision);
        var grant = (context.Policy.Grants ?? []).SingleOrDefault(g => g.Id == grantId);
        if (grant is null) return Change(Decision(OrganizationAuthorizationOutcome.Invalid, "grantMissing"), expectedRevision);
        state = CanAffectGrant(context, grant);
        return Change(state, expectedRevision, state.Outcome == OrganizationAuthorizationOutcome.Allowed ? Descendants(context, [grant.Id]) : []);
    }

    public static OrganizationPolicyChangeValidation ValidateRoleChange(OrganizationAuthorizationContext context,
        long expectedRevision, OrganizationRoleDefinition proposed)
    {
        var state = ChangeState(context, expectedRevision);
        if (state.Outcome != OrganizationAuthorizationOutcome.Allowed) return Change(state, expectedRevision);
        if (!Text(proposed.Key) || proposed.Scope != context.Policy.Scope || proposed.PermissionVersion <= 0 ||
            proposed.MetadataRevision < 0 || !PermissionsValid(proposed.Permissions))
            return Change(Decision(OrganizationAuthorizationOutcome.Invalid, "roleDraftInvalid"), expectedRevision);
        var old = (context.Policy.Roles ?? []).SingleOrDefault(r => r.Key == proposed.Key);
        var authorizationChanged = old is null || old.Enabled != proposed.Enabled || !SamePermissions(old.Permissions, proposed.Permissions);
        if (old is null ? proposed.PermissionVersion != 1 || proposed.MetadataRevision is < 0 or > 1 :
            proposed.PermissionVersion != (long)old.PermissionVersion + (authorizationChanged ? 1 : 0) ||
            proposed.MetadataRevision < old.MetadataRevision || proposed.MetadataRevision - old.MetadataRevision > 1 ||
            !authorizationChanged && proposed.MetadataRevision == old.MetadataRevision)
            return Change(Decision(OrganizationAuthorizationOutcome.Invalid, "roleVersionInvalid"), expectedRevision);
        var affected = authorizationChanged ? Descendants(context, (context.Policy.Grants ?? []).Where(g => g.RoleKey == proposed.Key).Select(g => g.Id)) : [];
        var rights = authorizationChanged ? (old?.Permissions ?? []).Concat(proposed.Enabled ? proposed.Permissions : [])
            .Where(p => p.CanUse).Select(p => p.Capability).Distinct(StringComparer.Ordinal)
            .Select(id => new OrganizationCapabilityPermission(id, true, true)).ToArray() : [];
        state = EvaluateRoleChangeAuthority(context, rights, affected);
        if (state.Outcome != OrganizationAuthorizationOutcome.Allowed) return Change(state, expectedRevision);
        return Change(Decision(OrganizationAuthorizationOutcome.Allowed, authorizationChanged ? "rolePermissionRevalidationRequired" : "roleMetadataChange"),
            expectedRevision, affected, authorizationChanged && affected.Count > 0);
    }

    // Authority only: callers still must run full ValidateRoleChange for a new operation.
    public static OrganizationAuthorizationDecision EvaluateRoleChangeAuthority(OrganizationAuthorizationContext context,
        IReadOnlyList<OrganizationCapabilityPermission> requiredRights, IReadOnlyList<string> affectedGrantIds)
    {
        var state = ContextState(context);
        if (state.Outcome != OrganizationAuthorizationOutcome.Allowed) return state;
        var grants = context.Policy.Grants ?? [];
        if (requiredRights is null || affectedGrantIds is null ||
            requiredRights.Count > OrganizationCapabilityCatalog.Implemented.Count || affectedGrantIds.Count > grants.Count ||
            requiredRights.Any(p => p is null || !p.CanUse || !p.CanDelegate) || !PermissionsValid(requiredRights) ||
            affectedGrantIds.Distinct(StringComparer.Ordinal).Count() != affectedGrantIds.Count ||
            affectedGrantIds.Any(id => !Text(id) || !grants.Any(g => g.Id == id)))
            return Decision(OrganizationAuthorizationOutcome.Invalid, "roleAuthorityRequestInvalid");
        state = Manage(context);
        if (state.Outcome != OrganizationAuthorizationOutcome.Allowed) return state;
        if (requiredRights.Count > 0)
        {
            state = CanAssign(context, requiredRights);
            if (state.Outcome != OrganizationAuthorizationOutcome.Allowed) return state;
        }
        foreach (var id in affectedGrantIds)
        {
            state = CanAffectGrant(context, grants.Single(g => g.Id == id));
            if (state.Outcome != OrganizationAuthorizationOutcome.Allowed) return state;
        }
        return Decision(OrganizationAuthorizationOutcome.Allowed, "roleAuthorityCurrent");
    }

    private static OrganizationAuthorizationDecision ChangeState(OrganizationAuthorizationContext context, long expected)
    {
        var state = ContextState(context);
        if (state.Outcome != OrganizationAuthorizationOutcome.Allowed) return state;
        return expected != context.Policy.Revision ? Decision(OrganizationAuthorizationOutcome.Conflict, "policyRevisionChanged") : state;
    }

    private static OrganizationAuthorizationDecision Manage(OrganizationAuthorizationContext context)
    {
        if (context.Root.ProofDefinition == OrganizationRankAuthority.Definition)
            return OrganizationAuthorizationPolicy.EvaluateManagement(context);
        var root = OrganizationAuthorizationPolicy.EvaluateRootControl(context, OrganizationRootControl.Delegate);
        if (root.Outcome == OrganizationAuthorizationOutcome.Allowed) return root;
        var use = OrganizationAuthorizationPolicy.EvaluateUse(context, OrganizationCapabilityCatalog.ManageRoles);
        return use.Outcome == OrganizationAuthorizationOutcome.Denied && root.Outcome == OrganizationAuthorizationOutcome.Unavailable ? root : use;
    }

    private static OrganizationAuthorizationDecision CanAssign(OrganizationAuthorizationContext context, IReadOnlyList<OrganizationCapabilityPermission> requested)
    {
        var root = OrganizationAuthorizationPolicy.EvaluateDelegation(context, context.Actor, requested);
        if (root.Outcome == OrganizationAuthorizationOutcome.Allowed) return root;
        foreach (var permission in requested)
        {
            var result = root;
            foreach (var grant in (context.Policy.Grants ?? []).Where(g => g.Subject == context.Actor.Subject))
            {
                var decision = OrganizationAuthorizationPolicy.EvaluateDelegation(context, context.Actor, [permission], grant.Id);
                if (decision.Outcome == OrganizationAuthorizationOutcome.Allowed) { result = decision; break; }
                if (decision.Outcome == OrganizationAuthorizationOutcome.Unavailable) result = decision;
            }
            if (result.Outcome != OrganizationAuthorizationOutcome.Allowed) return result;
        }
        return Decision(OrganizationAuthorizationOutcome.Allowed, "capabilitiesDelegable");
    }

    private static OrganizationAuthorizationDecision CanAffectGrant(OrganizationAuthorizationContext context, OrganizationGrant affected)
    {
        if (context.Root.ProofDefinition == OrganizationRankAuthority.Definition)
            return OrganizationAuthorizationPolicy.EvaluateManagement(context);
        var root = OrganizationAuthorizationPolicy.EvaluateRootControl(context, OrganizationRootControl.Delegate);
        if (root.Outcome == OrganizationAuthorizationOutcome.Allowed) return root;
        var current = affected;
        while (current.ParentGrantId is { } id)
        {
            var parent = (context.Policy.Grants ?? []).Single(g => g.Id == id);
            if (parent.Subject == context.Actor.Subject)
                return OrganizationAuthorizationPolicy.EvaluateDelegation(context, context.Actor,
                    affected.Ceiling.Where(p => p.CanUse).ToArray(), parent.Id);
            current = parent;
        }
        return root.Outcome == OrganizationAuthorizationOutcome.Unavailable ? root :
            Decision(OrganizationAuthorizationOutcome.Denied, "grantProvenanceNotOwned");
    }

    private static bool SamePermissions(IReadOnlyList<OrganizationCapabilityPermission> left, IReadOnlyList<OrganizationCapabilityPermission> right) =>
        left.Count == right.Count && left.All(p => right.Contains(p));
    private static IReadOnlyList<string> Descendants(OrganizationAuthorizationContext context, IEnumerable<string> seeds)
    {
        var affected = seeds.ToHashSet(StringComparer.Ordinal);
        while (true)
        {
            var count = affected.Count;
            foreach (var grant in context.Policy.Grants ?? [])
                if (grant.ParentGrantId is { } parent && affected.Contains(parent)) affected.Add(grant.Id);
            if (count == affected.Count) return Array.AsReadOnly(affected.OrderBy(id => id, StringComparer.Ordinal).ToArray());
        }
    }
    private static OrganizationPolicyChangeValidation Change(OrganizationAuthorizationDecision decision, long revision,
        IReadOnlyList<string>? affected = null, bool revalidate = false) => new(decision, revision, affected ?? Array.Empty<string>(), revalidate);
}
