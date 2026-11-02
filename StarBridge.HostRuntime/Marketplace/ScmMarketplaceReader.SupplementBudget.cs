using System.Text.Json;

namespace StarBridge.HostRuntime.Marketplace;

internal sealed partial class ScmMarketplaceReader
{
    private async Task<JsonElement> GetQualitySupplement(string route, bool userTriggered, CancellationToken ct, QualityWork work)
    {
        // Refuse exhausted budgets before waiting for concurrency. Admission is checked again
        // in Get immediately before SendAsync, so queued work cannot escape a pause or window.
        lock (_categoryLock)
        {
            PruneCategories();
            if (CategoriesPaused(MonotonicTime.GetTimestamp()) ||
                (userTriggered ? _userQualityRequests.Count >= 60 : _categoryRequests.Count >= 30))
                throw new CategoryBudgetUnavailableException();
        }
        await _categoryGate.WaitAsync(ct);
        Task<JsonElement>? transport = null;
        try
        {
            transport = Get(route, ct, () => AdmitCategoryRequest(userTriggered));
            work.Transports.Add(transport);
            return await transport.WaitAsync(ct);
        }
        finally
        {
            // Share the metadata three-slot gate, retaining slots for uncooperative transports.
            // The unchanged four-slot global gate therefore always leaves one for main reads.
            if (transport is { IsCompleted: false })
                _ = transport.ContinueWith(t =>
                {
                    _ = t.Exception;
                    _categoryGate.Release();
                }, TaskScheduler.Default);
            else _categoryGate.Release();
        }
    }
}
