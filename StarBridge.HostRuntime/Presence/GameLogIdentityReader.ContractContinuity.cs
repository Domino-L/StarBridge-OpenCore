namespace StarBridge.HostRuntime.Presence;

public sealed partial class GameLogIdentityReader
{
    private string? _contractPath;
    private string? _contractFileIdentity;
    private DateTimeOffset? _contractFirstTimestamp;
    private bool _contractCoverageFromStart;
    internal bool ContractOwnershipCovered => _following && _contractCoverageFromStart;
    // Valid for the final private batch after a clean quit as well as live reads.
    internal string? ContractPlayerId => !_invalidIdentityEvidence && _identities.Count == 1
        ? _identities.Single().Key.Id : null;
    internal string? CleanlyEndedContractHandle => _quit && _following && !_invalidIdentityEvidence &&
        _identities.Count == 1 && _line.Count == 0 && !_longLine && _contractNotification is null
            ? _identities.Single().Value : null;
    internal event Action<string?, bool, bool>? ContractSourceEnded;

    private void InterruptContracts()
    {
        _contractCoverageFromStart = false;
        _contractFirstTimestamp ??= DateTimeOffset.MaxValue;
        ContractReadInterrupted?.Invoke();
    }

    // Only normal incremental reads may consume evidence. At a process/source boundary,
    // Compare identity AND length from the same handle; never open/read its tail.
    // A normal read can supply its paired metadata. Otherwise query metadata only,
    // closing that handle before callbacks; no content IO or retained boundary handle.
    private void EndContractSource(bool reliableTransition = true,
        (string Identity, long Length)? sourceMetadata = null)
    {
        if (_session?.TracksContracts != true || _source is null) return;
        var complete = false;
        try
        {
            if (reliableTransition && _contractPath is not null && _contractFileIdentity is not null)
            {
                var metadata = sourceMetadata ?? ReadContractSourceMetadata();
                complete = metadata.Identity == _contractFileIdentity && metadata.Length == _position &&
                    _following && !_invalidIdentityEvidence &&
                    _identities.Count == 1 && _line.Count == 0 && !_longLine && _contractNotification is null;
            }
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or GameplayTimeException) { }
        var handle = !_invalidIdentityEvidence && _identities.Count == 1 ? _identities.Single().Value : null;
        ContractSourceEnded?.Invoke(handle, complete, complete && ContractOwnershipCovered);
        if (!complete) InterruptContracts();
    }

    private (string Identity, long Length) ReadContractSourceMetadata()
    {
        using var handle = CheckedGameLogAccess.OpenChecked(_contractPath!, directory: false, readContent: false);
        if (!GetFileInformationByHandle(handle, out var info) ||
            (info.IndexHigh == 0 && info.IndexLow == 0) || (_strictLocalEvidence && info.Links != 1))
            throw new IOException();
        var identity = _strictLocalEvidence ? CheckedGameLogAccess.PersistentIdentity(handle) :
            info.Volume + ":" + info.IndexHigh + ":" + info.IndexLow;
        return (identity, ((long)info.SizeHigh << 32) | info.SizeLow);
    }
}
