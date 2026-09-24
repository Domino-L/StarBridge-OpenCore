namespace StarBridge.HostRuntime.Settings;

using Microsoft.Win32;

internal interface IApplicationStartupRegistration
{
    bool TrySetEnabled(bool enabled, out string? error);

    bool TrySave(bool enabled, bool previous, Action save, out string? error) =>
        StartupPreferenceTransaction.Save(TrySetEnabled, enabled, previous, save, out error);
}

internal static class StartupPreferenceTransaction
{
    internal delegate bool SetEnabled(bool enabled, out string? error);

    internal static bool Save(SetEnabled set, bool enabled, bool previous, Action save, out string? error)
    {
        if (!set(enabled, out error)) return false;
        try { save(); }
        catch
        {
            // Preserve the save failure. Never report a successful preference change.
            try { set(previous, out _); } catch { }
            throw;
        }
        return true;
    }
}

internal sealed class InertApplicationStartupRegistration : IApplicationStartupRegistration
{
    public bool TrySetEnabled(bool enabled, out string? error)
    {
        error = null;
        return true;
    }
}

internal sealed class WindowsApplicationStartupRegistration : IApplicationStartupRegistration
{
    internal const string StartupArgument = "--startup";
    internal const string RegistryPath = @"Software\Microsoft\Windows\CurrentVersion\Run";
    internal const string RegistryValueName = "StarBridge";

    private readonly string _applicationExecutablePath;
    private readonly Func<IDisposable> _acquireLease;
    private readonly StartupPreferenceTransaction.SetEnabled _set;

    internal WindowsApplicationStartupRegistration(string applicationExecutablePath,
        Func<IDisposable>? acquireLease = null, StartupPreferenceTransaction.SetEnabled? set = null)
    {
        if (string.IsNullOrWhiteSpace(applicationExecutablePath))
        {
            throw new ArgumentException(
                "The Flutter application executable path is required.",
                nameof(applicationExecutablePath));
        }

        _applicationExecutablePath = Path.GetFullPath(
            applicationExecutablePath.Trim().Trim('"'));
        _acquireLease = acquireLease ?? ApplicationStartupLease.Acquire;
        _set = set ?? SetEnabledUnderLease;
    }

    internal static string BuildCommand(string executablePath)
    {
        var normalizedPath = Path.GetFullPath(
            (executablePath ?? string.Empty).Trim().Trim('"'));
        return $"\"{normalizedPath}\" {StartupArgument}";
    }

    public bool TrySetEnabled(bool enabled, out string? error)
    {
        try
        {
            using var lease = _acquireLease();
            return _set(enabled, out error);
        }
        catch (Exception exception) when (
            exception is IOException or UnauthorizedAccessException or System.Security.SecurityException)
        {
            error = exception.GetType().Name;
            return false;
        }
    }

    public bool TrySave(bool enabled, bool previous, Action save, out string? error)
    {
        IDisposable lease;
        try { lease = _acquireLease(); }
        catch (Exception exception) when (
            exception is IOException or UnauthorizedAccessException or System.Security.SecurityException)
        {
            error = exception.GetType().Name;
            return false;
        }
        using (lease)
            return StartupPreferenceTransaction.Save(_set, enabled, previous, save, out error);
    }

    private bool SetEnabledUnderLease(bool enabled, out string? error)
    {
        try
        {
            if (!enabled)
            {
                using var existing = Registry.CurrentUser.OpenSubKey(RegistryPath, writable: true);
                existing?.DeleteValue(RegistryValueName, throwOnMissingValue: false);
                error = null;
                return true;
            }

            using var key = Registry.CurrentUser.CreateSubKey(RegistryPath, writable: true);
            if (key is null)
            {
                error = "registry_key_unavailable";
                return false;
            }

            key.SetValue(
                RegistryValueName,
                BuildCommand(_applicationExecutablePath),
                RegistryValueKind.String);
            error = null;
            return true;
        }
        catch (Exception exception) when (
            exception is IOException or UnauthorizedAccessException or System.Security.SecurityException)
        {
            error = exception.GetType().Name;
            return false;
        }
    }
}
