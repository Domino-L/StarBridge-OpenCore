using StarBridge.Core.Organizations;

namespace StarBridge.Core.Tests;

internal static class OrganizationLeaderRuleTests
{
    private static readonly DateTimeOffset Now = new(2026, 10, 24, 0, 0, 0, TimeSpan.Zero);
    private static readonly OrganizationAuthorizationScope Scope = new("synthetic", 7, "TEST");
    private static OrganizationMembershipEvidence Member(string subject) =>
        new(OrganizationMembershipState.Current, subject, Scope, "epoch-" + subject, Now, Now.AddMinutes(1), "synthetic");
    private static OrganizationRootEligibilityEvidence Proof(string subject, int rank) =>
        new(rank == 1 ? OrganizationRootEligibilityState.Eligible : OrganizationRootEligibilityState.Ineligible,
            OrganizationRankAuthority.Basis, subject, Scope, "epoch-" + subject,
            OrganizationRankAuthority.Definition, Now, Now.AddMinutes(1), rank);
    private static OrganizationRootActivation Activation(string subject) =>
        new("activation-" + subject, 1, subject, "epoch-" + subject, OrganizationRankAuthority.Basis, OrganizationRankAuthority.Definition);
    private static OrganizationAuthorizationContext Context(string subject, int rank, params OrganizationRootActivation[] activations) =>
        new(Member(subject), Proof(subject, rank), new(OrganizationPolicyReadState.Available, 1, Scope, activations, [], []), Now);
    private static void Check(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException(message);
        Console.WriteLine("PASS leader rule: " + message);
    }
    private static bool Allowed(OrganizationAuthorizationDecision decision) => decision.Outcome == OrganizationAuthorizationOutcome.Allowed;

    internal static void RunAll()
    {
        foreach (var rank in Enumerable.Range(1, 6))
        foreach (var activated in new[] { false, true })
        {
            var c = Context("A", rank, activated ? [Activation("A")] : []);
            foreach (var cap in OrganizationCapabilityCatalog.Implemented)
            {
                var expected = rank == 1 && activated || rank is 2 or 3 &&
                    cap is OrganizationCapabilityCatalog.ManageAnnouncements or OrganizationCapabilityCatalog.ViewAudit;
                Check(Allowed(OrganizationAuthorizationPolicy.EvaluateUse(c, cap)) == expected, $"rank {rank}, activated {activated}, {cap}");
            }
            Check(OrganizationRankAuthority.Role(c) == (rank == 1 ? "leader" : rank <= 3 ? "admin" : rank == 4 ? "editor" : "member"), $"rank {rank} role");
            foreach (var action in new[] { OrganizationRootControl.Activate, OrganizationRootControl.Recover })
                Check(Allowed(OrganizationAuthorizationPolicy.EvaluateRootControl(c, action)) == (rank == 1), $"rank {rank} {action}");
        }
        var a = Context("A", 1, Activation("A"));
        var b = Context("B", 1, Activation("A"));
        Check(!Allowed(OrganizationAuthorizationPolicy.EvaluateRootControl(b, OrganizationRootControl.Delegate)), "B cannot borrow A activation");
        b = b with { Policy = b.Policy with { Activations = [Activation("A"), Activation("B")] } };
        Check(Allowed(OrganizationAuthorizationPolicy.EvaluateRootControl(b, OrganizationRootControl.Delegate)) &&
            Allowed(OrganizationAuthorizationPolicy.EvaluateRootControl(a with { Policy = b.Policy }, OrganizationRootControl.Delegate)), "two independently activated leaders");
        var permissions = new[] { new OrganizationCapabilityPermission(OrganizationCapabilityCatalog.ManageAnnouncements, true, true) };
        var grant = new OrganizationGrant("grant", 1, Scope, "C", "epoch-C", "publisher", 1, permissions,
            RootActivationId: Activation("A").Id, RootActivationVersion: 1);
        b = b with { Policy = b.Policy with { Roles = [new("publisher", Scope, 1, 1, true, permissions)], Grants = [grant] } };
        Check(Allowed(OrganizationAuthorizationValidation.ValidateRevoke(b, 1, "grant").Decision), "B revokes A grant");
        Check(OrganizationRankAuthority.Role(b) == "leader", "revoking a grant never changes RSI leader role");
        var delegated = b with { Actor = Member("C"), Root = Proof("C", 6), RequiredMembers = [Member("A")], RequiredRoots = [Proof("A", 1)] };
        Check(Allowed(OrganizationAuthorizationPolicy.EvaluateUse(delegated, OrganizationCapabilityCatalog.ManageAnnouncements)), "grant uses issuer proof independently of viewer rank");
        var placeholders = b.Policy with { Activations = b.Policy.Activations!.Select(root => root with { Revoked = true }).ToArray() };
        Check(OrganizationAuthorizationValidation.ValidateSnapshotShape(placeholders).Outcome == OrganizationAuthorizationOutcome.Allowed &&
            !Allowed(OrganizationAuthorizationPolicy.EvaluateRootControl(b with { Policy = placeholders }, OrganizationRootControl.Delegate)) &&
            !Allowed(OrganizationAuthorizationPolicy.EvaluateUse(delegated with { Policy = placeholders }, OrganizationCapabilityCatalog.ManageAnnouncements)),
            "rollback placeholders retain graph bindings without root or delegated authority");
        Check(!Allowed(OrganizationAuthorizationPolicy.EvaluateUse(delegated with { RequiredRoots = [Proof("A", 2)] }, OrganizationCapabilityCatalog.ManageAnnouncements)), "issuer downgrade removes delegated power");
        var legacy = Activation("A") with { Basis = OrganizationRankAuthority.LegacyBasis, ProofDefinition = OrganizationRankAuthority.LegacyDefinition };
        var migrated = delegated with { Policy = delegated.Policy with { Activations = [legacy] } };
        Check(Allowed(OrganizationAuthorizationPolicy.EvaluateUse(migrated, OrganizationCapabilityCatalog.ManageAnnouncements)), "existing V1 grant remains usable under current V2 issuer proof");
        Check(!Allowed(OrganizationAuthorizationPolicy.EvaluateRootControl(a with { Policy = a.Policy with { Activations = [legacy] } }, OrganizationRootControl.Delegate)), "old activation is audit provenance only under V2");
        foreach (var rank in new[] { 1, 2, 3 })
        {
            var c = Context("A", rank, Activation("A"));
            foreach (var cap in OrganizationCapabilityCatalog.Implemented)
            {
                Check(!Allowed(OrganizationAuthorizationPolicy.EvaluateUse(c with { Root = c.Root with { ValidUntil = Now } }, cap)), $"expired rank {rank} loses {cap}");
                Check(!Allowed(OrganizationAuthorizationPolicy.EvaluateUse(c with { Root = Proof("A", 6) }, cap)), $"downgraded rank {rank} loses {cap}");
            }
        }
        var stale = a with { Root = a.Root with { State = OrganizationRootEligibilityState.Unavailable, Reason = OrganizationRankAuthority.StaleReason } };
        Check(OrganizationAuthorizationPolicy.EvaluateRootControl(stale, OrganizationRootControl.Activate).Reason == OrganizationRankAuthority.StaleReason &&
            !Allowed(OrganizationAuthorizationPolicy.EvaluateUse(stale, OrganizationCapabilityCatalog.ManageAnnouncements)), "stale reason preserved and power refused");
        Check(!Allowed(OrganizationAuthorizationPolicy.EvaluateRootControl(a with { Root = Proof("B", 1) }, OrganizationRootControl.Activate)), "another leader proof cannot activate actor");
        Check(!Allowed(OrganizationAuthorizationPolicy.EvaluateRootControl(a with { Root = a.Root with { MembershipEpoch = "old-epoch" } }, OrganizationRootControl.Activate)), "activation rejects proof from previous membership epoch");
        Check(!Allowed(OrganizationAuthorizationPolicy.EvaluateRootControl(a with { Root = a.Root with { RankValue = 2 } }, OrganizationRootControl.Activate)), "eligible label cannot override nonleader V2 rank");
        var v1 = a with { Root = a.Root with { Basis = legacy.Basis, ProofDefinition = legacy.ProofDefinition, RankValue = null }, Policy = a.Policy with { Activations = [legacy] } };
        Check(Allowed(OrganizationAuthorizationPolicy.EvaluateRootControl(v1, OrganizationRootControl.Delegate)) &&
            !Allowed(OrganizationAuthorizationPolicy.EvaluateUse(v1, OrganizationCapabilityCatalog.ManageAnnouncements)), "V1 root and ordinary capability behavior unchanged");
        Check(OrganizationAuthorizationValidation.ValidateSnapshotShape(b.Policy with { Activations = [Activation("B"), Activation("B") with { Id = "duplicate" }] }).Outcome == OrganizationAuthorizationOutcome.Invalid,
            "duplicate personal activations fail closed");
    }
}
