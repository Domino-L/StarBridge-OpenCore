namespace StarBridge.Desktop;

internal sealed record HangarPageScanObservation(
    int Page,
    int ContentItemCount,
    string CandidateSignature);

internal static class HangarPageScanPolicy
{
    internal static bool IsStable(
        int expectedPage,
        HangarPageScanObservation current,
        HangarPageScanObservation? previous)
    {
        return current.Page == expectedPage &&
               current.ContentItemCount > 0 &&
               previous?.Page == current.Page &&
               previous.ContentItemCount == current.ContentItemCount &&
               string.Equals(
                   previous.CandidateSignature,
                   current.CandidateSignature,
                   StringComparison.OrdinalIgnoreCase);
    }
}
