namespace StarBridge.HostRuntime.Support;

/// <summary>Already-presented local fields only; never retain FleetEvent.SourceLine,
/// GEID, vehicle instance ID or authentication data in the pending queue.</summary>
public sealed record LocalGameEventRecord(string Category, string EventType, string Title, string Detail);

/// <summary>Called under the existing GameLogRuntime lock. No timer, parser, file reader
/// or store of its own. Initial/recovery reads establish state but never append history.</summary>
public sealed class GameLogJournalBatch(LocalGameEventJournal journal)
{
    private readonly Queue<LocalGameEventRecord> _pending = new();
    private bool _following;
    private bool _continuing;
    private long _clearRevision;

    public void BeginRead()
    {
        if (!_continuing)
        {
            _pending.Clear();
            _clearRevision = journal.ClearRevision;
        }
    }

    public void Reset()
    {
        _following = false;
        _continuing = false;
        _pending.Clear();
    }

    public void Add(LocalGameEventRecord entry)
    {
        if (!_following || string.IsNullOrWhiteSpace(entry.Title)) return;
        if (_pending.Count == LocalGameEventJournal.MaximumEntries) _pending.Dequeue();
        _pending.Enqueue(entry with
        {
            Category = LocalGameEventJournal.NormalizeText(entry.Category, 32, "other"),
            EventType = LocalGameEventJournal.NormalizeText(entry.EventType, 80, "Unknown"),
            Title = LocalGameEventJournal.NormalizeText(entry.Title, 180, "未命名事件"),
            Detail = LocalGameEventJournal.NormalizeText(entry.Detail, 500, "")
        });
    }

    // The caller checks the *completed* read's identity and current account generation.
    // An unreadable/ambiguous/incomplete batch is discarded, not partially committed.
    public void Complete(Func<bool> current, bool incomplete = false)
    {
        if (incomplete)
        {
            if (!current()) Reset();
            else _continuing = true;
            return;
        }
        try
        {
            if (!current()) { Reset(); return; }
            foreach (var entry in _pending)
            {
                if (!current()) { Reset(); return; }
                journal.Append(entry.Category, entry.EventType, entry.Title, entry.Detail,
                    expectedClearRevision: _clearRevision, canAppend: current);
            }
            _following = true;
        }
        finally { _pending.Clear(); _continuing = false; }
    }
}
