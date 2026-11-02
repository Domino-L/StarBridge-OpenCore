namespace StarBridge.Core.Organizations;

public static class OrganizationAuthorizationPolicy
{
    public static OrganizationAuthorizationDecision EvaluateRootControl(
        OrganizationAuthorizationContext context, OrganizationRootControl action)
    {
        var current = OrganizationAuthorizationValidation.ContextState(context);
        if (current.Outcome != OrganizationAuthorizationOutcome.Allowed) return current;
        if (!Enum.IsDefined(action)) return new(OrganizationAuthorizationOutcome.Invalid, "unknownRootControl");
        var root = OrganizationAuthorizationValidation.Root(context.Root, context.Actor, context);
        if (root.Outcome != OrganizationAuthorizationOutcome.Allowed) return root;
        if (action != OrganizationRootControl.Delegate)
            // Any history for this subject in this scope is conservative opt-out,
            // including revoked records replaced by an explicit new-epoch activation.
            return new(OrganizationAuthorizationOutcome.Allowed,
                action == OrganizationRootControl.Activate && OrganizationRankAuthority.Current(context.Root, context.Actor, context) &&
                    context.Root.RankValue == 1 && !(context.Policy.Activations ?? []).Any(a => a.Subject == context.Actor.Subject)
                    ? "rootNeverActivated" : "explicitRootControl");
        var activation = (context.Policy.Activations ?? []).SingleOrDefault(a => !a.Revoked &&
            a.Subject == context.Actor.Subject && a.ProofDefinition == context.Root.ProofDefinition);
        if (activation is null || activation.Subject != context.Actor.Subject ||
            activation.MembershipEpoch != context.Actor.MembershipEpoch || activation.Basis != context.Root.Basis ||
            activation.ProofDefinition != context.Root.ProofDefinition)
            return new(OrganizationAuthorizationOutcome.Denied, "rootActivationNotCurrent");
        return new(OrganizationAuthorizationOutcome.Allowed, "explicitRootDelegation");
    }

    public static OrganizationAuthorizationDecision EvaluateUse(OrganizationAuthorizationContext context, string capability)
    {
        var current = OrganizationAuthorizationValidation.ContextState(context);
        if (current.Outcome != OrganizationAuthorizationOutcome.Allowed) return current;
        if (!OrganizationCapabilityCatalog.IsSupported(capability)) return new(OrganizationAuthorizationOutcome.Invalid, "unsupportedCapability");
        // Rank-one evidence keeps the member's own activation mandatory even
        // after expiry while other issuers are being observed. Root validation
        // checks binding and freshness before any activated-leader permission.
        if (context.Root.RankValue == 1)
        {
            var activation = EvaluateRootControl(context, OrganizationRootControl.Delegate);
            return activation.Outcome == OrganizationAuthorizationOutcome.Allowed
                ? new(OrganizationAuthorizationOutcome.Allowed, "activatedLeader") : activation;
        }
        if (OrganizationRankAuthority.Current(context.Root, context.Actor, context))
        {
            if (OrganizationRankPermissions.Allows(context.Policy, context.Root.RankValue!.Value, capability))
                return new(OrganizationAuthorizationOutcome.Allowed, "rankDerivedAdmin");
        }
        var result = context.Root.Reason == OrganizationRankAuthority.StaleReason
            ? new OrganizationAuthorizationDecision(OrganizationAuthorizationOutcome.Unavailable, OrganizationRankAuthority.StaleReason)
            : new OrganizationAuthorizationDecision(OrganizationAuthorizationOutcome.Denied, "notGranted");
        foreach (var grant in (context.Policy.Grants ?? []).Where(g => g.Subject == context.Actor.Subject &&
            g.Ceiling.Any(p => p.Capability == capability && p.CanUse)))
        {
            var candidate = EvaluateGrant(context, grant, capability, false);
            if (candidate.Outcome is OrganizationAuthorizationOutcome.Allowed or OrganizationAuthorizationOutcome.Invalid) return candidate;
            if (candidate.Outcome == OrganizationAuthorizationOutcome.Unavailable) result = candidate;
        }
        return result;
    }

    public static OrganizationAuthorizationDecision EvaluateDelegation(OrganizationAuthorizationContext context,
        OrganizationMembershipEvidence target, IReadOnlyList<OrganizationCapabilityPermission> requested, string? parentGrantId = null)
    {
        var current = OrganizationAuthorizationValidation.ContextState(context);
        if (current.Outcome != OrganizationAuthorizationOutcome.Allowed) return current;
        if (context.Root.ProofDefinition == OrganizationRankAuthority.Definition &&
            !OrganizationRankAuthority.Current(context.Root, context.Actor, context))
            return new(OrganizationAuthorizationOutcome.Unavailable, "rankUnavailable");
        if (context.Root.ProofDefinition == OrganizationRankAuthority.Definition && context.Root.RankValue != 1)
            return new(OrganizationAuthorizationOutcome.Denied, "verifiedLeaderRequired");
        if (requested.Count == 0 || !OrganizationAuthorizationValidation.PermissionsValid(requested) || requested.Any(p => !p.CanUse))
            return new(OrganizationAuthorizationOutcome.Invalid, "invalidDelegationCapabilities");
        var targetState = OrganizationAuthorizationValidation.Membership(target, target.Subject, target.MembershipEpoch, context);
        if (targetState.Outcome != OrganizationAuthorizationOutcome.Allowed) return targetState;
        if (parentGrantId is null) return EvaluateRootControl(context, OrganizationRootControl.Delegate);
        var parent = (context.Policy.Grants ?? []).SingleOrDefault(g => g.Id == parentGrantId);
        if (parent is null) return new(OrganizationAuthorizationOutcome.Invalid, "delegationParentMissing");
        if (parent.Subject != context.Actor.Subject) return new(OrganizationAuthorizationOutcome.Denied, "delegationParentNotOwned");
        foreach (var permission in requested)
        {
            var decision = EvaluateGrant(context, parent, permission.Capability, true);
            if (decision.Outcome != OrganizationAuthorizationOutcome.Allowed) return decision;
        }
        return new(OrganizationAuthorizationOutcome.Allowed, "boundedDelegation", parent.Id);
    }

    // Official-fleet policy writes must use this gate even for exact retries.
    // Legacy proof providers can still read/use retained grants but cannot edit governance.
    public static OrganizationAuthorizationDecision EvaluateManagement(OrganizationAuthorizationContext context)
    {
        var current = OrganizationAuthorizationValidation.ContextState(context);
        if (current.Outcome != OrganizationAuthorizationOutcome.Allowed) return current;
        if (context.Root.Reason == OrganizationRankAuthority.StaleReason)
            return new(OrganizationAuthorizationOutcome.Unavailable, OrganizationRankAuthority.StaleReason);
        if (!OrganizationRankAuthority.Current(context.Root, context.Actor, context))
            return new(OrganizationAuthorizationOutcome.Unavailable, "rankUnavailable");
        if (context.Root.RankValue != 1) return new(OrganizationAuthorizationOutcome.Denied, "verifiedLeaderRequired");
        return EvaluateRootControl(context, OrganizationRootControl.Delegate);
    }

    private static OrganizationAuthorizationDecision EvaluateGrant(OrganizationAuthorizationContext context,
        OrganizationGrant leaf, string capability, bool requireDelegation)
    {
        var current = leaf;
        while (true)
        {
            if (current.Revoked || current.ExpiresAt is { } expires && expires <= context.Now)
                return new(OrganizationAuthorizationOutcome.Denied, "grantRevokedOrExpired");
            var role = (context.Policy.Roles ?? []).Single(r => r.Key == current.RoleKey);
            if (!role.Enabled || role.PermissionVersion != current.RolePermissionVersion)
                return new(OrganizationAuthorizationOutcome.Denied, "roleDisabledOrBindingStale");
            var ceiling = current.Ceiling.SingleOrDefault(p => p.Capability == capability);
            var template = role.Permissions.SingleOrDefault(p => p.Capability == capability);
            var needsDelegate = requireDelegation || current.Id != leaf.Id;
            if (ceiling is null || template is null || !ceiling.CanUse || !template.CanUse ||
                needsDelegate && (!ceiling.CanDelegate || !template.CanDelegate))
                return new(OrganizationAuthorizationOutcome.Denied, "capabilityNotDelegated");
            var member = current.Subject == context.Actor.Subject ? context.Actor :
                (context.RequiredMembers ?? []).SingleOrDefault(m => m.Subject == current.Subject);
            if (member is null) return new(OrganizationAuthorizationOutcome.Unavailable, "ancestorMembershipUnavailable");
            var membership = OrganizationAuthorizationValidation.Membership(member, current.Subject, current.MembershipEpoch, context);
            if (membership.Outcome != OrganizationAuthorizationOutcome.Allowed) return membership;
            if (current.ParentGrantId is not null)
            {
                var parent = (context.Policy.Grants ?? []).Single(g => g.Id == current.ParentGrantId);
                if (parent.Version != current.ParentGrantVersion) return new(OrganizationAuthorizationOutcome.Denied, "parentBindingStale");
                current = parent;
                continue;
            }
            var activation = (context.Policy.Activations ?? []).Single(a => a.Id == current.RootActivationId);
            if (activation.Revoked || activation.Version != current.RootActivationVersion)
                return new(OrganizationAuthorizationOutcome.Denied, "rootActivationRevokedOrChanged");
            var issuer = activation.Subject == context.Actor.Subject ? context.Actor :
                (context.RequiredMembers ?? []).SingleOrDefault(m => m.Subject == activation.Subject);
            if (issuer is null) return new(OrganizationAuthorizationOutcome.Unavailable, "rootMembershipUnavailable");
            var issuerState = OrganizationAuthorizationValidation.Membership(issuer, activation.Subject, activation.MembershipEpoch, context);
            if (issuerState.Outcome != OrganizationAuthorizationOutcome.Allowed) return issuerState;
            var proof = context.RequiredRoots?.SingleOrDefault(r => r.Subject == issuer.Subject) ?? context.Root;
            var root = OrganizationAuthorizationValidation.Root(proof, issuer, context);
            if (root.Outcome != OrganizationAuthorizationOutcome.Allowed) return root;
            if ((activation.Basis != proof.Basis || activation.ProofDefinition != proof.ProofDefinition) &&
                !OrganizationRankAuthority.LegacyGrantBinding(activation, proof))
                return new(OrganizationAuthorizationOutcome.Denied, "rootActivationBindingStale");
            return new(OrganizationAuthorizationOutcome.Allowed, "effectiveGrant", leaf.Id);
        }
    }
}
