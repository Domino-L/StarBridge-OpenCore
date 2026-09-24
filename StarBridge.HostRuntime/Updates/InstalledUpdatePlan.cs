using System.Diagnostics;

namespace StarBridge.HostRuntime.Updates;

internal sealed record InstalledUpdatePlan(int SchemaVersion, string Installation, string CurrentVersion,
    string DataRoot, int ClientPid, long ClientStartTicks, int HostPid, long HostStartTicks, string InstallerName)
{
    internal const string FileName = "installed-plan.json";
    internal static InstalledUpdatePlan Read(string path, string helper)
    {
        path = InstalledUpdateFiles.Normalize(path);
        var root = Path.GetDirectoryName(path)!;
        if (Path.GetFileName(path) != FileName ||
            !InstalledUpdateRegistration.Same(helper, Path.Combine(root, "helper", "StarBridge.UpdateHelper.exe"))) throw new InvalidDataException();
        var plan = InstalledUpdateFiles.Read<InstalledUpdatePlan>(path, 16384);
        plan.Validate(root);
        return plan;
    }

    internal void Validate(string root)
    {
        if (SchemaVersion != 1 || ClientPid <= 0 || HostPid <= 0 || ClientPid == HostPid ||
            ClientStartTicks <= 0 || HostStartTicks <= 0 || InstallerName is null ||
            !InstallerName.StartsWith("installer-", StringComparison.Ordinal) || !InstallerName.EndsWith(".exe", StringComparison.Ordinal) ||
            !Guid.TryParseExact(InstallerName[10..^4], "N", out _) ||
            InstalledUpdateFiles.Normalize(DataRoot) != DataRoot ||
            InstalledUpdateRegistration.Contains(Installation, DataRoot) || InstalledUpdateRegistration.Contains(DataRoot, Installation))
            throw new InvalidDataException("Invalid installed update plan.");
        _ = ApplicationUpdateVersion.Parse(CurrentVersion);
        InstalledUpdateFiles.RequireSibling(Installation, root);
    }

    internal static Process Pin(int pid, long ticks, string path)
    {
        var process = Process.GetProcessById(pid);
        try {
            if (process.HasExited || process.StartTime.ToUniversalTime().Ticks != ticks ||
                !InstalledUpdateRegistration.Same(process.MainModule?.FileName, path)) throw new InvalidDataException("Update process changed.");
            _ = process.SafeHandle;
            return process;
        } catch { process.Dispose(); throw; }
    }
}
