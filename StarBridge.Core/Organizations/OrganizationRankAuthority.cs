namespace StarBridge.Core.Organizations;

// Trusted adapter evidence only. Display ranks and persisted roles are never rank proof.
public static class OrganizationRankAuthority
{
    public const string LegacyDefinition = "SCM_RSI_UNIQUE_TOP_RANK_V1";
    public const string LegacyBasis = "rsiUniqueTopRank";
    public const string Definition = "SCM_RSI_RANK_V2";
    public const string Basis = "scmRankValue";
    public const string StaleReason = "membershipEvidenceStale";

    // Reuses V2 binding and freshness checks without granting management powers.
    public static int? CurrentValue(OrganizationRootEligibilityEvidence proof,
        OrganizationMembershipEvidence member, DateTimeOffset now)
    {
        var context = new OrganizationAuthorizationContext(member, proof,
            new(OrganizationPolicyReadState.Available, 0, member.Scope), now);
        return member.State == OrganizationMembershipState.Current &&
            OrganizationAuthorizationValidation.Fresh(member.ObservedAt, member.ValidUntil, now, "membership").Outcome == OrganizationAuthorizationOutcome.Allowed &&
            proof.ObservedAt is { } observed && now - observed <= TimeSpan.FromHours(48) &&
            Current(proof, member, context) ? proof.RankValue : null;
    }

    internal static bool Current(OrganizationRootEligibilityEvidence proof,
        OrganizationMembershipEvidence member, OrganizationAuthorizationContext context) =>
        proof.ProofDefinition == Definition && proof.Basis == Basis && proof.RankValue is >= 1 and <= 6 &&
        proof.State == (proof.RankValue == 1 ? OrganizationRootEligibilityState.Eligible : OrganizationRootEligibilityState.Ineligible) &&
        proof.Reason != StaleReason && proof.Subject == member.Subject && proof.Scope == member.Scope &&
        proof.MembershipEpoch == member.MembershipEpoch && proof.ObservedAt is { } observed && proof.ValidUntil is { } until &&
        OrganizationAuthorizationValidation.Fresh(observed, until, context.Now, "rank").Outcome == OrganizationAuthorizationOutcome.Allowed;

    public static string Role(OrganizationAuthorizationContext context)
    {
        if (OrganizationAuthorizationValidation.ContextState(context).Outcome != OrganizationAuthorizationOutcome.Allowed)
            return "member";
        if (Current(context.Root, context.Actor, context)) return context.Root.RankValue switch
        {
            1 => "leader", <= 3 => "admin", 4 => "editor", _ => "member"
        };
        return context.Root.ProofDefinition == LegacyDefinition &&
            OrganizationAuthorizationValidation.Root(context.Root, context.Actor, context).Outcome == OrganizationAuthorizationOutcome.Allowed
            ? "leader" : "member";
    }

    internal static bool LegacyGrantBinding(OrganizationRootActivation activation, OrganizationRootEligibilityEvidence proof) =>
        activation.ProofDefinition == LegacyDefinition && activation.Basis == LegacyBasis &&
        proof.ProofDefinition == Definition && proof.Basis == Basis;
}
