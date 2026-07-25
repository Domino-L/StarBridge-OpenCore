using System.IO;
using System.Text.Json;

namespace StarBridge.Desktop;

internal sealed record LocalPlaySessionReminderState(
    int SchemaVersion = LocalPlaySessionReminder.CurrentSchemaVersion,
    DateTimeOffset? SessionStartedAtUtc = null,
    DateTimeOffset? LastObservedRunningAtUtc = null,
    DateTimeOffset? MissingSinceUtc = null,
    DateTimeOffset? ProcessStartedAtUtc = null,
    DateTimeOffset? NextReminderAtUtc = null,
    DateTimeOffset? LastReminderAtUtc = null);

internal sealed class LocalPlaySessionReminder
{
    public const int CurrentSchemaVersion = 1;
    public static readonly TimeSpan FirstReminderDelay = TimeSpan.FromHours(2);
    public static readonly TimeSpan RepeatReminderDelay = TimeSpan.FromHours(2);
    public static readonly TimeSpan SessionResetDelay = TimeSpan.FromMinutes(15);

    private static readonly TimeSpan SaveCheckpointInterval = TimeSpan.FromMinutes(1);
    private static readonly JsonSerializerOptions JsonOptions = new() { WriteIndented = true };

    private readonly string _statePath;
    private TimeSpan _firstReminderDelay;
    private TimeSpan _repeatReminderDelay;
    private readonly TimeSpan _sessionResetDelay;
    private LocalPlaySessionReminderState _state;
    private DateTimeOffset _lastSavedAtUtc = DateTimeOffset.MinValue;

    public LocalPlaySessionReminder(
        string? statePath = null,
        TimeSpan? firstReminderDelay = null,
        TimeSpan? repeatReminderDelay = null,
        TimeSpan? sessionResetDelay = null)
    {
        _statePath = string.IsNullOrWhiteSpace(statePath)
            ? Path.Combine(DesktopAppConfig.ConfigDirectory, "local-play-session.json")
            : statePath;
        _firstReminderDelay = firstReminderDelay ?? FirstReminderDelay;
        _repeatReminderDelay = repeatReminderDelay ?? RepeatReminderDelay;
        _sessionResetDelay = sessionResetDelay ?? SessionResetDelay;
        _state = LoadState(_statePath);
    }

    public bool Observe(bool isGameRunning, DateTimeOffset now, DateTimeOffset? processStartedAtUtc = null)
    {
        now = now.ToUniversalTime();
        processStartedAtUtc = NormalizeProcessStart(processStartedAtUtc, now);

        if (!isGameRunning)
        {
            ObserveStopped(now);
            return false;
        }

        ObserveRunning(now, processStartedAtUtc);
        return _state.NextReminderAtUtc is { } nextReminderAt && now >= nextReminderAt;
    }

    public void ConfigureDelays(TimeSpan firstReminderDelay, TimeSpan repeatReminderDelay, DateTimeOffset now)
    {
        if (firstReminderDelay <= TimeSpan.Zero || repeatReminderDelay <= TimeSpan.Zero)
        {
            return;
        }

        _firstReminderDelay = firstReminderDelay;
        _repeatReminderDelay = repeatReminderDelay;
        if (_state.SessionStartedAtUtc is not { } startedAt)
        {
            return;
        }

        var nextReminderAt = _state.LastReminderAtUtc is { } lastReminderAt
            ? lastReminderAt + _repeatReminderDelay
            : startedAt + _firstReminderDelay;
        _state = _state with { NextReminderAtUtc = nextReminderAt };
        Save(now.ToUniversalTime(), force: true);
    }

    public void MarkReminderShown(DateTimeOffset now)
    {
        if (_state.SessionStartedAtUtc is null)
        {
            return;
        }

        now = now.ToUniversalTime();
        _state = _state with
        {
            LastReminderAtUtc = now,
            NextReminderAtUtc = now + _repeatReminderDelay
        };
        Save(now, force: true);
    }

    public TimeSpan GetContinuousPlayTime(DateTimeOffset now)
    {
        if (_state.SessionStartedAtUtc is not { } startedAt)
        {
            return TimeSpan.Zero;
        }

        var elapsed = now.ToUniversalTime() - startedAt;
        return elapsed > TimeSpan.Zero ? elapsed : TimeSpan.Zero;
    }

    private void ObserveRunning(DateTimeOffset now, DateTimeOffset? processStartedAtUtc)
    {
        if (_state.SessionStartedAtUtc is null)
        {
            StartSession(now, processStartedAtUtc);
            return;
        }

        var processChanged = processStartedAtUtc is { } currentProcessStart &&
                             _state.ProcessStartedAtUtc is { } previousProcessStart &&
                             Math.Abs((currentProcessStart - previousProcessStart).TotalSeconds) > 2;
        var missingTooLong = _state.MissingSinceUtc is { } missingSince &&
                             now - missingSince >= _sessionResetDelay;
        var replacementStartedTooLate = processChanged &&
                                        _state.LastObservedRunningAtUtc is { } lastRunning &&
                                        processStartedAtUtc!.Value - lastRunning >= _sessionResetDelay;

        if (missingTooLong || replacementStartedTooLate)
        {
            StartSession(now, processStartedAtUtc);
            return;
        }

        var wasMissing = _state.MissingSinceUtc is not null;
        _state = _state with
        {
            LastObservedRunningAtUtc = now,
            MissingSinceUtc = null,
            ProcessStartedAtUtc = processStartedAtUtc ?? _state.ProcessStartedAtUtc
        };
        Save(now, force: wasMissing || processChanged);
    }

    private void ObserveStopped(DateTimeOffset now)
    {
        if (_state.SessionStartedAtUtc is null)
        {
            return;
        }

        if (_state.MissingSinceUtc is null)
        {
            _state = _state with { MissingSinceUtc = now };
            Save(now, force: true);
            return;
        }

        if (now - _state.MissingSinceUtc.Value < _sessionResetDelay)
        {
            return;
        }

        _state = new LocalPlaySessionReminderState();
        Save(now, force: true);
    }

    private void StartSession(DateTimeOffset now, DateTimeOffset? processStartedAtUtc)
    {
        var startedAt = processStartedAtUtc is { } processStart && processStart <= now
            ? processStart
            : now;
        _state = new LocalPlaySessionReminderState(
            SessionStartedAtUtc: startedAt,
            LastObservedRunningAtUtc: now,
            ProcessStartedAtUtc: processStartedAtUtc,
            NextReminderAtUtc: startedAt + _firstReminderDelay);
        Save(now, force: true);
    }

    private void Save(DateTimeOffset now, bool force)
    {
        if (!force && now - _lastSavedAtUtc < SaveCheckpointInterval)
        {
            return;
        }

        try
        {
            var directory = Path.GetDirectoryName(_statePath);
            if (!string.IsNullOrWhiteSpace(directory))
            {
                Directory.CreateDirectory(directory);
            }

            File.WriteAllText(_statePath, JsonSerializer.Serialize(_state, JsonOptions));
            _lastSavedAtUtc = now;
        }
        catch
        {
            // A health reminder must never disrupt the game or Overlay lifecycle.
        }
    }

    private static LocalPlaySessionReminderState LoadState(string path)
    {
        try
        {
            if (!File.Exists(path))
            {
                return new LocalPlaySessionReminderState();
            }

            var state = JsonSerializer.Deserialize<LocalPlaySessionReminderState>(File.ReadAllText(path));
            return state is { SchemaVersion: CurrentSchemaVersion }
                ? state
                : new LocalPlaySessionReminderState();
        }
        catch
        {
            return new LocalPlaySessionReminderState();
        }
    }

    private static DateTimeOffset? NormalizeProcessStart(DateTimeOffset? value, DateTimeOffset now)
    {
        if (value is null)
        {
            return null;
        }

        var normalized = value.Value.ToUniversalTime();
        return normalized <= now ? normalized : null;
    }
}
