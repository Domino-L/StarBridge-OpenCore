using Microsoft.Win32;
using StarBridge.HostRuntime.Support;
using StarBridge.HostRuntime.Updates;

namespace StarBridge.HostRuntime.Onboarding;

internal sealed record FirstUseInstallSource(string Kind, string Version);
internal sealed record FirstUseStartupObservation(string Eligibility, string Reason, bool HasProgress);
internal sealed record FirstUseInstalledObservation(InstalledUpdateRegistration Registration, FirstUseInstallSource? Source);

// Presentation eligibility only. It grants no identity, settings, consent or completion.
// Capture history before ordinary device owners can save their first defaults.
internal sealed class FirstUseStartupReader
{
    // Presence-only markers in their own folder under the data root, so recording
    // where this user started never creates setup progress or its folder. Once a
    // start is classified, later progress saves cannot change the answer:
    // - returning: a returning user's Usage mode or log panel saves stay returning;
    // - started: a new user's cleared guide page cannot later look like
    //   settings-only use after an update.
    // Older builds never read them, so rollback is unaffected.
    internal const string MarkerDirectory = "first-use-start-v1";
    internal const string ReturningMarker = "returning.v1";
    internal const string StartedMarker = "started.v1";
    private readonly FirstUseStartupObservation _initial;
    private readonly LocalFirstUseStore _local;
    private readonly FirstUseCompletionStore _completion;
    private readonly string _root;
    private readonly string _history;
    private readonly bool _started;
    private readonly string? _marker;
    private readonly FirstUseInstallSource? _installation;
    internal FirstUseStartupReader(string root, Func<FirstUseInstallSource?> installation)
    {
        _root = root;
        _local = new(root);
        _completion = new(root);
        try
        {
            _history = HasAny(root, ["desktop.config", "onboarding.complete", "onboarding-introduction.read"])
                ? "legacyUse"
                : HasAny(root, [Marker(ReturningMarker)]) ? "returning"
                : HasAny(root, ["application-preferences.v1.json", "application-behavior.json", "local-event-log.json",
                      "overlay.settings", "overlay.layout", "overlay.presets", "notification.settings.json",
                      "sync-privacy.settings.json", "local-play-session.json"]) ||
                  // "overlay-v2": 0.7.3 overlay v2 keeps its files in their own folder (OverlayWorkspaceStore.V2Folder).
                  HasAny(root, ["game-log-local-v1", "gameplay-time-local-v1", "personal-profile-cache", "chat-history", "overlay-v2"], directories: true)
                    ? "deviceUse" : "none";
            _started = HasAny(root, [Marker(StartedMarker)]);
            _installation = installation();
        }
        catch { _history = "unknown"; }
        _initial = ObserveStartup();
        // Only the answers that a later progress save could change are kept.
        _marker = _initial.Reason == "updateInstallation" || _initial.Reason == "previousUse" && _history == "deviceUse"
            ? ReturningMarker
            : _initial.Eligibility == "firstUse" && !_started ? StartedMarker : null;
        _ = EnsureRecorded();
    }

    // Keep the startup result even after mode switching saves resumable progress.
    internal FirstUseStartupObservation Read() => _initial;

    // Called at startup and again before the guide or Usage mode saves anything.
    // False means the marker still could not be written: the caller must not save,
    // so the next start sees the same data and classifies the same way.
    internal bool EnsureRecorded()
    {
        if (_marker is null) return true;
        try
        {
            if (HasAny(_root, [Marker(_marker)])) return true;
            var directory = Path.Combine(Path.GetFullPath(_root), MarkerDirectory);
            // Throws for a file in its place or a link anywhere on the path.
            _ = HasAny(_root, [MarkerDirectory], directories: true);
            Directory.CreateDirectory(directory);
            // Recheck after creation: never write through a link planted meanwhile.
            if (HasAny(_root, [Marker(_marker)])) return true;
            using var file = new FileStream(Path.Combine(directory, _marker), FileMode.CreateNew, FileAccess.Write, FileShare.None);
            file.Write("1"u8);
            file.Flush(true);
            return true;
        }
        catch (IOException) when (SafeExists(_marker)) { return true; }
        catch { return false; }
    }

    private bool SafeExists(string name)
    {
        try { return HasAny(_root, [Marker(name)]); }
        catch { return false; }
    }

    private static string Marker(string name) => Path.Combine(MarkerDirectory, name);

    private FirstUseStartupObservation ObserveStartup()
    {
        // Previous use determines display policy even if its old marker is not
        // an identity or a current completion receipt. Never parse account files.
        if (_history is "legacyUse" or "returning") return new("returning", "previousUse", false);
        if (_history == "unknown") return new("unknown", "unreadableHistory", false);
        LocalFirstUseSnapshot local;
        try
        {
            if (_completion.Read() is not null) return new("returning", "completedSetup", false);
            local = _local.Read();
        }
        catch { return new("unknown", "unreadableProgress", false); }
        // Guide progress resumes. Without it, a store written only by the
        // settings log panel of an updated install is previous use, not setup.
        if (local.Revision > 0 && (local.Progress is not null || _installation?.Kind != "update"))
            return new("firstUse", "resume", true);
        // A user first classified as new here stays in first-use setup until it
        // is completed, even with nothing saved yet (quit before the first save)
        // and whatever an update, rollback or ordinary device use left behind.
        if (_started) return new("firstUse", local.Revision > 0 ? "resume" : "freshInstallation", local.Revision > 0);
        if (_history == "deviceUse") return new("returning", "previousUse", false);
        return _installation?.Kind switch
        {
            "fresh" => new("firstUse", "freshInstallation", false),
            "update" => new("returning", "updateInstallation", false),
            _ => new("unknown", "installationUnknown", false)
        };
    }

    // Files (preferences, event journal) and data directories (account log and
    // play-time stores) appear only after real use. A first-use session saves
    // resumable progress as soon as setup opens, so they cannot hide a new user.
    private static bool HasAny(string root, string[] names, bool directories = false)
    {
        var full = Path.GetFullPath(root);
        foreach (var name in names)
        {
            var path = Path.Combine(full, name);
            var exists = false;
            for (var node = path; node is not null; node = Path.GetDirectoryName(node))
            {
                FileAttributes attributes;
                try { attributes = File.GetAttributes(node); }
                catch (FileNotFoundException) { continue; }
                catch (DirectoryNotFoundException) { continue; }
                if (attributes.HasFlag(FileAttributes.ReparsePoint)) throw new IOException();
                if (node == path)
                {
                    if (attributes.HasFlag(FileAttributes.Directory) != directories) throw new IOException();
                    // Presence proves previous use, not validity or completion.
                    exists = true;
                }
            }
            if (exists) return true;
        }
        return false;
    }

    internal static FirstUseInstallSource? ReadInstalledSource(string? client, string host, string root)
        => ReadInstalledSource(client, host, root, ReadInstalledObservation);

    // Internal filesystem/registration seam. Product callers always use the fixed HKCU reader.
    internal static FirstUseInstallSource? ReadInstalledSource(string? client, string host, string root,
        Func<FirstUseInstalledObservation> read)
    {
        if (client is null) return null;
        try
        {
            var observed = read();
            var registration = observed.Registration;
            registration.Require(client, host, root);
            var source = observed.Source;
            if (source?.Kind is not ("fresh" or "update") || source.Version != registration.Version) return null;
            // Same-version replacement can change only the source stamp. Recheck
            // both registration and stamp, never turn a raced update into first use.
            if (read() != observed) return null;
            return source;
        }
        catch { return null; }
    }

    private static FirstUseInstalledObservation ReadInstalledObservation()
    {
        var registration = InstalledUpdateRegistration.Read();
        using var hive = RegistryKey.OpenBaseKey(RegistryHive.CurrentUser, RegistryView.Registry64);
        using var key = hive.OpenSubKey(FlutterInstallationIdentity.RegistryPath);
        var kind = key?.GetValue("StarBridgeFirstUseSource") as string;
        var version = key?.GetValue("StarBridgeFirstUseSourceVersion") as string;
        return new(registration, kind is not null && version is not null ? new(kind, version) : null);
    }
}
