using System.Diagnostics;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Onboarding;

internal static class FirstUseModeRecoveryTests
{
    internal static async Task Run()
    {
        await Case("partial stop without receipt cannot be completed on cold startup", MissingReceipt);
        await Case("live original process cannot be replaced by a cold recovery acknowledgement", OriginalOwnerRunning);
        await Case("real stopped child process supports explicit recovery without restoring authorization", CompletedOwnerExited);
        await Case("later mode revision cannot reuse a former retirement", WrongRevision);
        await Case("damaged receipt remains intact until explicit repair and retry", DamagedReceipt);
        await Case("busy final writer and cancellation preserve pending intent without acknowledgement", BusyAndCancelled);
        await Case("retirement storage demands all real stop facts and final owner guards", ReceiptGuards);
        await Case("strict retirement documents reject missing, duplicate, unknown and false stop facts", StrictReceipts);
    }
    private static async Task Case(string name, Func<Task> run)
    { await run(); Console.WriteLine("PASS first-use mode recovery: " + name); }
    private static string Op() => Guid.NewGuid().ToString("N");
    private static string StatePath(string root) => Path.Combine(root, "first-use-mode-v1", "state.bin");
    private static string ReceiptPath(string root) => Path.Combine(root, "first-use-mode-v1", "retirement.bin");
    private static void Require(bool value, string message) { if (!value) throw new InvalidOperationException(message); }
    private static Task<AccountBridgeRuntime> NoOnline(CancellationToken _) =>
        throw new InvalidOperationException("Cold recovery cannot construct an account/OAuth/network owner.");
    private static async Task Expect(string code, Func<Task> run)
    {
        try { await run(); } catch (LocalFirstUseException error) when (error.Code == code) { return; }
        throw new InvalidOperationException("Expected " + code);
    }

    internal static async Task WriteCompletedStop(string root)
    {
        // This private console selector opens no UI. The fixture validates the
        // exact random Temp target before entering it; it never accepts a user
        // data directory or removes the parent-owned fixture on exit.
        using var f = new LocalAccountStopTests.Fixture(sharedRoot: root, initializeLocalState: false, preserveRoot: true);
        await AccountBridgeRuntime.CreateWithFirstUseModeAsync(root, _ => Task.FromResult(f.Runtime));
        FileStream? writer = null;
        f.Transport.RevokeReply = () => writer = new FileStream(StatePath(root) + ".lock",
            FileMode.Open, FileAccess.ReadWrite, FileShare.None);
        try
        {
            await Expect("firstUse.mode_write_failed", () => f.Runtime.FirstUseMode!.ApplyLocalAsync(0, Op(), f.Host.Generation));
            var pending = new FirstUseModeStore(root).Read();
            var receipt = new FirstUseModeStore(root).ReadRetirement();
            Require(f.Vault.Deleted && f.Host.CurrentContext is null && pending.Phase == "localPending" &&
                receipt?.IsFor(pending) == true && receipt.Owner.ProcessId == Environment.ProcessId &&
                receipt.Owner.ReadExit() == "running", "child must persist actual completed retirement, not synthetic ready booleans");
            f.RequireLocalStateUnchanged();
        }
        finally { writer?.Dispose(); f.Transport.RevokeReply = null; }
    }
    internal static async Task ChildStop(LocalAccountStopTests.Fixture fixture)
    {
        var assembly = typeof(FirstUseModeRecoveryTests).Assembly.Location;
        var start = new ProcessStartInfo("dotnet") { UseShellExecute = false, CreateNoWindow = true,
            RedirectStandardOutput = true, RedirectStandardError = true, WorkingDirectory = Path.GetDirectoryName(assembly)! };
        start.ArgumentList.Add(assembly);
        start.ArgumentList.Add("--first-use-mode-recovery-child");
        start.ArgumentList.Add(fixture.Root);
        using var process = Process.Start(start) ?? throw new InvalidOperationException("Could not start fixture child");
        var output = process.StandardOutput.ReadToEndAsync(); var error = process.StandardError.ReadToEndAsync();
        // A timeout must not restart, delete or orphan the fixture's still-live
        // child. The harness retains the handle until authoritative actual exit.
        await process.WaitForExitAsync();
        Require(process.ExitCode == 0, "fixture child failed: " + await output + await error);
        var receipt = new FirstUseModeStore(fixture.Root).ReadRetirement()!;
        Require(receipt.Owner.ProcessId == process.Id && receipt.Owner.ReadExit() == "exited", "authoritative child exit must match the recorded owner");
        fixture.RequireLocalStateUnchanged();
    }

    private static async Task MissingReceipt()
    {
        using var f = new LocalAccountStopTests.Fixture();
        new FirstUseModeStore(f.Root).Save(0, Op(), "localPending", () => true);
        var bytes = File.ReadAllBytes(StatePath(f.Root));
        using var cold = await AccountBridgeRuntime.CreateWithFirstUseModeAsync(f.Root, NoOnline);
        Require((await cold.FirstUseMode!.RecoverLocalAsync(1, Op())).State == "recoveryRequired" &&
            !cold.FirstUseMode.LocalMode().Active && !File.Exists(ReceiptPath(f.Root)) &&
            File.ReadAllBytes(StatePath(f.Root)).SequenceEqual(bytes), "process exit alone proves no withdrawal, drain or credential removal");
        f.RequireLocalStateUnchanged();
    }

    private static async Task OriginalOwnerRunning()
    {
        using var f = new LocalAccountStopTests.Fixture();
        await AccountBridgeRuntime.CreateWithFirstUseModeAsync(f.Root, _ => Task.FromResult(f.Runtime));
        FileStream? writer = null;
        f.Transport.RevokeReply = () => writer = new FileStream(StatePath(f.Root) + ".lock", FileMode.Open, FileAccess.ReadWrite, FileShare.None);
        try { await Expect("firstUse.mode_write_failed", () => f.Runtime.FirstUseMode!.ApplyLocalAsync(0, Op(), f.Host.Generation)); }
        finally { writer?.Dispose(); f.Transport.RevokeReply = null; }
        using var cold = await AccountBridgeRuntime.CreateWithFirstUseModeAsync(f.Root, NoOnline);
        Require((await cold.FirstUseMode!.RecoverLocalAsync(1, Op())).State == "ownerRunning" &&
            !cold.FirstUseMode.LocalMode().Active, "live owner requires its own lifecycle, not borrowed process-exit facts");
        Require((await f.Runtime.FirstUseMode!.ApplyLocalAsync(1, Op(), f.Host.Generation)).State == "local" && f.Vault.Deletions == 1,
            "the original owner can explicitly finish its own real stopped transition");
        f.RequireLocalStateUnchanged();
    }

    private static async Task CompletedOwnerExited()
    {
        using var f = new LocalAccountStopTests.Fixture(); await ChildStop(f);
        using var cold = await AccountBridgeRuntime.CreateWithFirstUseModeAsync(f.Root, NoOnline);
        Require(cold.FirstUseMode!.Current.State == "recoveryRequired" && !cold.FirstUseMode.LocalMode().Active,
            "opening a cold runtime does not automatically rewrite pending intent");
        var recovered = await cold.FirstUseMode.RecoverLocalAsync(1, Op());
        Require(recovered is { State: "local", Revision: 2, PublicationSuspended: true } && cold.FirstUseMode.LocalMode().Active &&
            cold.FirstUseGame is not null && cold.FirstUseStatistics is not null && cold.FirstUseOverlaySource!.Capture() is not null &&
            !f.Vault.Deleted && f.Vault.Loads == 0 && f.Transport.AllRequests == 0, "actual local consumers activate without account restoration or new revocation");
        f.RequireLocalStateUnchanged();
    }

    private static async Task WrongRevision()
    {
        using var f = new LocalAccountStopTests.Fixture(); await ChildStop(f);
        var store = new FirstUseModeStore(f.Root);
        store.Save(1, Op(), "localPending", () => true);
        var bytes = File.ReadAllBytes(StatePath(f.Root));
        using var cold = await AccountBridgeRuntime.CreateWithFirstUseModeAsync(f.Root, NoOnline);
        Require((await cold.FirstUseMode!.RecoverLocalAsync(2, Op())).State == "recoveryRequired" &&
            !cold.FirstUseMode.LocalMode().Active && File.ReadAllBytes(StatePath(f.Root)).SequenceEqual(bytes),
            "an old receipt cannot satisfy a later pending revision or operation");
    }

    private static async Task DamagedReceipt()
    {
        using var f = new LocalAccountStopTests.Fixture(); await ChildStop(f);
        var original = File.ReadAllBytes(ReceiptPath(f.Root)); var damaged = Encoding.UTF8.GetBytes("broken receipt");
        File.WriteAllBytes(ReceiptPath(f.Root), damaged);
        var pending = File.ReadAllBytes(StatePath(f.Root));
        using var cold = await AccountBridgeRuntime.CreateWithFirstUseModeAsync(f.Root, NoOnline);
        await Expect("firstUse.mode_receipt_read_failed", () => cold.FirstUseMode!.RecoverLocalAsync(1, Op()));
        Require(File.ReadAllBytes(ReceiptPath(f.Root)).SequenceEqual(damaged) && File.ReadAllBytes(StatePath(f.Root)).SequenceEqual(pending) &&
            !cold.FirstUseMode!.LocalMode().Active, "damaged recovery evidence is preserved, not reset or accepted");
        File.WriteAllBytes(ReceiptPath(f.Root), original);
        Require(cold.FirstUseMode!.Current.State == "recoveryRequired", "file repair does not automatically apply a user choice");
        Require((await cold.FirstUseMode.RecoverLocalAsync(1, Op())).State == "local", "explicit retry uses the repaired exact receipt");
    }

    private static async Task BusyAndCancelled()
    {
        using var f = new LocalAccountStopTests.Fixture(); await ChildStop(f);
        var bytes = File.ReadAllBytes(StatePath(f.Root));
        using var cold = await AccountBridgeRuntime.CreateWithFirstUseModeAsync(f.Root, NoOnline);
        using (var cancelled = new CancellationTokenSource())
        {
            cancelled.Cancel();
            try { await cold.FirstUseMode!.RecoverLocalAsync(1, Op(), cancelled.Token); }
            catch (OperationCanceledException) { }
        }
        using (var lease = new FileStream(StatePath(f.Root) + ".lock", FileMode.Open, FileAccess.ReadWrite, FileShare.None))
            await Expect("firstUse.mode_write_failed", () => cold.FirstUseMode!.RecoverLocalAsync(1, Op()));
        Require(!cold.FirstUseMode!.LocalMode().Active && File.ReadAllBytes(StatePath(f.Root)).SequenceEqual(bytes),
            "cancelled or failed recovery cannot grant local readiness");
        Require((await cold.FirstUseMode.RecoverLocalAsync(1, Op())).State == "local", "explicit retry retains the real receipt");
    }

    private static async Task ReceiptGuards()
    {
        using var f = new LocalAccountStopTests.Fixture();
        var store = new FirstUseModeStore(f.Root);
        var pending = store.Save(0, Op(), "localPending", () => true);
        await Expect("firstUse.mode_receipt_required", () => Task.Run(() => store.SaveRetirement(pending,
            new("publicationPending", 0, true, false, true, true), () => true)));
        Require(!File.Exists(ReceiptPath(f.Root)), "incomplete stop never creates a receipt");
        var completed = await f.Runtime.StopAccountForLocalModeAsync(f.Host.Generation);
        var calls = 0;
        await Expect("firstUse.context_changed", () => Task.Run(() => store.SaveRetirement(pending, completed, () => ++calls < 2)));
        Require(!File.Exists(ReceiptPath(f.Root)) && Directory.GetFiles(Path.GetDirectoryName(ReceiptPath(f.Root))!, "*.retirement.tmp").Length == 0,
            "late ownership loss preserves the former evidence and closes only its own temporary file");
        store.SaveRetirement(pending, completed, () => f.Runtime.IsLocalAccountStopped(completed.Generation));
        using (var lease = new FileStream(ReceiptPath(f.Root) + ".lock", FileMode.Open, FileAccess.ReadWrite, FileShare.None))
            await Expect("firstUse.mode_receipt_write_failed", () => Task.Run(() => store.SaveRetirement(pending, completed, () => true)));
        Require(store.ReadRetirement()!.IsFor(pending), "busy receipt writer preserves the original valid retirement");
        f.RequireLocalStateUnchanged();
    }

    private static async Task StrictReceipts()
    {
        using var f = new LocalAccountStopTests.Fixture(); await ChildStop(f);
        var receipt = new FirstUseModeStore(f.Root).ReadRetirement()!;
        var json = new JsonSerializerOptions(JsonSerializerDefaults.Web);
        var documents = new[] { "{}", "{\"schemaVersion\":1,\"schemaVersion\":1,\"value\":{}}",
            JsonSerializer.Serialize(new { schemaVersion = 2, value = receipt }, json),
            JsonSerializer.Serialize(new { schemaVersion = 1, value = receipt, extra = true }, json),
            JsonSerializer.Serialize(new { schemaVersion = 1, value = receipt with { PublicationStopped = false } }, json),
            JsonSerializer.Serialize(new { schemaVersion = 1, value = receipt with { SavedAt = DateTimeOffset.UtcNow.AddDays(1) } }, json),
            JsonSerializer.Serialize(new { schemaVersion = 1, value = receipt with { Owner = receipt.Owner with { ProcessId = 0 } } }, json)
        };
        foreach (var document in documents)
        {
            var bytes = ProtectedData.Protect(Encoding.UTF8.GetBytes(document),
                Encoding.UTF8.GetBytes("StarBridge.first-use-retirement.v1"), DataProtectionScope.CurrentUser);
            File.WriteAllBytes(ReceiptPath(f.Root), bytes);
            using var cold = await AccountBridgeRuntime.CreateWithFirstUseModeAsync(f.Root, NoOnline);
            await Expect("firstUse.mode_receipt_read_failed", () => cold.FirstUseMode!.RecoverLocalAsync(1, Op()));
            Require(!cold.FirstUseMode!.LocalMode().Active && File.ReadAllBytes(ReceiptPath(f.Root)).SequenceEqual(bytes),
                "invalid complete-looking metadata cannot satisfy the actual recovery contract");
        }
        f.RequireLocalStateUnchanged();
    }
}
