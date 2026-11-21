using StarBridge.Core.Profiles;

namespace StarBridge.HostRuntime.Account;

/// <summary>Host decoration on a successfully authorized visitor document.</summary>
internal sealed record VisitorPersonalProfileResult(
    PersonalProfileDocumentContract Profile, PersonalProfilePublicFacts? AccountFacts = null,
    PersonalProfileTradeWindow? TradeWindow = null);
