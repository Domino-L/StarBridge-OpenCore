using System.Globalization;
using System.Text;

namespace StarBridge.HostRuntime.HealthReading;

// Counts only, for "读取自己的血量" (11-13 scheduler/user): how often capture started and stopped and why, how many
// images came in, how often the tile was found and a value came out, how often full health was kept, the
// processing time per read, and the last state. No image, no health value, no window title, no name is written.
// One summary line per minute while anything happened, plus one line when capture starts or stops.
internal sealed class SelfHealthDiagnostics
{
    public const double SummaryEverySeconds = 60;

    readonly Action<string> _write;
    readonly Dictionary<string, int> _stops = new(StringComparer.Ordinal);
    double _windowStart = double.NaN;
    int _starts, _images, _newImages, _black, _found, _read, _held, _newLife, _noTile, _away;
    // 11-14 (user: "突然识别出极低血量 但当前血量正常"): readings refused because another tile was found away from the
    // confirmed tile position; big drops (15 or more) that started confirming, were shown, or were dropped. Counts only.
    int _offHome, _bigHeld, _bigShown, _bigDropped;
    // 11-15 user ("只有圆环在闪"): how often the ring sent to the visor went away, how often it came back within a second
    // of going, and how many images kept the last value over a short unreadable gap (ShortGapKeepSeconds). Counts only.
    int _ringHidden, _ringBack, _gapKept, _ringDrops, _nearFullChanges;
    double _ringHiddenAt = double.NegativeInfinity;
    // 11-17 user (new life from the log): images where the new life's full waited for this capture size to be read
    // clearly once, and how often the tile search started afresh (a server join, the first spawn after it).
    int _newLifeWaiting, _searchRestarts;
    public const double RingBackWithinSeconds = 1.0;
    double _msSum, _msMax; int _msCount;
    string _state = "off";
    string? _lastStop;

    public SelfHealthDiagnostics(Action<string> write) { _write = write; }

    internal string State => _state;

    public void CaptureStarted(double now)
    {
        Begin(now);
        _starts++; _lastStop = null;
        Write($"capture=start");
    }

    // Reasons: off, not-running, not-readable, no-model, no-source, lost, failed, stopping.
    public void CaptureStopped(double now, string reason)
    {
        Begin(now);
        _state = "stopped:" + reason;
        // the idle polls that follow this stop are the same stop (review P3)
        _lastStop = reason;
        Count(_stops, reason);
        Write($"capture=stop reason={reason}");
    }

    // Idle reasons while no capture runs (switch off, game not running, not readable): counted once per change.
    public void Idle(double now, string reason)
    {
        if (_lastStop == reason) return;
        _lastStop = reason;
        Begin(now);
        Count(_stops, reason);
        _state = "idle:" + reason;
    }

    public void Read(double now, bool newImage, string recognizerState, bool recognizerValue, SelfHealthHoldOutcome outcome, double milliseconds,
        bool shortGapKept = false, bool newLifeWaitingForSize = false)
    {
        Begin(now);
        _lastStop = null;
        _images++;
        if (newImage) _newImages++;
        if (recognizerState == "black") _black++;
        else if (recognizerState != "not_found") _found++;
        if (recognizerValue) _read++;
        if (shortGapKept) _gapKept++;
        if (newLifeWaitingForSize) _newLifeWaiting++;
        switch (outcome)
        {
            case SelfHealthHoldOutcome.Held: _held++; break;
            case SelfHealthHoldOutcome.NewLifeFull: _newLife++; break;
            case SelfHealthHoldOutcome.NoTile: _noTile++; break;
            case SelfHealthHoldOutcome.Away: _away++; break;
        }
        _state = outcome switch
        {
            SelfHealthHoldOutcome.Reading => "reading",
            SelfHealthHoldOutcome.Held => "full-kept",
            SelfHealthHoldOutcome.NewLifeFull => "full-new-life",
            SelfHealthHoldOutcome.Black => "black",
            SelfHealthHoldOutcome.Away => "away-or-dead",
            SelfHealthHoldOutcome.TileUnread => "tile-unread",
            SelfHealthHoldOutcome.Carried => "carried",
            _ => "no-tile",
        };
        if (double.IsFinite(milliseconds) && milliseconds >= 0)
        {
            _msSum += milliseconds; _msCount++;
            if (milliseconds > _msMax) _msMax = milliseconds;
        }
    }

    public void Guards(bool offHomeRejected, bool bigDropStarted, bool bigDropShown, bool bigDropAbandoned)
    {
        if (offHomeRejected) _offHome++;
        if (bigDropStarted) _bigHeld++;
        if (bigDropShown) _bigShown++;
        if (bigDropAbandoned) _bigDropped++;
    }

    // The ring sent to the visor appeared (shown) or went away (not shown).
    public void Ring(double now, bool shown)
    {
        Begin(now);
        if (!shown) { _ringHidden++; _ringHiddenAt = now; return; }
        if (now - _ringHiddenAt <= RingBackWithinSeconds + 1e-9) _ringBack++;
        _ringHiddenAt = double.NegativeInfinity;
    }

    // The tile search started afresh (a server join, the first spawn after it).
    public void TileSearchRestarted() => _searchRestarts++;

    // A shown value changed: down (the visor flashes the ring for it) or up; nearFull: either side at 98 or more.
    public void RingChange(bool drop, bool nearFull)
    {
        if (drop) _ringDrops++;
        if (nearFull) _nearFullChanges++;
    }

    // Writes the minute's summary when due and anything happened.
    public void Tick(double now)
    {
        if (double.IsNaN(_windowStart) || now - _windowStart < SummaryEverySeconds) return;
        if (_images > 0 || _starts > 0 || _stops.Count > 0) Flush();
        Reset(now);
    }

    void Flush()
    {
        var line = new StringBuilder("summary");
        line.Append(" starts=").Append(_starts);
        line.Append(" images=").Append(_images).Append(" new=").Append(_newImages);
        line.Append(" black=").Append(_black).Append(" tileFound=").Append(_found).Append(" valueRead=").Append(_read);
        line.Append(" fullKept=").Append(_held).Append(" fullNewLife=").Append(_newLife);
        line.Append(" noTile=").Append(_noTile).Append(" awayOrDead=").Append(_away);
        line.Append(" offHomeRejected=").Append(_offHome).Append(" bigDropHeld=").Append(_bigHeld)
            .Append(" bigDropShown=").Append(_bigShown).Append(" bigDropDropped=").Append(_bigDropped);
        line.Append(" ringHidden=").Append(_ringHidden).Append(" ringBackIn1s=").Append(_ringBack).Append(" shortGapKept=").Append(_gapKept)
            .Append(" ringDrops=").Append(_ringDrops).Append(" nearFullChanges=").Append(_nearFullChanges);
        line.Append(" newLifeWaitingForSize=").Append(_newLifeWaiting).Append(" tileSearchRestarts=").Append(_searchRestarts);
        foreach (var stop in _stops.OrderBy(pair => pair.Key, StringComparer.Ordinal)) line.Append(" stop.").Append(stop.Key).Append('=').Append(stop.Value);
        line.Append(" avgMs=").Append(_msCount == 0 ? "-" : (_msSum / _msCount).ToString("0.00", CultureInfo.InvariantCulture));
        line.Append(" maxMs=").Append(_msCount == 0 ? "-" : _msMax.ToString("0.00", CultureInfo.InvariantCulture));
        line.Append(" state=").Append(_state);
        Write(line.ToString());
    }

    void Begin(double now) { if (double.IsNaN(_windowStart)) _windowStart = now; }

    void Reset(double now)
    {
        _windowStart = now;
        _starts = _images = _newImages = _black = _found = _read = _held = _newLife = _noTile = _away = 0;
        _offHome = _bigHeld = _bigShown = _bigDropped = 0;
        _ringHidden = _ringBack = _gapKept = _ringDrops = _nearFullChanges = 0;
        _newLifeWaiting = _searchRestarts = 0;
        _msSum = _msMax = 0; _msCount = 0;
        _stops.Clear();
    }

    static void Count(Dictionary<string, int> counts, string key) => counts[key] = counts.GetValueOrDefault(key) + 1;

    void Write(string line) { try { _write(line); } catch (Exception) { } }
}

// The file: self-health-diagnostics.log in the data root, at most 128 KB, the previous one kept as .1.
internal static class SelfHealthDiagnosticsFile
{
    internal const string FileName = "self-health-diagnostics.log";
    internal const long MaximumBytes = 128 * 1024;
    static readonly object Gate = new();

    public static Action<string> For(string root) => line => Append(root, line);

    internal static void Append(string root, string line)
    {
        try
        {
            lock (Gate)
            {
                var directory = Path.GetFullPath(root);
                for (var parent = new DirectoryInfo(directory); parent is not null; parent = parent.Parent)
                    if (parent.Exists && parent.Attributes.HasFlag(FileAttributes.ReparsePoint)) return;
                var path = Path.Combine(directory, FileName);
                if (File.Exists(path) && File.GetAttributes(path).HasFlag(FileAttributes.ReparsePoint)) return;
                Directory.CreateDirectory(directory);
                if (File.Exists(path) && new FileInfo(path).Length >= MaximumBytes)
                {
                    var previous = path + ".1";
                    if (File.Exists(previous) && File.GetAttributes(previous).HasFlag(FileAttributes.ReparsePoint)) return;
                    File.Move(path, previous, overwrite: true);
                }
                File.AppendAllText(path, $"{DateTimeOffset.UtcNow:O} {line}{Environment.NewLine}");
            }
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or System.Security.SecurityException) { }
    }
}
