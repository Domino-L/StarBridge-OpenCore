using System.Security.Cryptography;
using System.Text;
using StarBridge.HostRuntime.Updates;

internal static class InstalledUpdate
{
    internal static async Task<int> Run(string path, bool recovery)
    {
        try
        {
            var helper = Environment.ProcessPath ?? throw new InvalidDataException();
            var plan = InstalledUpdatePlan.Read(path, helper);
            var root = Path.GetDirectoryName(Path.GetFullPath(path))!;
            var id = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(plan.Installation.ToUpperInvariant())));
            using var gate = new Semaphore(1, 1, "Local\\StarBridge.InstalledUpdate." + id);
            if (!gate.WaitOne(0)) return 4;
            try {
                using var operations = new InstalledUpdateWindowsOperations(plan, root, recovery);
                var transaction = new InstalledUpdateTransaction(plan.Installation, root);
                if (recovery) return await transaction.RecoverAsync(operations) == "rolled-back" ? 0 : 5;
                using var preparation = new CancellationTokenSource(TimeSpan.FromSeconds(25));
                await operations.VerifyInstallerAsync(preparation.Token);
                // The record may be v1 or v2; use the version the operations verified, never a v1-only re-read.
                var state = await transaction.ApplyAsync(operations.Version, operations,
                    token => FlutterUpdateHandoff.ReportPreparedAsync(token, required: true));
                return state == "committed" ? 0 : state == "rolled-back" ? 5 : 6;
            } finally { gate.Release(); }
        }
        catch { return 7; } // Recovery material is retained; never dump user paths or secrets.
    }
}
