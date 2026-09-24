using System.Security.Cryptography;
using System.Text.Json;

namespace StarBridge.Core.Hangar;

public sealed record HangarItemObservation(string Title, string? Kind, string? Liner);
public sealed record HangarPledgeObservation(string SourceKey, string? AcquiredText, IReadOnlyList<HangarItemObservation> Items);
public sealed record HangarPageObservation(int Page, int? TotalPages, int? NextPage, bool Unfiltered, IReadOnlyList<HangarPledgeObservation> Pledges);
public sealed record CollectedHangarShip(string PledgeKey, int ItemIndex, string Title, string? Liner, string? AcquiredText);

public enum HangarScanState { Collecting, VerifyingFirstPage, Complete, NeedsReview, Invalid, Cancelled, TimedOut }
public enum HangarScanIssue { None, InvalidObservation, Filtered, UnconfirmedEmpty, PaginationChanged, MissingPaginationProof, DuplicatePledge, PageChanged, LimitExceeded }
public sealed record HangarScanSnapshot(
    HangarScanState State, HangarScanIssue Issue, int ExpectedPage, int? TotalPages,
    IReadOnlyList<HangarPageObservation> Pages, IReadOnlyList<CollectedHangarShip> Ships, int UnclassifiedCount)
{
    // Local data readiness only: not a server permission, ownership proof or save command.
    public bool IsComplete => State == HangarScanState.Complete;
}

/// <summary>
/// One serialized local scan. Call only after Host identity/source/generation checks.
/// Two independently captured observations must agree per page. Multi-page scans
/// finish by rechecking page one. Nothing here reads a browser or changes a saved hangar.
/// ItemIndex is a locator within this observation, NEVER a stable ship instance ID.
/// </summary>
public sealed class HangarScanSession
{
    public const int MaximumPages = 100;
    public const int MaximumPledgesPerPage = 200;
    public const int MaximumItemsPerPage = 2000;
    public const int MaximumTotalItems = 20000;
    public const int MaximumPageBytes = 512 * 1024;
    public const int MaximumCaptures = 1000;
    public static readonly TimeSpan MaximumDuration = TimeSpan.FromMinutes(10);

    private readonly TimeProvider _clock;
    private readonly long _started;
    private readonly List<HangarPageObservation> _pages = [];
    private readonly List<string> _fingerprints = [];
    private readonly HashSet<string> _pledgeKeys = new(StringComparer.Ordinal);
    private HangarScanState _state = HangarScanState.Collecting;
    private HangarScanIssue _issue;
    private int _expectedPage = 1;
    private int? _totalPages;
    private ulong _lastCapture;
    private int _captures;
    private int _totalItems;
    private string? _pendingFingerprint;

    public HangarScanSession(TimeProvider? clock = null)
    {
        _clock = clock ?? TimeProvider.System;
        _started = _clock.GetTimestamp();
    }

    public void Cancel()
    {
        if (!Terminal) { _state = HangarScanState.Cancelled; _pendingFingerprint = null; }
    }

    public HangarScanSnapshot Snapshot
    {
        get
        {
            CheckDeadline();
            var ships = new List<CollectedHangarShip>();
            var unclassified = 0;
            foreach (var page in _pages)
            foreach (var pledge in page.Pledges)
            {
                if (pledge.Items.Count == 0) unclassified++;
                for (var index = 0; index < pledge.Items.Count; index++)
                {
                    var item = pledge.Items[index];
                    var kind = item.Kind?.Trim().ToLowerInvariant();
                    if (kind is "ship" or "飞船")
                        ships.Add(new(pledge.SourceKey, index, item.Title, item.Liner, pledge.AcquiredText));
                    else if (kind is not ("fps equipment" or "skin" or "insurance")) unclassified++;
                }
            }
            return new(_state, _issue, _expectedPage, _totalPages, Array.AsReadOnly(_pages.ToArray()), ships.AsReadOnly(), unclassified);
        }
    }

    public HangarScanSnapshot Observe(ulong captureId, HangarPageObservation observation)
    {
        CheckDeadline();
        if (Terminal || captureId <= _lastCapture) return Snapshot;
        _lastCapture = captureId;
        if (++_captures > MaximumCaptures) return Fail(HangarScanIssue.LimitExceeded);
        var issue = Validate(observation);
        if (issue != HangarScanIssue.None) return Fail(issue);
        var page = Freeze(observation);
        var bytes = JsonSerializer.SerializeToUtf8Bytes(page);
        if (bytes.Length > MaximumPageBytes) return Fail(HangarScanIssue.LimitExceeded);
        var fingerprint = Convert.ToHexString(SHA256.HashData(bytes));
        if (_totalPages is not null && page.TotalPages is not null && page.TotalPages != _totalPages)
            return Fail(HangarScanIssue.PaginationChanged);
        if (page.Page != _expectedPage)
        {
            // Replayed accepted pages do not add instances or count as a fresh sample.
            if (page.Page <= _pages.Count && _fingerprints[page.Page - 1] == fingerprint) return Snapshot;
            return Fail(page.Page <= _pages.Count ? HangarScanIssue.PageChanged : HangarScanIssue.InvalidObservation);
        }
        if (_totalPages is not null && page.Page > _totalPages) return Fail(HangarScanIssue.PaginationChanged);
        if (_pendingFingerprint != fingerprint) { _pendingFingerprint = fingerprint; return Snapshot; }
        _pendingFingerprint = null;
        if (_state == HangarScanState.VerifyingFirstPage)
        {
            if (_fingerprints[0] != fingerprint) return Fail(HangarScanIssue.PageChanged);
            Finish();
            return Snapshot;
        }

        _totalPages ??= page.TotalPages;
        if (page.NextPage is null && (_totalPages is null || page.Page != _totalPages))
            return Fail(_totalPages is null ? HangarScanIssue.MissingPaginationProof : HangarScanIssue.PaginationChanged);
        if (page.NextPage is not null && _totalPages is not null && page.Page >= _totalPages)
            return Fail(HangarScanIssue.PaginationChanged);
        if (page.Pledges.Any(p => _pledgeKeys.Contains(p.SourceKey))) return Fail(HangarScanIssue.DuplicatePledge);
        var count = page.Pledges.Sum(p => p.Items.Count);
        if (_totalItems + count > MaximumTotalItems) return Fail(HangarScanIssue.LimitExceeded);
        foreach (var pledge in page.Pledges) _pledgeKeys.Add(pledge.SourceKey);
        _pages.Add(page);
        _fingerprints.Add(fingerprint);
        _totalItems += count;
        if (page.NextPage is int next) _expectedPage = next;
        else if (_pages.Count == 1) Finish();
        else { _state = HangarScanState.VerifyingFirstPage; _expectedPage = 1; }
        return Snapshot;
    }

    private void Finish()
    {
        CheckDeadline();
        // Match WPF extraction: only Ship/飞船 items form the inventory. Other
        // package contents need no classification and must not gate publication.
        // UnclassifiedCount remains diagnostic/legacy protocol data only.
        if (!Terminal) _state = HangarScanState.Complete;
    }
    private bool Terminal => _state is not (HangarScanState.Collecting or HangarScanState.VerifyingFirstPage);
    private void CheckDeadline()
    {
        if (!Terminal && _clock.GetElapsedTime(_started) >= MaximumDuration)
        { _state = HangarScanState.TimedOut; _pendingFingerprint = null; }
    }
    private HangarScanSnapshot Fail(HangarScanIssue issue)
    { _state = HangarScanState.Invalid; _issue = issue; _pendingFingerprint = null; return Snapshot; }
    private static bool Text(string? value, int maximum, bool required = false) =>
        (!required || !string.IsNullOrWhiteSpace(value)) && (value is null || value.Length <= maximum && !value.Any(char.IsControl));
    private static HangarScanIssue Validate(HangarPageObservation page)
    {
        if (page is null || page.Page < 1 || page.TotalPages is < 1 || page.TotalPages < page.Page ||
            page.NextPage is not null && page.NextPage != page.Page + 1 || page.Pledges is null)
            return HangarScanIssue.InvalidObservation;
        if (page.Page > MaximumPages || page.TotalPages > MaximumPages || page.NextPage > MaximumPages ||
            page.Pledges.Count > MaximumPledgesPerPage) return HangarScanIssue.LimitExceeded;
        if (!page.Unfiltered) return HangarScanIssue.Filtered;
        if (page.Pledges.Count == 0) return HangarScanIssue.UnconfirmedEmpty;
        var keys = new HashSet<string>(StringComparer.Ordinal);
        var count = 0;
        foreach (var pledge in page.Pledges)
        {
            if (pledge is null || !Text(pledge.SourceKey, 128, true) || !Text(pledge.AcquiredText, 128) || pledge.Items is null)
                return HangarScanIssue.InvalidObservation;
            if (!keys.Add(pledge.SourceKey)) return HangarScanIssue.DuplicatePledge;
            if (pledge.Items.Count > MaximumItemsPerPage || (count += pledge.Items.Count) > MaximumItemsPerPage)
                return HangarScanIssue.LimitExceeded;
            foreach (var item in pledge.Items)
                if (item is null || !Text(item.Title, 256, true) || !Text(item.Kind, 64) || !Text(item.Liner, 256))
                    return HangarScanIssue.InvalidObservation;
        }
        return HangarScanIssue.None;
    }
    private static HangarPageObservation Freeze(HangarPageObservation page) => page with {
        Pledges = Array.AsReadOnly(page.Pledges.Select(p => p with { Items = Array.AsReadOnly(p.Items.ToArray()) }).ToArray())
    };
}
