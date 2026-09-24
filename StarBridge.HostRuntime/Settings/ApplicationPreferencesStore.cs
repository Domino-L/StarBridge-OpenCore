namespace StarBridge.HostRuntime.Settings;

using StarBridge.NativeBridge;
using System.Text;
using System.Text.Json;

internal sealed class ApplicationPreferencesStore : IApplicationPreferencesStore
{
    private const string FileName = "application-preferences.v1.json";
    private const string LegacyApplicationBehaviorFileName = "application-behavior.json";
    private readonly string _settingsPath;
    private readonly string _legacyApplicationBehaviorPath;

    internal ApplicationPreferencesStore(string dataRoot)
    {
        if (string.IsNullOrWhiteSpace(dataRoot))
        {
            throw new ArgumentException("Application preferences data root is required.", nameof(dataRoot));
        }

        var normalizedRoot = Path.GetFullPath(dataRoot);
        _settingsPath = Path.Combine(normalizedRoot, FileName);
        _legacyApplicationBehaviorPath = Path.Combine(
            normalizedRoot,
            LegacyApplicationBehaviorFileName);
    }

    public ApplicationPreferencesReadResult Load()
    {
        try
        {
            if (!File.Exists(_settingsPath))
            {
                return LoadLegacyApplicationBehavior() ??
                       ApplicationPreferencesReadResult.Defaulted;
            }

            var stored = JsonSerializer.Deserialize<ApplicationPreferencesSnapshot>(
                File.ReadAllText(_settingsPath),
                BridgeProtocol.JsonOptions);
            var normalized = stored?.Normalize();
            return normalized is { } && normalized.IsSupported()
                ? new ApplicationPreferencesReadResult(
                    normalized,
                    ApplicationPreferencesStorageStates.Ready)
                : ApplicationPreferencesReadResult.RecoveredDefaults;
        }
        catch (JsonException)
        {
            return ApplicationPreferencesReadResult.RecoveredDefaults;
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            throw new ApplicationPreferencesException(
                ApplicationPreferencesStableErrors.ReadFailed,
                "Application preferences could not be read.",
                retryable: true,
                exception);
        }
    }

    private ApplicationPreferencesReadResult? LoadLegacyApplicationBehavior()
    {
        if (!File.Exists(_legacyApplicationBehaviorPath))
        {
            return null;
        }

        try
        {
            var legacy = JsonSerializer.Deserialize<LegacyApplicationBehaviorSnapshot>(
                File.ReadAllText(_legacyApplicationBehaviorPath),
                new JsonSerializerOptions
                {
                    PropertyNameCaseInsensitive = true
                });
            if (legacy is null)
            {
                return ApplicationPreferencesReadResult.RecoveredDefaults;
            }

            var migrated = ApplicationPreferencesSnapshot.Default with
            {
                LaunchAtStartup = legacy.LaunchAtStartup,
                KeepRunningInBackground = legacy.KeepRunningInBackground,
                StartMinimized = legacy.StartMinimized,
                StartupChoiceMade = true,
                CloseBehaviorChoiceMade = legacy.CloseBehaviorChoiceMade,
                BackgroundHintShown = legacy.BackgroundHintShown
            };
            return new ApplicationPreferencesReadResult(
                migrated.Normalize(),
                ApplicationPreferencesStorageStates.Ready);
        }
        catch (JsonException)
        {
            return ApplicationPreferencesReadResult.RecoveredDefaults;
        }
    }

    public void Save(ApplicationPreferencesSnapshot snapshot)
    {
        ArgumentNullException.ThrowIfNull(snapshot);
        snapshot = snapshot.Normalize();
        if (!snapshot.IsSupported())
        {
            throw new ApplicationPreferencesException(
                ApplicationPreferencesStableErrors.InvalidValue,
                "Application preferences contain an unsupported value.");
        }

        var directory = Path.GetDirectoryName(_settingsPath) ??
                        throw new InvalidOperationException("Settings directory is unavailable.");
        var temporaryPath = Path.Combine(
            directory,
            $".{Path.GetFileName(_settingsPath)}.{Guid.NewGuid():N}.tmp");
        try
        {
            Directory.CreateDirectory(directory);
            var json = JsonSerializer.Serialize(snapshot, BridgeProtocol.JsonOptions);
            using (var stream = new FileStream(
                       temporaryPath,
                       FileMode.CreateNew,
                       FileAccess.Write,
                       FileShare.None,
                       bufferSize: 4096,
                       FileOptions.WriteThrough))
            using (var writer = new StreamWriter(stream, new UTF8Encoding(false)))
            {
                writer.Write(json);
                writer.Flush();
                stream.Flush(flushToDisk: true);
            }

            File.Move(temporaryPath, _settingsPath, overwrite: true);
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            TryDeleteTemporaryFile(temporaryPath);
            throw new ApplicationPreferencesException(
                ApplicationPreferencesStableErrors.SaveFailed,
                "Application preferences could not be saved.",
                retryable: true,
                exception);
        }
    }

    private static void TryDeleteTemporaryFile(string path)
    {
        try
        {
            if (File.Exists(path))
            {
                File.Delete(path);
            }
        }
        catch
        {
            // A future save ignores and can safely replace an orphaned temp file.
        }
    }

    private sealed record LegacyApplicationBehaviorSnapshot(
        bool LaunchAtStartup,
        bool KeepRunningInBackground,
        bool StartMinimized,
        bool BackgroundHintShown,
        bool CloseBehaviorChoiceMade = false);
}
