using StarBridge.HostRuntime.PartyRooms;

namespace StarBridge.HostRuntime.Communities;

internal sealed partial class CommunityClient
{
    private sealed record SharingLogoChunks(string Version, string Mime, byte[] Bytes, int Received, DateTimeOffset Expires);
    private readonly Dictionary<string, SharingLogoChunks> _sharingLogoChunks = new();
    private int _sharingLogoEpoch;

    // Reuse only fully validated media already read for this scoped organization.
    // No HTTP, disk storage, consent changes, or partial images enter the settings projection.
    private void RememberSharingLogoChunk(string reference, Target target, int epoch, string version, string mime,
        int total, int offset, string data, CancellationToken token)
    {
        token.ThrowIfCancellationRequested();
        var bytes = Convert.FromBase64String(data);
        lock (_directoryLogoGate)
        {
            var now = _targetClock.GetUtcNow();
            if (epoch != _sharingLogoEpoch || !_targets.TryGetValue(reference, out var current) ||
                current.Scope != target.Scope || current.Code != target.Code || current.Expires <= now) return;
            foreach (var old in _sharingLogoChunks.Where(row => row.Value.Expires <= now).ToArray())
                _sharingLogoChunks.Remove(old.Key);
            if (offset == 0)
            {
                // At most 16 unfinished logos, each within the existing 512 KiB media bound.
                if (!_sharingLogoChunks.ContainsKey(reference) && _sharingLogoChunks.Count >= 16)
                    _sharingLogoChunks.Remove(_sharingLogoChunks.MinBy(row => row.Value.Expires).Key);
                _sharingLogoChunks[reference] = new(version, mime, new byte[total], 0, now.AddMinutes(5));
            }
            if (!_sharingLogoChunks.TryGetValue(reference, out var pending)) return;
            if (pending.Version != version || pending.Mime != mime || pending.Bytes.Length != total ||
                pending.Received != offset)
            {
                _sharingLogoChunks.Remove(reference);
                return;
            }
            bytes.CopyTo(pending.Bytes, offset);
            var received = offset + bytes.Length;
            if (received != total)
            {
                _sharingLogoChunks[reference] = pending with { Received = received };
                return;
            }
            _sharingLogoChunks.Remove(reference);
            var image = RoomAvatarProjection.Normalize("data:" + mime + ";base64," +
                Convert.ToBase64String(pending.Bytes), 512 * 1024);
            if (image is not null)
                StoreDirectoryLogo("sharing\0" + target.Scope + "\0" + target.Code.ToUpperInvariant(), image,
                    current.Expires < pending.Expires ? current.Expires : pending.Expires, epoch);
        }
    }
}
