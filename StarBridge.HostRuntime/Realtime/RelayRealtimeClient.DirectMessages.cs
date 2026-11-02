using System.Text.Json;

namespace StarBridge.HostRuntime.Realtime;

internal sealed partial class RelayRealtimeClient
{
    // Memory-only hint deduplication. Unknown peers may invalidate the directory;
    // they never mint a target capability or grant history/send permission.
    private readonly Dictionary<string, (long Sequence, HashSet<string> Ids)> _directHints = new(StringComparer.Ordinal);
    private bool _directMessageEventsObserved;
    private Dictionary<string, string[]> _directTargets = new(StringComparer.Ordinal);
    private string? _directTargetOwner;
    private readonly Dictionary<string, long> _directTargetVersions = new(StringComparer.Ordinal);
    private bool _unknownDirectHintObserved;
    private long _genericSocialVersion;

    internal void SetDirectMessageTargets(string bearer, Dictionary<string, string[]> targets, CancellationToken token = default)
    {
        lock (_gate) {
            token.ThrowIfCancellationRequested();
            _directTargetOwner = bearer;
            _directTargets = targets;
            var active = targets.Values.SelectMany(v => v).ToHashSet(StringComparer.Ordinal);
            foreach (var reference in _directTargetVersions.Keys.Where(k => !active.Contains(k)).ToArray())
                _directTargetVersions.Remove(reference);
        }
    }

    // Only opaque, previously issued capability references cross the bridge.
    // An empty target list means directory-only reconciliation.
    internal (bool Only, string[] Targets) DirectMessageChanges(string bearer, string instance, long version)
    {
        lock (_gate) {
            var active = _directTargets.Values.SelectMany(v => v).ToHashSet(StringComparer.Ordinal);
            return _bearer == bearer && instance == _instance && version >= _genericSocialVersion
                ? (true, _directTargetVersions.Where(p => p.Value > version && active.Contains(p.Key)).Select(p => p.Key).ToArray())
                : (false, []);
        }
    }

    internal bool DirectMessagesPushHealthy
    {
        get { lock (_gate) return _state == State.Connected && _directMessageEventsObserved; }
    }

    private void ResetDirectMessageHints()
    {
        _directHints.Clear();
        _directMessageEventsObserved = false;
        _directTargetVersions.Clear();
        _unknownDirectHintObserved = false;
        _genericSocialVersion = _socialVersion;
    }

    private void ObserveDirectMessageHint(string type, JsonElement data)
    {
        if (type != "dm.message.created") return;
        // Called under the transport gate. Deliberately inspect no text,
        // attachment, sender identity or nonce from the pushed message.
        if (!TryDirectMessageHint(data, out var conversation, out var id, out var sequence))
        {
            // Older shapes request one directory reconciliation, without
            // treating them as proof that DM push is supported.
            InvalidateUnknownDirectHint();
            return;
        }
        if (_directTargetOwner != _bearer || !_directTargets.TryGetValue(conversation, out var targets))
        {
            InvalidateUnknownDirectHint();
            return;
        }
        _directMessageEventsObserved = true;
        if (_directHints.TryGetValue(conversation, out var previous) &&
            (sequence <= previous.Sequence || previous.Ids.Contains(id))) return;
        // Bounds only affect redundant reads, never message retention: REST
        // owns both content and sequence catch-up.
        if (_directHints.Count >= 2000 && !_directHints.ContainsKey(conversation)) _directHints.Clear();
        var ids = previous.Ids ?? new HashSet<string>(StringComparer.Ordinal);
        if (ids.Count >= 1000) ids.Clear();
        ids.Add(id);
        _directHints[conversation] = (sequence, ids);
        _socialVersion++;
        foreach (var target in targets) _directTargetVersions[target] = _socialVersion;
        Signal();
    }

    private void InvalidateUnknownDirectHint()
    {
        // Coalesce unknown peers/legacy shapes once per connection. They do not
        // prove health and must never wake every visible history reader.
        if (_unknownDirectHintObserved) return;
        _unknownDirectHintObserved = true;
        _socialVersion++;
        Signal();
    }

    private static bool TryDirectMessageHint(JsonElement data, out string conversation, out string id, out long sequence)
    {
        conversation = id = "";
        sequence = 0;
        if (data.ValueKind != JsonValueKind.Object ||
            !data.TryGetProperty("conversation", out var peer) || peer.ValueKind != JsonValueKind.String ||
            !data.TryGetProperty("message", out var message) || message.ValueKind != JsonValueKind.Object ||
            !message.TryGetProperty("id", out var key) || key.ValueKind != JsonValueKind.String ||
            !message.TryGetProperty("sequence", out var cursor) || cursor.ValueKind != JsonValueKind.Number ||
            !cursor.TryGetInt64(out sequence) || sequence <= 0)
            return false;
        conversation = peer.GetString()!;
        id = key.GetString()!;
        return conversation.Length is > 0 and <= 256 && !string.IsNullOrWhiteSpace(conversation) &&
               id.Length is > 0 and <= 256 && !string.IsNullOrWhiteSpace(id);
    }
}
