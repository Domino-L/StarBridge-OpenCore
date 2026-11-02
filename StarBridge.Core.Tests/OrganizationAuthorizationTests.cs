using StarBridge.Core.Organizations;

namespace StarBridge.Core.Tests;

internal static class OrganizationAuthorizationTests
{
    private static readonly DateTimeOffset Now = new(2026, 10, 17, 0, 0, 0, TimeSpan.Zero);
    private static readonly OrganizationAuthorizationScope Scope = new("synthetic-scm", 7, "ASTER");
    private const string Epoch = "scm-observed-membership-row-v1:30";

    internal static void RunAll()
    {
        OrganizationGovernanceManagementTests.RunAll();
        OrganizationLeaderRuleTests.RunAll();
        RootFactsAreIndependentAndCurrent();
        GrantsDependOnCurrentPermissionChains();
        ChangesRequireCurrentAuthorityAndCas();
        ValidatedGrantsRemainUsableAndBounded();
        UnsafeGraphsReturnTypedFailure();
        ManagementCannotEscapeGrantProvenance();
        RoleVersionOverflowDoesNotValidateAnInvalidBinding();
        SnapshotShapeNeverRequiresOrGrantsCurrentAuthority();
        RoleAuthorityPreflightRemainsBoundedAndSeparate();
    }

    private static OrganizationMembershipEvidence Member(string subject = "root", string epoch = Epoch) =>
        new(OrganizationMembershipState.Current, subject, Scope, epoch, Now.AddSeconds(-17),
            Now.AddMinutes(3), "SCM_OBSERVED_MEMBERSHIP_V1");
    private static OrganizationRootEligibilityEvidence Eligible() =>
        new(OrganizationRootEligibilityState.Eligible, "synthetic-selected-provider", "root", Scope, Epoch,
            "synthetic-proof-v1", Now.AddMinutes(-1), Now.AddMinutes(2));
    private static OrganizationRootActivation Activation() =>
        new("activation-1", 1, "root", Epoch, "synthetic-selected-provider", "synthetic-proof-v1");
    private static OrganizationAuthorizationContext Context() =>
        new(Member(), new(OrganizationRootEligibilityState.Unconfigured),
            new(OrganizationPolicyReadState.Available, 0, Scope), Now);
    private static void Expect(OrganizationAuthorizationDecision decision, OrganizationAuthorizationOutcome expected, string description)
    {
        if (decision.Outcome != expected)
            throw new InvalidOperationException(description + $": expected {expected}; got {decision.Outcome}/{decision.Reason}");
        Console.WriteLine("PASS " + description);
    }
    private static void RootFactsAreIndependentAndCurrent()
    {
        var c = Context();
        Expect(OrganizationAuthorizationPolicy.EvaluateRootControl(c, OrganizationRootControl.Activate),
            OrganizationAuthorizationOutcome.Unavailable, "Unconfigured root is unavailable independently of a known empty policy");
        Expect(OrganizationAuthorizationPolicy.EvaluateRootControl(c with { Root = new(OrganizationRootEligibilityState.Unavailable) }, OrganizationRootControl.Activate),
            OrganizationAuthorizationOutcome.Unavailable, "Unavailable current root proof cannot become a known denial");
        Expect(OrganizationAuthorizationPolicy.EvaluateRootControl(c with { Root = new(OrganizationRootEligibilityState.Ineligible) }, OrganizationRootControl.Activate),
            OrganizationAuthorizationOutcome.Denied, "Known ineligible root is denied");
        c = c with { Root = Eligible() };
        Expect(OrganizationAuthorizationPolicy.EvaluateRootControl(c, OrganizationRootControl.Activate),
            OrganizationAuthorizationOutcome.Allowed, "Current independent root proof permits explicit activation");
        Expect(OrganizationAuthorizationPolicy.EvaluateRootControl(c, OrganizationRootControl.Delegate),
            OrganizationAuthorizationOutcome.Denied, "Eligible root cannot delegate before explicit activation");
        Expect(OrganizationAuthorizationPolicy.EvaluateRootControl(c with { Actor = Member() with { State = OrganizationMembershipState.Unavailable } }, OrganizationRootControl.Activate),
            OrganizationAuthorizationOutcome.Unavailable, "Unknown current actor membership is unavailable");
        Expect(OrganizationAuthorizationPolicy.EvaluateRootControl(c with { Actor = Member() with { State = OrganizationMembershipState.NotCurrent } }, OrganizationRootControl.Activate),
            OrganizationAuthorizationOutcome.Denied, "Known departure denies activation");
        Expect(OrganizationAuthorizationPolicy.EvaluateRootControl(c with { Actor = Member() with { ValidUntil = Now } }, OrganizationRootControl.Activate),
            OrganizationAuthorizationOutcome.Unavailable, "Expired membership cannot activate root");
        Expect(OrganizationAuthorizationPolicy.EvaluateRootControl(c with { Actor = Member() with { Scope = Scope with { OrganizationId = 8 } } }, OrganizationRootControl.Activate),
            OrganizationAuthorizationOutcome.Invalid, "Cross-scope evidence is invalid");
        Expect(OrganizationAuthorizationPolicy.EvaluateRootControl(c with { Root = Eligible() with { MembershipEpoch = "prior-epoch" } }, OrganizationRootControl.Activate),
            OrganizationAuthorizationOutcome.Denied, "Previous membership epoch cannot activate root");
        Expect(OrganizationAuthorizationPolicy.EvaluateRootControl(c with { Root = Eligible() with { Subject = "other" } }, OrganizationRootControl.Activate),
            OrganizationAuthorizationOutcome.Denied, "Another subject's root proof cannot activate actor");
        Expect(OrganizationAuthorizationPolicy.EvaluateRootControl(c with { Root = Eligible() with { ValidUntil = Now } }, OrganizationRootControl.Activate),
            OrganizationAuthorizationOutcome.Unavailable, "Expired root eligibility remains unavailable");
        Expect(OrganizationAuthorizationPolicy.EvaluateRootControl(c with { Root = Eligible() with { ObservedAt = Now.AddSeconds(1) } }, OrganizationRootControl.Activate),
            OrganizationAuthorizationOutcome.Invalid, "Future root proof is malformed rather than fresh");
        Expect(OrganizationAuthorizationPolicy.EvaluateRootControl(c with { Policy = c.Policy with { ReadState = OrganizationPolicyReadState.Unavailable } }, OrganizationRootControl.Activate),
            OrganizationAuthorizationOutcome.Unavailable, "Unreadable policy cannot be substituted with an empty policy");
        c = c with { Policy = c.Policy with { Revision = 1, Activations = [Activation()] } };
        Expect(OrganizationAuthorizationPolicy.EvaluateRootControl(c, OrganizationRootControl.Delegate),
            OrganizationAuthorizationOutcome.Allowed, "Explicit activation and current proof permit root delegation control");
        Expect(OrganizationAuthorizationPolicy.EvaluateRootControl(c with { Root = new(OrganizationRootEligibilityState.Unavailable) }, OrganizationRootControl.Delegate),
            OrganizationAuthorizationOutcome.Unavailable, "Stored activation never replaces current root authority");
        Expect(OrganizationAuthorizationPolicy.EvaluateRootControl(c with { Policy = c.Policy with { Activations = [Activation() with { Revoked = true }] } }, OrganizationRootControl.Delegate),
            OrganizationAuthorizationOutcome.Denied, "Revoked activation cannot delegate");
        Expect(OrganizationAuthorizationPolicy.EvaluateRootControl(c with { Root = Eligible() with { ProofDefinition = "new-proof-definition" } }, OrganizationRootControl.Delegate),
            OrganizationAuthorizationOutcome.Denied, "Changed provider definition requires explicit activation revalidation");
    }

    private const string Ann = OrganizationCapabilityCatalog.ManageAnnouncements;
    private static OrganizationCapabilityPermission Permission(bool delegateRight = true) => new(Ann, true, delegateRight);
    private static OrganizationRoleDefinition Role() => new("officer", Scope, 1, 1, true, [Permission()]);
    private static OrganizationGrant RootGrant() => new("grant-root", 1, Scope, "root", Epoch, "officer", 1,
        [Permission()], RootActivationId: "activation-1", RootActivationVersion: 1);
    private static OrganizationGrant ChildGrant() => new("grant-child", 1, Scope, "child", "child-epoch", "officer", 1,
        [Permission(false)], ParentGrantId: "grant-root", ParentGrantVersion: 1);
    private static OrganizationAuthorizationContext Granted() => Context() with
    {
        Root = Eligible(),
        Policy = new(OrganizationPolicyReadState.Available, 5, Scope, [Activation()], [Role()], [RootGrant()])
    };
    private static OrganizationAuthorizationContext Child() => Granted() with
    {
        Actor = Member("child", "child-epoch"), RequiredMembers = [Member()],
        Policy = Granted().Policy with { Grants = [RootGrant(), ChildGrant()] }
    };
    private static void GrantsDependOnCurrentPermissionChains()
    {
        Expect(OrganizationAuthorizationPolicy.EvaluateUse(Context() with { Root = Eligible() }, Ann),
            OrganizationAuthorizationOutcome.Denied, "Root eligibility does not itself grant ordinary announcement use");
        var c = Granted();
        Expect(OrganizationAuthorizationPolicy.EvaluateUse(c, Ann), OrganizationAuthorizationOutcome.Allowed, "Explicit root-issued grant permits an implemented capability");
        Expect(OrganizationAuthorizationPolicy.EvaluateUse(c, "broadcasts.publish"), OrganizationAuthorizationOutcome.Invalid, "Unimplemented broadcast permission cannot be used");
        Expect(OrganizationAuthorizationPolicy.EvaluateUse(c with { Root = new(OrganizationRootEligibilityState.Unavailable) }, Ann), OrganizationAuthorizationOutcome.Unavailable, "Existing grant still requires current root authority");
        Expect(OrganizationAuthorizationPolicy.EvaluateUse(c with { Policy = c.Policy with { Roles = [Role() with { Enabled = false }] } }, Ann), OrganizationAuthorizationOutcome.Denied, "Disabled current role revokes effective use");
        Expect(OrganizationAuthorizationPolicy.EvaluateUse(c with { Policy = c.Policy with { Roles = [Role() with { PermissionVersion = 2 }] } }, Ann), OrganizationAuthorizationOutcome.Denied, "Unrevalidated permission-version binding cannot inherit a new template");
        Expect(OrganizationAuthorizationPolicy.EvaluateUse(c with { Policy = c.Policy with { Roles = [Role() with { MetadataRevision = 2 }] } }, Ann), OrganizationAuthorizationOutcome.Allowed, "Metadata-only role revision does not revoke a valid grant");
        c = Child();
        Expect(OrganizationAuthorizationPolicy.EvaluateUse(c, Ann), OrganizationAuthorizationOutcome.Allowed, "Current use-only child grant can use its delegated capability");
        Expect(OrganizationAuthorizationPolicy.EvaluateDelegation(c, Member("target", "target-epoch"), [Permission(false)], "grant-child"), OrganizationAuthorizationOutcome.Denied, "Use-only child cannot delegate further");
        Expect(OrganizationAuthorizationPolicy.EvaluateUse(c with { RequiredMembers = [] }, Ann), OrganizationAuthorizationOutcome.Unavailable, "Missing required ancestor membership is unknown rather than departed");
        Expect(OrganizationAuthorizationPolicy.EvaluateUse(c with { RequiredMembers = [Member() with { State = OrganizationMembershipState.NotCurrent }] }, Ann), OrganizationAuthorizationOutcome.Denied, "Known departed ancestor revokes descendant use");
        Expect(OrganizationAuthorizationPolicy.EvaluateUse(c with { RequiredMembers = [Member() with { State = OrganizationMembershipState.Unavailable }] }, Ann), OrganizationAuthorizationOutcome.Unavailable, "Unknown ancestor authority cannot become a known empty policy");
        Expect(OrganizationAuthorizationPolicy.EvaluateUse(c with { Actor = Member("child", "new-epoch") }, Ann), OrganizationAuthorizationOutcome.Denied, "Rejoining with a new member epoch does not revive an old grant");
        Expect(OrganizationAuthorizationPolicy.EvaluateUse(c with { Policy = c.Policy with { Grants = [RootGrant() with { Revoked = true }, ChildGrant()] } }, Ann), OrganizationAuthorizationOutcome.Denied, "Parent revocation immediately denies descendants");
        Expect(OrganizationAuthorizationPolicy.EvaluateUse(c with { Policy = c.Policy with { Grants = [RootGrant() with { Version = 2 }, ChildGrant()] } }, Ann), OrganizationAuthorizationOutcome.Denied, "Changed parent binding cannot authorize a stale descendant");
        Expect(OrganizationAuthorizationPolicy.EvaluateUse(c with { Policy = c.Policy with { Grants = [RootGrant(), ChildGrant() with { ExpiresAt = Now }] } }, Ann), OrganizationAuthorizationOutcome.Denied, "Known expired grant is denied");
        Expect(OrganizationAuthorizationPolicy.EvaluateUse(c with { Policy = c.Policy with { Grants = [RootGrant(), ChildGrant(), ChildGrant()] } }, Ann), OrganizationAuthorizationOutcome.Invalid, "Duplicate grant IDs make the graph invalid");
        Expect(OrganizationAuthorizationPolicy.EvaluateUse(c with { Policy = c.Policy with { Grants = [ChildGrant()] } }, Ann), OrganizationAuthorizationOutcome.Invalid, "Missing parent policy reference is an unsafe graph");
        var cycle = RootGrant() with { ParentGrantId = "grant-child", ParentGrantVersion = 1, RootActivationId = null, RootActivationVersion = null };
        Expect(OrganizationAuthorizationPolicy.EvaluateUse(c with { Policy = c.Policy with { Grants = [cycle, ChildGrant()] } }, Ann), OrganizationAuthorizationOutcome.Invalid, "Cyclic parent references fail closed");
        Expect(OrganizationAuthorizationPolicy.EvaluateUse(c with { Policy = c.Policy with { Roles = [Role() with { Scope = Scope with { Sid = "FOREIGN" } }] } }, Ann), OrganizationAuthorizationOutcome.Invalid, "Cross-scope role references are invalid");
        Expect(OrganizationAuthorizationPolicy.EvaluateUse(c with { Policy = c.Policy with { Roles = [Role() with { Permissions = [new(Ann, false, true)] }] } }, Ann), OrganizationAuthorizationOutcome.Invalid, "Delegate without use is an invalid ordinary capability");
        Expect(OrganizationAuthorizationPolicy.EvaluateDelegation(Granted(), Member("target", "target-epoch"), [Permission(false)]), OrganizationAuthorizationOutcome.Allowed, "Explicit activated root can bootstrap a bounded grant without ordinary use");
        Expect(OrganizationAuthorizationPolicy.EvaluateDelegation(Granted(), Member("target", "target-epoch") with { State = OrganizationMembershipState.NotCurrent }, [Permission(false)]), OrganizationAuthorizationOutcome.Denied, "Grant target must still be a current member");
        Expect(OrganizationAuthorizationPolicy.EvaluateDelegation(Granted(), Member("target", "target-epoch"), [new("website.edit", true, true)]), OrganizationAuthorizationOutcome.Invalid, "Root cannot grant an unimplemented website action");
    }

    private static void ChangesRequireCurrentAuthorityAndCas()
    {
        var c = Granted();
        var draft = RootGrant() with { Id = "new-grant", Subject = "target", MembershipEpoch = "target-epoch" };
        var target = Member("target", "target-epoch");
        Expect(OrganizationAuthorizationValidation.ValidateGrant(c, 4, draft, target).Decision, OrganizationAuthorizationOutcome.Conflict, "Stale grant CAS conflicts before any mutation");
        Expect(OrganizationAuthorizationValidation.ValidateGrant(c, 5, draft, target).Decision, OrganizationAuthorizationOutcome.Allowed, "Activated current root validates a bounded grant draft");
        Expect(OrganizationAuthorizationValidation.ValidateGrant(c, 5, draft with { Subject = "other" }, target).Decision, OrganizationAuthorizationOutcome.Invalid, "Grant draft cannot substitute its target subject");
        Expect(OrganizationAuthorizationValidation.ValidateGrant(c, 5, draft with { MembershipEpoch = "old-target-epoch" }, target).Decision, OrganizationAuthorizationOutcome.Denied, "Grant draft must bind the target's current membership epoch");
        Expect(OrganizationAuthorizationValidation.ValidateGrant(c, 5, RootGrant(), Member()).Decision, OrganizationAuthorizationOutcome.Conflict, "Existing grant ID cannot be silently overwritten");
        Expect(OrganizationAuthorizationValidation.ValidateRevoke(c, 4, "grant-root").Decision, OrganizationAuthorizationOutcome.Conflict, "Revoke also requires current snapshot CAS");
        Expect(OrganizationAuthorizationValidation.ValidateRevoke(c, 5, "grant-root").Decision, OrganizationAuthorizationOutcome.Allowed, "Activated current root can revoke an explicit grant");
        Expect(OrganizationAuthorizationValidation.ValidateRevoke(Child(), 5, "grant-root").Decision, OrganizationAuthorizationOutcome.Denied, "Ordinary member cannot revoke an ancestor grant");
        var metadata = Role() with { MetadataRevision = 2 };
        var m = OrganizationAuthorizationValidation.ValidateRoleChange(c, 5, metadata);
        Expect(m.Decision, OrganizationAuthorizationOutcome.Allowed, "Metadata-only change validates without changing permission binding");
        Check(!m.RequiresGrantRevalidation && m.AffectedGrantIds.Count == 0, "Metadata-only change does not retire or migrate grants");
        var changed = Role() with { PermissionVersion = 2, Permissions = [Permission(false)] };
        var p = OrganizationAuthorizationValidation.ValidateRoleChange(c, 5, changed);
        Expect(p.Decision, OrganizationAuthorizationOutcome.Allowed, "Capability change is an explicit validated permission mutation");
        Check(p.RequiresGrantRevalidation && p.AffectedGrantIds.SequenceEqual(new[] { "grant-root" }), "Permission mutation returns affected bindings for A2 atomic revalidation");
        Expect(OrganizationAuthorizationValidation.ValidateRoleChange(c, 5, changed with { PermissionVersion = 1 }).Decision, OrganizationAuthorizationOutcome.Invalid, "Capability delta cannot masquerade as metadata at the old permission version");
        Expect(OrganizationAuthorizationValidation.ValidateRoleChange(c, 5, metadata with { PermissionVersion = 2 }).Decision, OrganizationAuthorizationOutcome.Invalid, "Metadata update cannot gratuitously invalidate permission bindings");
        Expect(OrganizationAuthorizationValidation.ValidateRoleChange(c, 4, metadata).Decision, OrganizationAuthorizationOutcome.Conflict, "Role metadata mutation is still protected by snapshot CAS");
        Expect(OrganizationAuthorizationValidation.ValidateRoleChange(c, 5, changed with { Permissions = [new("broadcasts.publish", true, true)] }).Decision, OrganizationAuthorizationOutcome.Invalid, "Unimplemented capability cannot enter a role template");
        var useOnly = c with { Actor = Member("child", "child-epoch"), RequiredMembers = [Member()], Policy = c.Policy with { Grants = [RootGrant(), ChildGrant()] } };
        Expect(OrganizationAuthorizationValidation.ValidateRoleChange(useOnly, 5, metadata).Decision, OrganizationAuthorizationOutcome.Denied, "Announcement use alone does not authorize role management");
        Expect(OrganizationAuthorizationValidation.ValidateGrant(c with { Root = new(OrganizationRootEligibilityState.Unavailable) }, 5, draft, target).Decision, OrganizationAuthorizationOutcome.Unavailable, "Unknown root authority cannot produce a validated grant command");
    }

    private static void Check(bool condition, string description)
    {
        if (!condition) throw new InvalidOperationException(description);
        Console.WriteLine("PASS " + description);
    }

    private static void ValidatedGrantsRemainUsableAndBounded()
    {
        var root = Granted();
        var direct = RootGrant() with { Id = "direct-target", Subject = "target", MembershipEpoch = "target-epoch" };
        var target = Member("target", "target-epoch");
        var consumer = root with { Actor = target, RequiredMembers = [Member()], Policy = root.Policy with { Grants = [direct] } };
        Expect(OrganizationAuthorizationPolicy.EvaluateUse(consumer, Ann), OrganizationAuthorizationOutcome.Allowed, "A root-issued grant to another member uses the issuer's current activation proof");
        var child = Child() with { Policy = Child().Policy with { Grants = [RootGrant(), ChildGrant() with { Ceiling = [Permission()] }] } };
        Expect(OrganizationAuthorizationPolicy.EvaluateDelegation(child, target, [Permission(false)], "grant-child"), OrganizationAuthorizationOutcome.Allowed, "A current delegate with both use and delegate can issue a bounded descendant grant");
        var descendant = new OrganizationGrant("descendant", 1, Scope, "target", "target-epoch", "officer", 1, [Permission(false)], ParentGrantId: "grant-child", ParentGrantVersion: 1);
        Expect(OrganizationAuthorizationValidation.ValidateGrant(child, 5, descendant, target).Decision, OrganizationAuthorizationOutcome.Allowed, "Ordinary current delegate validates a child-bound grant without becoming root");
        consumer = child with { Actor = target, RequiredMembers = [Member(), Member("child", "child-epoch")], Policy = child.Policy with { Grants = [.. child.Policy.Grants!, descendant] } };
        Expect(OrganizationAuthorizationPolicy.EvaluateUse(consumer, Ann), OrganizationAuthorizationOutcome.Allowed, "A validated ordinary descendant can consume its explicit capability");
        Expect(OrganizationAuthorizationPolicy.EvaluateUse(consumer with { RequiredMembers = [Member(), Member("child", "changed-epoch")] }, Ann), OrganizationAuthorizationOutcome.Denied, "Changed intermediate membership epoch retires descendants");
        var all = OrganizationCapabilityCatalog.Implemented.Select(id => new OrganizationCapabilityPermission(id, true, true)).ToArray();
        var adminRole = Role() with { Permissions = all };
        var admin = Child() with { Policy = Child().Policy with { Roles = [adminRole], Grants = [RootGrant() with { Ceiling = all }, ChildGrant() with { Ceiling = all }] } };
        Expect(OrganizationAuthorizationValidation.ValidateRoleChange(admin, 5, adminRole with { MetadataRevision = 2 }).Decision, OrganizationAuthorizationOutcome.Allowed, "An explicitly authorized ordinary role manager can edit metadata");
        var change = OrganizationAuthorizationValidation.ValidateRoleChange(admin with { Actor = Member(), RequiredMembers = [Member("child", "child-epoch")] }, 5, adminRole with { PermissionVersion = 2, Enabled = false });
        Check(change.RequiresGrantRevalidation && change.AffectedGrantIds.SequenceEqual(new[] { "grant-child", "grant-root" }), "Disabling a role identifies direct and descendant bindings for the same A2 transaction");
        var noAudit = new[] { Permission(false), new OrganizationCapabilityPermission(OrganizationCapabilityCatalog.ManageRoles, true, false) };
        var limited = admin with { Policy = admin.Policy with { Grants = [RootGrant() with { Ceiling = all }, ChildGrant() with { Ceiling = noAudit }] } };
        Expect(OrganizationAuthorizationValidation.ValidateRoleChange(limited, 5, adminRole with { PermissionVersion = 2, Permissions = [new(OrganizationCapabilityCatalog.ViewAudit, true, true)] }).Decision, OrganizationAuthorizationOutcome.Denied, "Role management does not let a delegate invent audit rights it cannot delegate");
        Expect(OrganizationAuthorizationPolicy.EvaluateDelegation(root, target with { Scope = Scope with { Sid = "FOREIGN" } }, [Permission(false)]), OrganizationAuthorizationOutcome.Invalid, "Cross-organization grant targets cannot inherit actor authority");
        Expect(OrganizationAuthorizationPolicy.EvaluateUse(root with { Policy = root.Policy with { Grants = [RootGrant() with { Ceiling = [] }] } }, Ann), OrganizationAuthorizationOutcome.Denied, "A role template never expands an empty explicit grant ceiling");
        var reenabled = root with { Policy = root.Policy with { Roles = [Role() with { Enabled = true, PermissionVersion = 3 }], Grants = [RootGrant()] } };
        Expect(OrganizationAuthorizationPolicy.EvaluateUse(reenabled, Ann), OrganizationAuthorizationOutcome.Denied, "Reenabled role does not restore an unrevalidated old binding");
    }

    private static void UnsafeGraphsReturnTypedFailure()
    {
        var c = Child();
        var orphan = RootGrant() with { ParentGrantId = "absent-parent", ParentGrantVersion = 1, RootActivationId = null, RootActivationVersion = null };
        Expect(OrganizationAuthorizationPolicy.EvaluateUse(c with { Policy = c.Policy with { Grants = [ChildGrant(), orphan] } }, Ann), OrganizationAuthorizationOutcome.Invalid, "An indirect missing parent returns Invalid without throwing");
        Expect(OrganizationAuthorizationPolicy.EvaluateUse(Context(), Ann), OrganizationAuthorizationOutcome.Denied, "Known empty ordinary policy is denied without reclassifying unconfigured root facts");
        Expect(OrganizationAuthorizationPolicy.EvaluateUse(c with { Policy = c.Policy with { ReadState = OrganizationPolicyReadState.Unavailable } }, Ann), OrganizationAuthorizationOutcome.Unavailable, "Unreadable stored policy is unavailable for ordinary use");
        Expect(OrganizationAuthorizationPolicy.EvaluateUse(c with { RequiredMembers = [Member() with { ValidUntil = Now }] }, Ann), OrganizationAuthorizationOutcome.Unavailable, "Expired ancestor evidence cannot be renewed by a stored grant");
        Expect(OrganizationAuthorizationPolicy.EvaluateUse(c with { Root = Eligible() with { ValidUntil = Now } }, Ann), OrganizationAuthorizationOutcome.Unavailable, "Expired independent root proof suspends descendant use");
        Expect(OrganizationAuthorizationPolicy.EvaluateUse(c with { Policy = c.Policy with { Roles = [Role(), Role()] } }, Ann), OrganizationAuthorizationOutcome.Invalid, "Duplicate role keys are invalid rather than arbitrary first-match permissions");
        Expect(OrganizationAuthorizationPolicy.EvaluateUse(c with { RequiredMembers = [Member(), Member()] }, Ann), OrganizationAuthorizationOutcome.Invalid, "Duplicate authoritative member facts are ambiguous and invalid");
        Expect(OrganizationAuthorizationPolicy.EvaluateUse(c with { Policy = c.Policy with { Activations = [Activation() with { Version = 2 }] } }, Ann), OrganizationAuthorizationOutcome.Denied, "Root activation version change invalidates old grant provenance");
        Expect(OrganizationAuthorizationPolicy.EvaluateUse(c with { Root = Eligible() with { Basis = "new-selected-basis" } }, Ann), OrganizationAuthorizationOutcome.Denied, "A changed root basis requires explicit revalidation of persisted provenance");
    }

    private static void ManagementCannotEscapeGrantProvenance()
    {
        var all = OrganizationCapabilityCatalog.Implemented.Select(id => new OrganizationCapabilityPermission(id, true, true)).ToArray();
        var officer = Role() with { Permissions = all };
        var manager = Role() with { Key = "manager", Permissions = [new(OrganizationCapabilityCatalog.ManageRoles, true, false)] };
        var managerGrant = ChildGrant() with { RoleKey = "manager", Ceiling = manager.Permissions };
        var c = Child() with { Policy = Child().Policy with { Roles = [officer, manager], Grants = [RootGrant() with { Ceiling = all }, managerGrant] } };
        Expect(OrganizationAuthorizationValidation.ValidateRevoke(c, 5, "grant-root").Decision, OrganizationAuthorizationOutcome.Denied, "roles.manage use alone cannot revoke a higher-level grant");
        var sibling = ChildGrant() with { Id = "sibling", Subject = "sibling", MembershipEpoch = "sibling-epoch" };
        c = c with { Policy = c.Policy with { Grants = [.. c.Policy.Grants!, sibling] } };
        Expect(OrganizationAuthorizationValidation.ValidateRevoke(c, 5, "sibling").Decision, OrganizationAuthorizationOutcome.Denied, "Metadata manager cannot revoke unrelated sibling provenance");
        Expect(OrganizationAuthorizationValidation.ValidateRoleChange(c, 5, officer with { Enabled = false, PermissionVersion = 2 }).Decision, OrganizationAuthorizationOutcome.Denied, "Metadata manager cannot disable a role carrying capabilities it cannot delegate");
        var bound = Child() with { Policy = Child().Policy with { Roles = [officer], Grants = [RootGrant() with { Ceiling = all }, ChildGrant() with { Ceiling = all }] } };
        Expect(OrganizationAuthorizationValidation.ValidateRevoke(bound, 5, "grant-root").Decision, OrganizationAuthorizationOutcome.Denied, "Even matching ordinary rights cannot cross the ancestor provenance boundary");
        Expect(OrganizationAuthorizationValidation.ValidateRoleChange(bound, 5, officer with { Enabled = false, PermissionVersion = 2 }).Decision, OrganizationAuthorizationOutcome.Denied, "A delegate cannot mutate a shared template that would revoke its issuer's grant");
        var ownedRole = Role() with { Key = "owned-child" };
        var owned = ChildGrant() with { Id = "owned", Subject = "target", MembershipEpoch = "target-epoch", RoleKey = "owned-child", ParentGrantId = "grant-child" };
        bound = bound with { Policy = bound.Policy with { Roles = [officer, ownedRole], Grants = [.. bound.Policy.Grants!, owned] } };
        Expect(OrganizationAuthorizationValidation.ValidateRevoke(bound, 5, "owned").Decision, OrganizationAuthorizationOutcome.Allowed, "Current use and delegate allow revoking a grant in one's own child chain");
        Expect(OrganizationAuthorizationValidation.ValidateRoleChange(bound, 5, ownedRole with { Enabled = false, PermissionVersion = 2 }).Decision, OrganizationAuthorizationOutcome.Allowed, "Role manager with current delegation can disable only its bounded child template");
        Expect(OrganizationAuthorizationValidation.ValidateRevoke(bound with { Root = new(OrganizationRootEligibilityState.Unavailable) }, 5, "owned").Decision, OrganizationAuthorizationOutcome.Unavailable, "Unknown required root prevents management without fabricating known revocation");
    }

    private static void RoleVersionOverflowDoesNotValidateAnInvalidBinding()
    {
        var c = Granted();
        c = c with { Policy = c.Policy with { Roles = [Role() with { PermissionVersion = int.MaxValue }],
            Grants = [RootGrant() with { RolePermissionVersion = int.MaxValue }] } };
        var invalid = Role() with { PermissionVersion = int.MinValue, Permissions = [Permission(false)] };
        Expect(OrganizationAuthorizationValidation.ValidateRoleChange(c, 5, invalid).Decision, OrganizationAuthorizationOutcome.Invalid, "Permission-version overflow cannot validate a negative new binding");
    }

    private static void SnapshotShapeNeverRequiresOrGrantsCurrentAuthority()
    {
        Expect(OrganizationAuthorizationValidation.ValidateSnapshotShape(Context().Policy), OrganizationAuthorizationOutcome.Allowed, "Explicit known-empty policy has valid shape without an actor or root proof");
        Expect(OrganizationAuthorizationValidation.ValidateSnapshotShape(Granted().Policy), OrganizationAuthorizationOutcome.Allowed, "Persisted grants can be shape-validated without inventing current member evidence");
        Expect(OrganizationAuthorizationValidation.ValidateSnapshotShape(Context().Policy with { ReadState = OrganizationPolicyReadState.Unavailable }), OrganizationAuthorizationOutcome.Unavailable, "Unreadable snapshot is never shape-valid known empty");
        Expect(OrganizationAuthorizationValidation.ValidateSnapshotShape(Child().Policy with { Grants = [ChildGrant()] }), OrganizationAuthorizationOutcome.Invalid, "Shape-only validation rejects unresolved parent policy references");
        Expect(OrganizationAuthorizationValidation.ValidateSnapshotShape(Granted().Policy with { Roles = [Role(), Role()] }), OrganizationAuthorizationOutcome.Invalid, "Shape-only validation rejects duplicate roles before storage restore");
        Expect(OrganizationAuthorizationPolicy.EvaluateUse(Granted() with { Root = new(OrganizationRootEligibilityState.Unconfigured) }, Ann), OrganizationAuthorizationOutcome.Unavailable, "Shape-valid persisted activation never becomes current root authority");
    }
    private static void RoleAuthorityPreflightRemainsBoundedAndSeparate()
    {
        var context = Granted();
        Expect(OrganizationAuthorizationValidation.EvaluateRoleChangeAuthority(context, [Permission()], []), OrganizationAuthorizationOutcome.Allowed,
            "Current role authority preflight does not require a new resource version");
        Expect(OrganizationAuthorizationValidation.EvaluateRoleChangeAuthority(context, [Permission(), Permission()], []), OrganizationAuthorizationOutcome.Invalid,
            "Authority preflight rejects duplicate rights");
        Expect(OrganizationAuthorizationValidation.EvaluateRoleChangeAuthority(context, [], ["missing"]), OrganizationAuthorizationOutcome.Invalid,
            "Authority preflight cannot accept unknown affected grants");
        Expect(OrganizationAuthorizationValidation.EvaluateRoleChangeAuthority(context, [], ["grant-root", "grant-root"]), OrganizationAuthorizationOutcome.Invalid,
            "Authority preflight rejects repeated affected references");
        var rolePermission = new OrganizationCapabilityPermission(OrganizationCapabilityCatalog.ManageRoles, true, false);
        var metaRole = new OrganizationRoleDefinition("metadata", Scope, 1, 1, true, [rolePermission]);
        var metadataGrant = new OrganizationGrant("metadata-child", 1, Scope, "child", "child-epoch", "metadata", 1, [rolePermission],
            RootActivationId: "activation-1", RootActivationVersion: 1);
        var manager = Child() with { Policy = context.Policy with { Roles = [Role(), metaRole], Grants = [RootGrant(), metadataGrant] } };
        Expect(OrganizationAuthorizationValidation.EvaluateRoleChangeAuthority(manager, [], []), OrganizationAuthorizationOutcome.Allowed,
            "A metadata manager may manage display metadata with no delegation claim");
        Expect(OrganizationAuthorizationValidation.EvaluateRoleChangeAuthority(manager, [Permission()], []), OrganizationAuthorizationOutcome.Denied,
            "Metadata use cannot create a template containing rights the actor cannot delegate");
        Expect(OrganizationAuthorizationValidation.ValidateRoleChange(manager, manager.Policy.Revision,
            Role() with { Key = "new-role" }).Decision, OrganizationAuthorizationOutcome.Denied,
            "Calling authority preflight with no rights never bypasses full new-role validation");
    }

}
