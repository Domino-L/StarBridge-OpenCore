using StarBridge.HostRuntime.Privacy;

namespace StarBridge.HostRuntime;

public sealed partial class AccountBridgeRuntime
{
    // Default protocol availability is not publication consent. Explicit false
    // (and malformed non-null values) retain the existing emergency off switch.
    internal static bool OfficialRealtimeEnabledByConfiguration(string? value) =>
        value is null || string.Equals(value, "true", StringComparison.OrdinalIgnoreCase);

    private OfficialFleetRealtimePrivacyBridge? _officialRealtimePrivacy;
    // Protocol transport only. Relay enablement/current authority is established
    // by each successful context/schema2 read, never by these Ready names.
    // Retain this existing native composition seam; it now also supplies observed
    // governance protocol support, independently of realtime configuration.
    public IReadOnlyList<string> OfficialFleetRealtimeCapabilities =>
        [.. (_host is Account.ScmAccountBridgeHost { HasOfficialRealtimeProtocol: true } && _officialRealtimePrivacy is not null
            ? new[] { "privacy.officialFleetScopes", "officialFleet.runtimeMembers", "officialFleet.runtimeActivity" } : []),
         .. (_officialRealtimePrivacy is { AudienceSupported: true } ? new[] { "privacy.officialFleetAudience" } : []),
         .. (_host is Account.ScmAccountBridgeHost scm ? scm.GovernanceCapabilities : [])];

    // Everything this owner adds to the Host's static list. Game identity is an
    // account capability, separate from the fleet protocol reported above.
    public IReadOnlyList<string> AdditionalHostCapabilities =>
        [.. OfficialFleetRealtimeCapabilities,
         .. (!_disposed && !_firstUseCandidate && !RetainsFirstUseSession &&
             _host is Account.ScmAccountBridgeHost { HasGameIdentityBridge: true }
             ? new[] { Account.GameIdentityBridge.Capability } : [])];
}
