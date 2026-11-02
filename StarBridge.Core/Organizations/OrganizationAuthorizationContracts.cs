namespace StarBridge.Core.Organizations;

public enum OrganizationAuthorizationOutcome { Allowed, Denied, Unavailable, Invalid, Conflict }
public sealed record OrganizationAuthorizationDecision(OrganizationAuthorizationOutcome Outcome, string Reason, string? GrantId = null);
public enum OrganizationMembershipState { Current, NotCurrent, Unavailable }
public enum OrganizationRootEligibilityState { Unconfigured, Unavailable, Ineligible, Eligible }
public enum OrganizationPolicyReadState { Available, Unavailable }
public enum OrganizationRootControl { Activate, Recover, Delegate }

public sealed record OrganizationAuthorizationScope(string AuthorityNamespace, long OrganizationId, string Sid);

// Trusted in-process observations, never request/Bridge DTOs. The Server adapter
// binds the authenticated subject and authority source; display ranks are not evidence.
public sealed record OrganizationMembershipEvidence(OrganizationMembershipState State, string Subject,
    OrganizationAuthorizationScope Scope, string MembershipEpoch, DateTimeOffset ObservedAt,
    DateTimeOffset ValidUntil, string SourceDefinition = "");

// Adapter validity is independent from G1 display consent and its five-second TTL.
public sealed record OrganizationRootEligibilityEvidence(OrganizationRootEligibilityState State,
    string? Basis = null, string? Subject = null, OrganizationAuthorizationScope? Scope = null,
    string? MembershipEpoch = null, string? ProofDefinition = null,
    DateTimeOffset? ObservedAt = null, DateTimeOffset? ValidUntil = null,
    int? RankValue = null, string? Reason = null);

public sealed record OrganizationRootActivation(string Id, long Version, string Subject,
    string MembershipEpoch, string Basis, string ProofDefinition, bool Revoked = false);

public sealed record OrganizationCapabilityPermission(string Capability, bool CanUse, bool CanDelegate);
public sealed record OrganizationRankPermission(int RankValue, bool Announcements, bool Rally, bool Audit);
public sealed record OrganizationRoleDefinition(string Key, OrganizationAuthorizationScope Scope,
    int PermissionVersion, long MetadataRevision, bool Enabled, IReadOnlyList<OrganizationCapabilityPermission> Permissions);
public sealed record OrganizationGrant(string Id, long Version, OrganizationAuthorizationScope Scope,
    string Subject, string MembershipEpoch, string RoleKey, int RolePermissionVersion,
    IReadOnlyList<OrganizationCapabilityPermission> Ceiling, string? ParentGrantId = null,
    long? ParentGrantVersion = null, string? RootActivationId = null, long? RootActivationVersion = null,
    bool Revoked = false, DateTimeOffset? ExpiresAt = null);

// A known empty policy and an unreadable policy are different facts. Activations
// are provenance, never reusable current root eligibility evidence.
public sealed record OrganizationAuthorizationSnapshot(OrganizationPolicyReadState ReadState, long Revision,
    OrganizationAuthorizationScope? Scope = null, IReadOnlyList<OrganizationRootActivation>? Activations = null,
    IReadOnlyList<OrganizationRoleDefinition>? Roles = null, IReadOnlyList<OrganizationGrant>? Grants = null,
    [property: System.Text.Json.Serialization.JsonIgnore(Condition = System.Text.Json.Serialization.JsonIgnoreCondition.WhenWritingNull)]
    IReadOnlyList<OrganizationRankPermission>? RankPermissions = null);

public sealed record OrganizationAuthorizationContext(OrganizationMembershipEvidence Actor,
    OrganizationRootEligibilityEvidence Root, OrganizationAuthorizationSnapshot Policy, DateTimeOffset Now,
    IReadOnlyList<OrganizationMembershipEvidence>? RequiredMembers = null,
    IReadOnlyList<OrganizationRootEligibilityEvidence>? RequiredRoots = null);

// Pure preflight, never a persistence lease. A2 must recheck under its CAS transaction.
public sealed record OrganizationPolicyChangeValidation(OrganizationAuthorizationDecision Decision,
    long ExpectedRevision, IReadOnlyList<string> AffectedGrantIds, bool RequiresGrantRevalidation = false);
