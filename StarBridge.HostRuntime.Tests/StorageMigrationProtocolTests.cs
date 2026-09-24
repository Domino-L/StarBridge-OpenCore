using System.Text.Json;
using StarBridge.HostRuntime.Storage;
using StarBridge.NativeBridge;

internal static class StorageMigrationProtocolTests
{
    internal static async Task Verify()
    {
        var fixture = Path.Combine(Path.GetTempPath(), "starbridge-migration-protocol-" + Guid.NewGuid().ToString("N"));
        var bootstrap = Path.Combine(fixture, "bootstrap");
        var source = Path.Combine(fixture, "source");
        var destination = Path.Combine(fixture, "destination");
        Directory.CreateDirectory(bootstrap);
        Directory.CreateDirectory(source);
        try
        {
            VerifyWpfGuard();
            VerifyPlan(bootstrap, source, destination, fixture);
            await VerifyResultAndBridge(bootstrap, source, destination);
            VerifyNoOpRecovery(fixture);
        }
        finally { Directory.Delete(fixture, recursive: true); } // Only this newly-created isolated fixture.
    }

    private static void VerifyWpfGuard()
    {
        var name = @"Local\starbridge-migration-guard-test-" + Guid.NewGuid().ToString("N");
        using var ready = new ManualResetEventSlim();
        using var release = new ManualResetEventSlim();
        var holder = new Thread(() =>
        {
            using var mutex = new Mutex(true, name);
            ready.Set();
            release.Wait();
            mutex.ReleaseMutex();
        });
        holder.Start();
        try
        {
            if (!ready.Wait(TimeSpan.FromSeconds(5))) throw new Exception("Guard fixture did not start.");
            try { StorageMigrationWpfGuard.RequireStopped(name); throw new Exception("Active WPF writer was not identified."); }
            catch (StorageMigrationWpfRunningException) { }
        }
        finally { release.Set(); holder.Join(); }
        StorageMigrationWpfGuard.RequireStopped(name);
    }

    private static void VerifyPlan(string bootstrap, string source, string destination, string fixture)
    {
        var nonce = Guid.NewGuid().ToString("N");
        var plan = new StorageMigrationPlan(1, nonce, bootstrap, source, destination,
            101, 1001, Path.Combine(fixture, "client", "starbridge_flutter.exe"),
            202, 2002, Path.Combine(fixture, "client", "native_host", "StarBridge.NativeHost.exe"));
        var path = StorageMigrationPlanFile.Write(bootstrap, plan);
        if (StorageMigrationPlanFile.Read(path, bootstrap) != plan) throw new Exception("Migration plan did not round-trip exactly.");
        try { StorageMigrationPlanFile.Read(path, Path.Combine(fixture, "other")); throw new Exception("Plan escaped its bootstrap."); }
        catch (InvalidDataException) { }

        File.WriteAllText(path, JsonSerializer.Serialize(new
        {
            schemaVersion = 1, nonce, bootstrap, source, destination,
            clientPid = 101, clientStartTicks = 1001, clientPath = plan.ClientPath,
            hostPid = 202, hostStartTicks = 2002, hostPath = plan.HostPath,
            callerPath = destination,
        }));
        try { StorageMigrationPlanFile.Read(path, bootstrap); throw new Exception("Plan accepted an untrusted extra field."); }
        catch (JsonException) { }
        StorageMigrationPlanFile.Write(bootstrap, plan);
        try { StorageMigrationPlanFile.DeleteIfOwned(path, bootstrap, Guid.NewGuid().ToString("N")); throw new Exception("Wrong plan nonce deleted the handoff."); }
        catch (InvalidOperationException) { }
        if (!File.Exists(path)) throw new Exception("Wrong plan nonce removed the handoff.");
        Directory.CreateDirectory(destination);
        File.WriteAllText(Path.Combine(destination, "migrated.json"), "complete");
        StorageMigrationPlanFile.DeleteIfOwned(path, bootstrap, nonce);
        if (File.Exists(path)) throw new Exception("Owned migration plan was not removed.");
    }

    private static async Task VerifyResultAndBridge(string bootstrap, string source, string destination)
    {
        var nonce = Guid.NewGuid().ToString("N");
        var resultPath = Path.Combine(bootstrap, StorageMigrationPlanFile.ResultName);
        WriteResult(resultPath, nonce, source, destination);
        var store = new StorageMigrationResultStore(bootstrap);
        var first = store.Read();
        var second = store.Read();
        if (first is null || second != first || first.State != "migrated") throw new Exception("Migration result was not durable before acknowledgement.");
        try { store.Acknowledge(Guid.NewGuid().ToString("N")); throw new Exception("Wrong result nonce was acknowledged."); }
        catch (InvalidOperationException) { }
        if (!File.Exists(resultPath)) throw new Exception("Wrong acknowledgement removed the result.");

        long generation = 9;
        var selection = new StorageMigrationSelection(bootstrap, () => source,
            _ => throw new Exception("Result route opened a picker."),
            (_, _, _) => throw new Exception("Result route started a migration."));
        using var dispatcher = new StorageMigrationBridgeDispatcher(selection, () => generation, store);
        var resultRequest = BridgeEnvelope.Request(StorageMigrationBridgeDispatcher.ResultRequest,
            Guid.NewGuid().ToString("N"), generation, new { schemaVersion = 1 });
        var response = (await dispatcher.DispatchAsync(resultRequest)).Response;
        if (response.Status != "ok" || response.Payload.GetProperty("state").GetString() != "migrated" ||
            response.Payload.GetProperty("nonce").GetString() != nonce || !File.Exists(resultPath))
            throw new Exception("Result bridge changed or removed the durable result.");

        var wrongAck = BridgeEnvelope.Request(StorageMigrationBridgeDispatcher.AcknowledgeRequest,
            Guid.NewGuid().ToString("N"), generation, new { schemaVersion = 1, nonce = Guid.NewGuid().ToString("N") });
        if ((await dispatcher.DispatchAsync(wrongAck)).Response.Status != "error" || !File.Exists(resultPath))
            throw new Exception("Bridge accepted the wrong acknowledgement.");
        var extra = resultRequest with { Payload = BridgePayload.From(new { schemaVersion = 1, source }) };
        if ((await dispatcher.DispatchAsync(extra)).Response.Status != "error") throw new Exception("Result route accepted caller storage data.");
        var account = resultRequest with { AccountContext = new("test", "test", "test") };
        if ((await dispatcher.DispatchAsync(account)).Response.Status != "error") throw new Exception("Result route accepted account context.");

        var ack = BridgeEnvelope.Request(StorageMigrationBridgeDispatcher.AcknowledgeRequest,
            Guid.NewGuid().ToString("N"), generation, new { schemaVersion = 1, nonce });
        if ((await dispatcher.DispatchAsync(ack)).Response.Status != "ok" || File.Exists(resultPath))
            throw new Exception("Exact result acknowledgement was not applied.");

        File.WriteAllText(resultPath, JsonSerializer.Serialize(new
        {
            schemaVersion = 1, nonce, state = "migrated", source, destination,
            completedAt = DateTimeOffset.UtcNow, unexpected = true,
        }));
        try { store.Read(); throw new Exception("Result accepted an untrusted extra field."); }
        catch (JsonException) { }
        if (!File.Exists(resultPath)) throw new Exception("Invalid result was silently discarded.");
    }

    private static void VerifyNoOpRecovery(string fixture)
    {
        var absent = Path.Combine(fixture, "absent-bootstrap");
        if (StorageMigrationRecovery.RecoverPending(absent) != "none" || Directory.Exists(absent))
            throw new Exception("No-op recovery created storage.");
    }

    private static void WriteResult(string path, string nonce, string source, string destination)
        => File.WriteAllText(path, JsonSerializer.Serialize(new
        {
            schemaVersion = 1, nonce, state = "migrated", source, destination,
            completedAt = DateTimeOffset.UtcNow,
        }));
}
