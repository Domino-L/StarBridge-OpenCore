using System.Diagnostics;

namespace StarBridge.HostRuntime.Storage;

public sealed class StorageMigrationInstallation
{
    private readonly string _bootstrap, _helper;
    private readonly Process _client;
    public StorageMigrationInstallation(string bootstrap, string helper, Process client)
    { _bootstrap = StorageRootLocator.Normalize(bootstrap); _helper = Path.GetFullPath(helper); _client = client; }

    public async Task HandoffAsync(string source, string destination, CancellationToken cancellation)
    {
        cancellation.ThrowIfCancellationRequested();
        StorageMigrationWpfGuard.RequireStopped();
        if (!_helper.EndsWith(Path.Combine("maintenance", "StarBridge.UpdateHelper.exe"), StringComparison.OrdinalIgnoreCase) ||
            !File.Exists(_helper)) throw new FileNotFoundException("Storage helper unavailable.");
        _client.Refresh();
        using var host = Process.GetCurrentProcess();
        if (_client.HasExited || string.IsNullOrWhiteSpace(_client.MainModule?.FileName) || string.IsNullOrWhiteSpace(host.MainModule?.FileName))
            throw new IOException("Client process unavailable.");
        var nonce = Guid.NewGuid().ToString("N");
        var plan = new StorageMigrationPlan(1, nonce, _bootstrap,
            StorageRootLocator.Normalize(source), StorageRootLocator.Normalize(destination),
            _client.Id, _client.StartTime.ToUniversalTime().Ticks, Path.GetFullPath(_client.MainModule.FileName),
            host.Id, host.StartTime.ToUniversalTime().Ticks, Path.GetFullPath(host.MainModule.FileName));
        var path = StorageMigrationPlanFile.Write(_bootstrap, plan);
        Process? helper = null;
        try { helper = await StorageMigrationHandoff.StartAsync(_helper, path, nonce, cancellation); }
        catch
        {
            TryDeleteOwnPlan(path, nonce);
            // Also explain a WPF process that started during helper preparation.
            StorageMigrationWpfGuard.RequireStopped();
            throw;
        }
        finally { helper?.Dispose(); }
    }

    private static void TryDeleteOwnPlan(string path, string nonce)
    {
        try { StorageMigrationPlanFile.DeleteIfOwned(path, Path.GetDirectoryName(path)!, nonce); }
        catch { }
    }
}
