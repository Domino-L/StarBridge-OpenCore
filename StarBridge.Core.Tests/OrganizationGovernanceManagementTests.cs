using StarBridge.Core.Organizations;

namespace StarBridge.Core.Tests;

internal static class OrganizationGovernanceManagementTests
{
    internal static void RunAll()
    {
        var now = new DateTimeOffset(2026, 10, 31, 0, 0, 0, TimeSpan.Zero);
        var scope = new OrganizationAuthorizationScope("synthetic", 7, "TEST");
        var member = new OrganizationMembershipEvidence(OrganizationMembershipState.Current, "leader", scope, "epoch-1",
            now, now.AddMinutes(1), "synthetic");
        var proof = new OrganizationRootEligibilityEvidence(OrganizationRootEligibilityState.Eligible, OrganizationRankAuthority.Basis,
            member.Subject, scope, member.MembershipEpoch, OrganizationRankAuthority.Definition, now, now.AddMinutes(1), 1);
        var context = new OrganizationAuthorizationContext(member, proof, new(OrganizationPolicyReadState.Available, 0, scope, [], [], []), now);
        string Reason(OrganizationAuthorizationContext c) => OrganizationAuthorizationPolicy.EvaluateRootControl(c, OrganizationRootControl.Activate).Reason;
        Check(Reason(context) == "rootNeverActivated", "empty subject history offers automatic activation");
        var activation = new OrganizationRootActivation("a", 1, member.Subject, member.MembershipEpoch, proof.Basis!, proof.ProofDefinition!);
        foreach (var history in new OrganizationRootActivation[][]
        {
            [activation], [activation with { Revoked = true, Version = 2 }],
            [activation with { Revoked = true, MembershipEpoch = "previous-epoch" }],
            [activation with { Revoked = true, MembershipEpoch = "previous-epoch" }, activation with { Id = "new-epoch", Revoked = true }],
            [activation with { Revoked = true, ProofDefinition = OrganizationRankAuthority.LegacyDefinition }]
        }) Check(Reason(context with { Policy = context.Policy with { Activations = history } }) == "explicitRootControl",
            "any own activation history prevents automatic activation");
        Check(Reason(context with { Policy = context.Policy with { Activations = [activation with { Subject = "other" }] } }) == "rootNeverActivated",
            "another subject's history does not prevent first activation");
        context = context with { Policy = context.Policy with { Activations = [activation] } };
        foreach (var capability in OrganizationCapabilityCatalog.Implemented)
            Check(OrganizationAuthorizationPolicy.EvaluateUse(context, capability).Outcome == OrganizationAuthorizationOutcome.Allowed,
                "activated verified leader has " + capability);
        foreach (var rank in Enumerable.Range(2, 5))
        {
            var ranked = context with { Root = proof with { RankValue = rank, State = OrganizationRootEligibilityState.Ineligible } };
            foreach (var capability in OrganizationCapabilityCatalog.Implemented)
                Check((OrganizationAuthorizationPolicy.EvaluateUse(ranked, capability).Outcome == OrganizationAuthorizationOutcome.Allowed) ==
                    (rank <= 3 && capability is OrganizationCapabilityCatalog.ManageAnnouncements or OrganizationCapabilityCatalog.ViewAudit),
                    "unchanged default for verified rank " + rank + " / " + capability);
            Check(OrganizationAuthorizationPolicy.EvaluateManagement(ranked).Outcome == OrganizationAuthorizationOutcome.Denied,
                "lower rank cannot write governance");
            Check(OrganizationAuthorizationPolicy.EvaluateDelegation(ranked, member, [new(OrganizationCapabilityCatalog.ViewAudit, true, false)]).Outcome !=
                OrganizationAuthorizationOutcome.Allowed, "lower rank cannot delegate");
        }
        var table = OrganizationRankPermissions.Defaults.Select(r => r with { Rally = r.RankValue == 5 }).ToArray();
        var ordinary = context with { Root = proof with { RankValue = 5, State = OrganizationRootEligibilityState.Ineligible },
            Policy = context.Policy with { RankPermissions = table } };
        Check(OrganizationAuthorizationPolicy.EvaluateUse(ordinary, OrganizationCapabilityCatalog.ManageRally).Outcome == OrganizationAuthorizationOutcome.Allowed,
            "rank table grants rally use without delegation");
        Check(OrganizationAuthorizationPolicy.EvaluateUse(ordinary with { Root = ordinary.Root with { ValidUntil = now } },
            OrganizationCapabilityCatalog.ManageRally).Outcome != OrganizationAuthorizationOutcome.Allowed, "expired rank never uses the table");
        Check(!OrganizationRankPermissions.Valid([.. table.Take(3), new(1, true, true, true)]), "rank one is fixed and cannot enter the editable table");
        Check(!OrganizationRankPermissions.Valid([.. table.Take(3), table[0]]), "duplicate and incomplete ranks are invalid");
        Check(OrganizationRankPermissions.Valid(null), "old snapshots load with default rank permissions");
        LeaderRevocation();
    }
    private static void LeaderRevocation()
    {
        var now = new DateTimeOffset(2026, 10, 31, 0, 0, 0, TimeSpan.Zero);
        var scope = new OrganizationAuthorizationScope("synthetic", 7, "TEST");
        OrganizationMembershipEvidence Member(string name) => new(OrganizationMembershipState.Current,
            name, scope, "epoch-" + name, now, now.AddMinutes(1), "synthetic");
        OrganizationRootEligibilityEvidence Proof(string name, int rank = 1) => new(
            rank == 1 ? OrganizationRootEligibilityState.Eligible : OrganizationRootEligibilityState.Ineligible,
            OrganizationRankAuthority.Basis, name, scope, "epoch-" + name, OrganizationRankAuthority.Definition,
            now, now.AddMinutes(1), rank);
        OrganizationRootActivation Activation(string name) => new("activation-" + name, 1, name,
            "epoch-" + name, OrganizationRankAuthority.Basis, OrganizationRankAuthority.Definition);
        var roots = new[] { Activation("A"), Activation("B") };
        var rights = OrganizationCapabilityCatalog.Implemented.Select(cap => new OrganizationCapabilityPermission(cap, true, false)).ToArray();
        var role = new OrganizationRoleDefinition("manager", scope, 1, 1, true, rights);
        var grant = new OrganizationGrant("B-to-A", 1, scope, "A", "epoch-A", role.Key, 1, rights,
            RootActivationId: roots[1].Id, RootActivationVersion: 1);
        var context = new OrganizationAuthorizationContext(Member("A"), Proof("A"),
            new(OrganizationPolicyReadState.Available, 1, scope, roots, [role], []), now, [Member("B")], [Proof("B")]);
        Check(OrganizationAuthorizationPolicy.EvaluateUse(context, OrganizationCapabilityCatalog.ManageRally).Reason == "activatedLeader",
            "review sequence: A and B are activated rank one");
        context = context with { Policy = context.Policy with { Grants = [grant], Revision = 2 } };
        Check(OrganizationAuthorizationValidation.ValidateSnapshotShape(context.Policy).Outcome == OrganizationAuthorizationOutcome.Allowed,
            "review sequence: B grants A rally.manage bound to B activation");
        context = context with { Policy = context.Policy with { Activations = [roots[0] with { Revoked = true, Version = 2 }, roots[1]], Revision = 3 } };
        foreach (var capability in OrganizationCapabilityCatalog.Implemented)
        {
            Check(OrganizationAuthorizationPolicy.EvaluateUse(context, capability).Outcome == OrganizationAuthorizationOutcome.Denied,
                "review sequence: A revokes; B grant cannot restore " + capability);
            Check(OrganizationAuthorizationPolicy.EvaluateUse(context with { Root = Proof("A", 5) }, capability).Reason == "effectiveGrant",
                "lower rank personal grant remains effective for " + capability);
            // Actor proof lapses while the issuer observation is being awaited.
            // Membership and B's proof remain current at both evaluations.
            var expired = context with { Root = Proof("A") with { ValidUntil = now.AddSeconds(1) }, Now = now.AddSeconds(2) };
            var first = OrganizationAuthorizationPolicy.EvaluateUse(expired, capability);
            Check(first.Outcome is OrganizationAuthorizationOutcome.Unavailable or OrganizationAuthorizationOutcome.Denied &&
                first.Reason != "effectiveGrant", "expired rank one cannot recover B grant for " + capability);
            Check(OrganizationAuthorizationPolicy.EvaluateUse(expired with { Now = now.AddSeconds(3) }, capability) == first,
                "expired rank one re-evaluation is stable for " + capability);
            var lower = expired with { Root = Proof("A", 5) with { ValidUntil = now.AddSeconds(1) } };
            Check(OrganizationAuthorizationPolicy.EvaluateUse(lower, capability).Reason == "effectiveGrant",
                "expired lower rank keeps personal grant behavior for " + capability);
        }
        var otherScope = scope with { OrganizationId = 8, Sid = "OTHER" };
        var other = context with { Actor = Member("A") with { Scope = otherScope }, Root = Proof("A") with { Scope = otherScope },
            Policy = new(OrganizationPolicyReadState.Available, 0, otherScope, [], [], []), RequiredMembers = [], RequiredRoots = [] };
        Check(OrganizationAuthorizationPolicy.EvaluateRootControl(context, OrganizationRootControl.Activate).Reason == "explicitRootControl" &&
            OrganizationAuthorizationPolicy.EvaluateRootControl(other, OrganizationRootControl.Activate).Reason == "rootNeverActivated",
            "revocation blocks automatic activation only in the same fleet scope");
    }
    private static void Check(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException(message);
        Console.WriteLine("PASS governance Core: " + message);
    }
}
