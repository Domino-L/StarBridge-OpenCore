using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace StarBridge.Desktop;

internal enum GameplayDataConsentState
{
    Unknown,
    Allowed,
    Declined
}

internal sealed record GameplayDataConsentSettings(
    int Version = GameplayStatisticsRecorder.CurrentConsentVersion,
    GameplayDataConsentState State = GameplayDataConsentState.Unknown,
    DateTimeOffset UpdatedAt = default,
    bool ShareOnProfile = false);

internal static class GameplayStatisticsConsentPromptPolicy
{
    public static bool ShouldPrompt(
        GameplayDataConsentSettings consent,
        bool hasOwner,
        bool hasAuthenticatedSession,
        string? stableAccountId)
    {
        if (!hasOwner ||
            (hasAuthenticatedSession && string.IsNullOrWhiteSpace(stableAccountId)))
        {
            return false;
        }

        return consent.Version < GameplayStatisticsRecorder.CurrentConsentVersion ||
               consent.State == GameplayDataConsentState.Unknown;
    }
}

internal sealed record GameplayStatisticsSnapshot(
    int SchemaVersion = GameplayStatisticsRecorder.CurrentStatisticsSchemaVersion,
    long PlayTimeSeconds = 0,
    int DownedCount = 0,
    int DeathCount = 0,
    DateTimeOffset? FirstRecordedAt = null,
    DateTimeOffset? LastRecordedAt = null,
    long HistoricalPlayTimeSeconds = 0,
    int HistoricalSessionCount = 0,
    int HistoricalIncompleteSessionCount = 0,
    DateTimeOffset? HistoryImportedAt = null)
{
    public static GameplayStatisticsSnapshot Empty { get; } = new();
}

internal sealed class GameplayStatisticsRecorder
{
    public const int CurrentConsentVersion = 1;
    public const int CurrentStatisticsSchemaVersion = 4;
    private static readonly TimeSpan MaximumSampleGap = TimeSpan.FromSeconds(30);
    private static readonly TimeSpan SaveInterval = TimeSpan.FromMinutes(1);
    private static readonly JsonSerializerOptions JsonOptions = new() { WriteIndented = true };

    private readonly string _statisticsDirectory;
    private string? _consentPath;
    private string? _statisticsPath;
    private string? _ownerKey;
    private DateTimeOffset? _lastGameSampleAt;
    private DateTimeOffset _lastSavedAt = DateTimeOffset.MinValue;
    private bool _wasGameRunning;
    private bool _dirty;

    public GameplayStatisticsRecorder(string? baseDirectory = null)
    {
        var root = string.IsNullOrWhiteSpace(baseDirectory)
            ? DesktopAppConfig.ConfigDirectory
            : baseDirectory;
        _statisticsDirectory = Path.Combine(root, "GameplayStatistics");
        Consent = new GameplayDataConsentSettings();
    }

    public GameplayDataConsentSettings Consent { get; private set; }

    public GameplayStatisticsSnapshot Snapshot { get; private set; } = GameplayStatisticsSnapshot.Empty;

    public bool HasOwner => !string.IsNullOrWhiteSpace(_ownerKey);

    public string? LastWriteError { get; private set; }

    public bool IsRecordingAllowed =>
        Consent.Version >= CurrentConsentVersion &&
        Consent.State == GameplayDataConsentState.Allowed;

    public void BindOwner(string? ownerKey)
    {
        var normalized = ownerKey?.Trim();
        if (string.IsNullOrWhiteSpace(normalized) ||
            string.Equals(_ownerKey, normalized, StringComparison.OrdinalIgnoreCase))
        {
            return;
        }

        Stop(DateTimeOffset.UtcNow);
        _ownerKey = normalized;
        var ownerHash = HashOwnerKey(normalized);
        _consentPath = Path.Combine(_statisticsDirectory, $"{ownerHash}.consent.json");
        _statisticsPath = Path.Combine(_statisticsDirectory, $"{ownerHash}.json");
        Consent = LoadConsent();
        Snapshot = LoadSnapshot(_statisticsPath, out var snapshotRequiresMigration);
        _dirty = snapshotRequiresMigration;
        _lastSavedAt = DateTimeOffset.UtcNow;
        Flush();
    }

    public void SetConsent(GameplayDataConsentState state, DateTimeOffset now)
    {
        if (!HasOwner || string.IsNullOrWhiteSpace(_consentPath))
        {
            throw new InvalidOperationException("尚未识别当前用户，无法保存游玩时长记录许可。");
        }

        if (!Enum.IsDefined(state))
        {
            state = GameplayDataConsentState.Unknown;
        }

        if (Consent.State == state && Consent.Version == CurrentConsentVersion)
        {
            return;
        }

        if (Consent.State == GameplayDataConsentState.Allowed)
        {
            Stop(now);
        }

        var updatedConsent = Consent with
        {
            Version = CurrentConsentVersion,
            State = state,
            UpdatedAt = now
        };
        try
        {
            SaveConsent(updatedConsent);
            LastWriteError = null;
        }
        catch (Exception ex)
        {
            LastWriteError = UserFacingError.Describe(ex, "游玩时长未能保存，请稍后重试。");
            throw;
        }

        Consent = updatedConsent;
        _lastGameSampleAt = null;
        _wasGameRunning = false;
    }

    public void ObserveGameProcess(bool isRunning, DateTimeOffset now)
    {
        if (!CanRecord())
        {
            _lastGameSampleAt = null;
            _wasGameRunning = false;
            return;
        }

        if (isRunning)
        {
            AccumulatePlayTime(now);
            _lastGameSampleAt = now;
            _wasGameRunning = true;
            FlushIfDue(now);
            return;
        }

        if (_wasGameRunning)
        {
            AccumulatePlayTime(now);
            Flush();
        }

        _lastGameSampleAt = null;
        _wasGameRunning = false;
    }

    public void ImportHistory(GameplayHistoryImportResult import, DateTimeOffset now)
    {
        if (!CanRecord())
        {
            throw new InvalidOperationException("请先允许游玩时长记录，再导入历史记录。");
        }

        if (Snapshot.HistoryImportedAt.HasValue)
        {
            throw new InvalidOperationException("历史记录已经导入。重置游玩时长后可再次导入一次。");
        }

        if (!import.HasData || !import.FirstSessionAt.HasValue || !import.LastSessionAt.HasValue)
        {
            throw new InvalidOperationException(import.Error ?? "没有可导入的有效历史记录。");
        }

        var historicalSeconds = Math.Max(0, import.PlayTimeSeconds);
        Snapshot = Snapshot with
        {
            PlayTimeSeconds = Snapshot.PlayTimeSeconds + historicalSeconds,
            HistoricalPlayTimeSeconds = historicalSeconds,
            HistoricalSessionCount = Math.Max(0, import.SessionCount),
            HistoricalIncompleteSessionCount = Math.Max(0, import.IncompleteSessionCount),
            HistoryImportedAt = now,
            FirstRecordedAt = Min(Snapshot.FirstRecordedAt, import.FirstSessionAt),
            LastRecordedAt = Max(Snapshot.LastRecordedAt, import.LastSessionAt)
        };
        _dirty = true;
        Flush();
    }

    public void Stop(DateTimeOffset now)
    {
        if (CanRecord() && _wasGameRunning)
        {
            AccumulatePlayTime(now);
        }

        _lastGameSampleAt = null;
        _wasGameRunning = false;
        Flush();
    }

    public void Clear()
    {
        try
        {
            if (!string.IsNullOrWhiteSpace(_statisticsPath) && File.Exists(_statisticsPath))
            {
                File.Delete(_statisticsPath);
            }

            LastWriteError = null;
        }
        catch (Exception ex)
        {
            LastWriteError = UserFacingError.Describe(ex, "游玩时长未能保存，请稍后重试。");
            throw;
        }

        Snapshot = GameplayStatisticsSnapshot.Empty;
        _dirty = false;
        _lastGameSampleAt = null;
        _wasGameRunning = false;
    }

    public void SetProfileSharing(bool shareOnProfile, DateTimeOffset now)
    {
        if (!HasOwner || string.IsNullOrWhiteSpace(_consentPath))
        {
            throw new InvalidOperationException("尚未识别当前用户，无法保存统计展示设置。");
        }

        if (Consent.ShareOnProfile == shareOnProfile)
        {
            return;
        }

        var updatedConsent = Consent with
        {
            ShareOnProfile = shareOnProfile,
            UpdatedAt = now
        };
        SaveConsent(updatedConsent);
        Consent = updatedConsent;
    }

    public void Flush()
    {
        if (!_dirty || string.IsNullOrWhiteSpace(_statisticsPath))
        {
            return;
        }

        try
        {
            Directory.CreateDirectory(_statisticsDirectory);
            File.WriteAllText(_statisticsPath, JsonSerializer.Serialize(Snapshot, JsonOptions));
            _dirty = false;
            LastWriteError = null;
        }
        catch (Exception ex)
        {
            LastWriteError = UserFacingError.Describe(ex, "游玩时长未能保存，请稍后重试。");
        }
        finally
        {
            _lastSavedAt = DateTimeOffset.UtcNow;
        }
    }

    private bool CanRecord() => IsRecordingAllowed && !string.IsNullOrWhiteSpace(_statisticsPath);

    private void AccumulatePlayTime(DateTimeOffset now)
    {
        if (!_lastGameSampleAt.HasValue)
        {
            return;
        }

        var elapsed = now - _lastGameSampleAt.Value;
        if (elapsed <= TimeSpan.Zero || elapsed > MaximumSampleGap)
        {
            return;
        }

        var seconds = Math.Max(0, (long)Math.Round(elapsed.TotalSeconds, MidpointRounding.AwayFromZero));
        if (seconds == 0)
        {
            return;
        }

        Snapshot = Touch(Snapshot with { PlayTimeSeconds = Snapshot.PlayTimeSeconds + seconds }, now);
        _dirty = true;
    }

    private void FlushIfDue(DateTimeOffset now)
    {
        if (_dirty && (_lastSavedAt == DateTimeOffset.MinValue || now - _lastSavedAt >= SaveInterval))
        {
            Flush();
        }
    }

    private static GameplayStatisticsSnapshot Touch(GameplayStatisticsSnapshot snapshot, DateTimeOffset now) =>
        snapshot with
        {
            FirstRecordedAt = snapshot.FirstRecordedAt ?? now,
            LastRecordedAt = now
        };

    private GameplayDataConsentSettings LoadConsent()
    {
        try
        {
            if (!File.Exists(_consentPath))
            {
                return new GameplayDataConsentSettings();
            }

            var loaded = JsonSerializer.Deserialize<GameplayDataConsentSettings>(File.ReadAllText(_consentPath));
            if (loaded is null || !Enum.IsDefined(loaded.State))
            {
                return new GameplayDataConsentSettings();
            }

            return loaded;
        }
        catch
        {
            return new GameplayDataConsentSettings();
        }
    }

    private static GameplayStatisticsSnapshot LoadSnapshot(string path, out bool requiresMigration)
    {
        requiresMigration = false;
        try
        {
            var loaded = File.Exists(path)
                ? JsonSerializer.Deserialize<GameplayStatisticsSnapshot>(File.ReadAllText(path))
                : null;
            requiresMigration = loaded is not null &&
                                (loaded.SchemaVersion != CurrentStatisticsSchemaVersion ||
                                 loaded.DownedCount != 0 ||
                                 loaded.DeathCount != 0);
            return loaded is null
                ? GameplayStatisticsSnapshot.Empty
                : loaded with
                {
                    SchemaVersion = CurrentStatisticsSchemaVersion,
                    PlayTimeSeconds = Math.Max(0, loaded.PlayTimeSeconds),
                    DownedCount = 0,
                    DeathCount = 0,
                    HistoricalPlayTimeSeconds = Math.Clamp(
                        loaded.HistoricalPlayTimeSeconds,
                        0,
                        Math.Max(0, loaded.PlayTimeSeconds)),
                    HistoricalSessionCount = Math.Max(0, loaded.HistoricalSessionCount),
                    HistoricalIncompleteSessionCount = Math.Clamp(
                        loaded.HistoricalIncompleteSessionCount,
                        0,
                        Math.Max(0, loaded.HistoricalSessionCount))
                };
        }
        catch
        {
            requiresMigration = false;
            return GameplayStatisticsSnapshot.Empty;
        }
    }

    private void SaveConsent(GameplayDataConsentSettings consent)
    {
        if (string.IsNullOrWhiteSpace(_consentPath))
        {
            throw new InvalidOperationException("尚未识别当前用户，无法保存游玩时长记录许可。");
        }

        var directory = Path.GetDirectoryName(_consentPath);
        if (!string.IsNullOrWhiteSpace(directory))
        {
            Directory.CreateDirectory(directory);
        }

        File.WriteAllText(_consentPath, JsonSerializer.Serialize(consent, JsonOptions));
    }

    private static string HashOwnerKey(string ownerKey)
    {
        var bytes = SHA256.HashData(Encoding.UTF8.GetBytes(ownerKey.Trim().ToLowerInvariant()));
        return Convert.ToHexString(bytes.AsSpan(0, 12)).ToLowerInvariant();
    }

    private static DateTimeOffset? Min(DateTimeOffset? left, DateTimeOffset? right)
    {
        if (!left.HasValue)
        {
            return right;
        }

        if (!right.HasValue)
        {
            return left;
        }

        return left.Value <= right.Value ? left : right;
    }

    private static DateTimeOffset? Max(DateTimeOffset? left, DateTimeOffset? right)
    {
        if (!left.HasValue)
        {
            return right;
        }

        if (!right.HasValue)
        {
            return left;
        }

        return left.Value >= right.Value ? left : right;
    }
}
