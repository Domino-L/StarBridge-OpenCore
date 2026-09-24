using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace StarBridge.HostRuntime.Communities;

internal sealed partial class CommunityClient
{
    private readonly object _membershipReadLock = new();
    private readonly Dictionary<(string Scope, string Credential), MembershipRead> _membershipReads = new();
    private bool _membershipReadsDisposed;

    private sealed class MembershipRead
    {
        internal readonly CancellationTokenSource Cancellation = new();
        internal readonly TaskCompletionSource<JsonElement[]> Result = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal int Consumers;
    }

    // Only overlapping read operations share work. Never retain completed permission
    // snapshots; mutation preflights deliberately keep using WpfS2Membership directly.
    private async Task<JsonElement[]> ReadWpfS2MembershipShared(string bearer, string scope, CancellationToken token)
    {
        token.ThrowIfCancellationRequested();
        var key = (scope, Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(bearer))));
        MembershipRead read;
        bool start;
        lock (_membershipReadLock)
        {
            ObjectDisposedException.ThrowIf(_membershipReadsDisposed, this);
            start = !_membershipReads.TryGetValue(key, out read!);
            if (start) _membershipReads.Add(key, read = new());
            read.Consumers++;
        }
        if (start) _ = CompleteMembershipRead(key, read, bearer);
        try { return await read.Result.Task.WaitAsync(token); }
        finally
        {
            var cancel = false;
            lock (_membershipReadLock)
            {
                if (--read.Consumers == 0 && _membershipReads.TryGetValue(key, out var current) && ReferenceEquals(current, read))
                {
                    _membershipReads.Remove(key);
                    cancel = true;
                }
            }
            if (cancel) CancelMembershipRead(read);
        }
    }

    private async Task CompleteMembershipRead((string Scope, string Credential) key, MembershipRead read, string bearer)
    {
        JsonElement[]? rows = null;
        Exception? failure = null;
        try
        {
            rows = await WpfS2Membership(bearer, read.Cancellation.Token);
            read.Cancellation.Token.ThrowIfCancellationRequested();
        }
        catch (Exception error) { failure = error; }
        lock (_membershipReadLock)
        {
            if (_membershipReads.TryGetValue(key, out var current) && ReferenceEquals(current, read))
                _membershipReads.Remove(key);
            if (_membershipReadsDisposed || failure is OperationCanceledException)
                read.Result.TrySetCanceled();
            else if (failure is not null)
            {
                read.Result.TrySetException(failure);
                // All consumers may have canceled before a transport failure arrived.
                _ = read.Result.Task.Exception;
            }
            else read.Result.TrySetResult(rows!);
        }
        read.Cancellation.Dispose();
    }

    private static void CancelMembershipRead(MembershipRead read)
    {
        try { read.Cancellation.Cancel(); }
        catch (ObjectDisposedException) { } // Completion won the race.
    }

    private void DisposeMembershipReads()
    {
        MembershipRead[] pending;
        lock (_membershipReadLock)
        {
            _membershipReadsDisposed = true;
            pending = _membershipReads.Values.ToArray();
            _membershipReads.Clear();
        }
        foreach (var read in pending) CancelMembershipRead(read);
    }
}
