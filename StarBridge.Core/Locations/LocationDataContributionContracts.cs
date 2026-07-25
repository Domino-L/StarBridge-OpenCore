namespace StarBridge.Core.Locations;

public enum LocationCodeSourceContract
{
    NavigationTarget,
    RouteStart,
    InventoryLocation
}

public sealed record LocationCodeObservationContract(
    string Code,
    LocationCodeSourceContract Source);

public sealed record LocationPairObservationContract(
    string QuantumTargetCode,
    string ActualLocationCode,
    int ArrivalToConfirmationSeconds);

public sealed record LocationDataContributionRequestContract(
    string ClientId,
    LocationCodeObservationContract[] Codes,
    LocationPairObservationContract[] Pairs);

public sealed record LocationDataContributionResponseContract(
    int AcceptedCodes,
    int AcceptedPairs,
    int KnownCodes,
    int CandidatePairs,
    DateTimeOffset UpdatedAt);
