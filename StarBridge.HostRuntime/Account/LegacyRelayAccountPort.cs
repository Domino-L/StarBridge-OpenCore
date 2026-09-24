namespace StarBridge.HostRuntime.LegacyRelay;

using StarBridge.Core.Profiles;
using StarBridge.HostRuntime.Auth;

internal enum LegacyRelayAccessState
{
    Ready,
    Unavailable,
    AuthorizationRequired,
    AccountMismatch,
    NotEstablished
}

internal sealed record LegacyRelayProfileReadResult(
    LegacyRelayAccessState State,
    PersonalProfileDocumentContract? Profile = null);

/// <summary>
/// Owns the compatibility lease between one SCM account and one legacy Relay
/// account. The SCM bearer remains inside the Host and is never copied into a
/// second persisted session.
/// </summary>
internal interface ILegacyRelayAccountPort
{
    Task<LegacyRelayAccessState> EstablishAsync(
        ScmOAuthSession session,
        string expectedLegacyAccountId,
        CancellationToken cancellationToken);

    Task<LegacyRelayProfileReadResult> ReadOwnProfileAsync(
        ScmOAuthSession session,
        string expectedLegacyAccountId,
        CancellationToken cancellationToken);

    void Reset();
}

internal sealed class UnavailableLegacyRelayAccountPort : ILegacyRelayAccountPort
{
    internal static UnavailableLegacyRelayAccountPort Instance { get; } = new();

    private UnavailableLegacyRelayAccountPort()
    {
    }

    public Task<LegacyRelayAccessState> EstablishAsync(
        ScmOAuthSession session,
        string expectedLegacyAccountId,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        return Task.FromResult(LegacyRelayAccessState.Unavailable);
    }

    public Task<LegacyRelayProfileReadResult> ReadOwnProfileAsync(
        ScmOAuthSession session,
        string expectedLegacyAccountId,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        return Task.FromResult(
            new LegacyRelayProfileReadResult(LegacyRelayAccessState.Unavailable));
    }

    public void Reset()
    {
    }
}
