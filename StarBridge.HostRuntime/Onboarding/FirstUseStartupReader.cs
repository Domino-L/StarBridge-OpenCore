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
    private readonly LocalFirstUseStore _local;
    private readonly FirstUseCompletionStore _completion;
    private readonly string _history;
    private readonly FirstUseInstallSource? _installation;
    internal FirstUseStartupReader(string root, Func<FirstUseInstallSource?> installation)
    {
        _local = new(root);
        _completion = new(root);
        try
        {
            _history = HasAny(root, ["desktop.config", "onboarding.complete", "onboarding-introduction.read"])
                ? "legacyUse"
                : HasAny(root, ["application-preferences.v1.json", "application-behavior.json", "local-event-log.json",
                      "overlay.settings", "overlay.layout", "overlay.presets", "notification.settings.json",
                      "sync-privacy.settings.json", "local-play-session.json"]) ||
                  HasAny(root, ["game-log-local-v1", "gameplay-time-local-v1", "personal-profile-cache", "chat-history"], directories: true)
                    ? "deviceUse" : "none";
            _installation = installation();
        }
        catch { _history = "unknown"; }
    }

    internal FirstUseStartupObservation Read()
    {
        // Previous use determines display policy even if its old marker is not
        // an identity or a current completion receipt. Never parse account files.
        if (_history == "legacyUse") return new("returning", "previousUse", false);
        if (_history == "unknown") return new("unknown", "unreadableHistory", false);
        LocalFirstUseSnapshot local;
        try
        {
            if (_completion.Read() is not null) return new("returning", "completedSetup", false);
            local = _local.Read();
        }
        catch { return new("unknown", "unreadableProgress", false); }
        if (local.Revision > 0) return new("firstUse", "resume", true);
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
