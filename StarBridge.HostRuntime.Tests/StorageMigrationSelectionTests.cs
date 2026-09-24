using StarBridge.HostRuntime.Storage;

internal static class StorageMigrationSelectionTests
{
    internal static async Task Verify()
    {
        var fixture = Path.Combine(Path.GetTempPath(), "starbridge-migration-choice-" + Guid.NewGuid().ToString("N"));
        var bootstrap = Path.Combine(fixture, "bootstrap");
        var source = Path.Combine(fixture, "source");
        var target = Path.Combine(fixture, "destination");
        Directory.CreateDirectory(bootstrap); Directory.CreateDirectory(source);
        var locator = Path.Combine(bootstrap, StorageRootLocator.FileName);
        File.WriteAllText(locator, source);
        try
        {
            foreach (var mode in new[] { "success", "cancel-picker", "same", "stale", "pointer", "occupied", "handoff-failure", "cancel-confirm", "superseded" })
            {
                var current = true;
                var calls = 0;
                var broker = new StorageMigrationSelection(bootstrap, () => source,
                    _ => Task.FromResult<string?>(mode == "cancel-picker" ? null : mode == "same" ? source : target),
                    (from, to, _) => {
                        calls++;
                        if (from != source || to != target) throw new Exception("Unselected path handed off.");
                        if (mode == "handoff-failure") throw new IOException("fixture failure");
                        return Task.CompletedTask;
                    });
                var choice = await broker.ChooseAsync(() => current, default);
                if (Directory.Exists(target) || StorageRootLocator.Read(bootstrap) != source || calls != 0)
                    throw new Exception("Selection mutated storage.");
                if (mode is "cancel-picker" or "same")
                { if (choice is not null) throw new Exception("No-op selection created ticket."); continue; }
                if (choice is null) throw new Exception("Missing choice.");
                if (mode == "stale") current = false;
                if (mode == "pointer") File.WriteAllText(locator, bootstrap);
                if (mode == "occupied") { Directory.CreateDirectory(target); File.WriteAllText(Path.Combine(target, "keep"), "keep"); }
                if (mode == "superseded") await broker.ChooseAsync(() => current, default);
                using var cancellation = new CancellationTokenSource();
                if (mode == "cancel-confirm") cancellation.Cancel();
                if (mode == "success") await broker.ConfirmAsync(choice.Ticket, () => true, default);
                else await Refused(() => broker.ConfirmAsync(choice.Ticket, () => true, cancellation.Token));
                if (calls != (mode is "success" or "handoff-failure" ? 1 : 0)) throw new Exception("Unexpected handoff.");
                if (mode is "success" or "handoff-failure")
                    await Refused(() => broker.ConfirmAsync(choice.Ticket, () => true, default));
                if (mode == "pointer") File.WriteAllText(locator, source);
                if (mode == "occupied") { File.Delete(Path.Combine(target, "keep")); Directory.Delete(target); }
            }
            var completion = new TaskCompletionSource<string?>(TaskCreationOptions.RunContinuationsAsynchronously);
            var concurrent = new StorageMigrationSelection(bootstrap, () => source, _ => completion.Task,
                (_, _, _) => throw new Exception("No confirmation expected."));
            var pending = concurrent.ChooseAsync(() => true, default);
            await Refused(() => concurrent.ChooseAsync(() => true, default));
            completion.SetResult(target);
            await pending;
            await VerifyBridge(bootstrap, source, target);
        }
        finally { Directory.Delete(fixture, recursive: true); } // Only the newly-created isolated fixture.
    }

    private static async Task VerifyBridge(string bootstrap, string source, string target)
    {
        long generation = 4;
        var handoffs = 0;
        using var dispatcher = new StorageMigrationBridgeDispatcher(new StorageMigrationSelection(bootstrap,
            () => source, _ => Task.FromResult<string?>(target), (_, _, _) => { handoffs++; return Task.CompletedTask; }), () => generation);
        var choose = StarBridge.NativeBridge.BridgeEnvelope.Request(StorageMigrationBridgeDispatcher.ChooseRequest,
            Guid.NewGuid().ToString("N"), generation, new { schemaVersion = 1 });
        using var composite = new StarBridge.HostRuntime.CompositeBridgeDispatcher(new Reject(), new Reject(), new Reject(), storageMigration: dispatcher);
        foreach (var payload in new object[] { new { schemaVersion = 2 }, new { schemaVersion = "1" }, new { schemaVersion = 1, destination = target } })
        {
            var request = choose with { Payload = StarBridge.NativeBridge.BridgePayload.From(payload) };
            if ((await composite.DispatchAsync(request)).Response.Status != "error") throw new Exception("Unsafe migration payload accepted.");
        }
        if ((await composite.DispatchAsync(choose with { AccountContext = new("test", "test", "test") })).Response.Status != "error")
            throw new Exception("Unexpected account context accepted.");
        var result = (await composite.DispatchAsync(choose)).Response;
        if (result.Status != "ok" || result.Payload.GetProperty("destination").GetString() != target) throw new Exception("Choice route failed.");
        var confirm = StarBridge.NativeBridge.BridgeEnvelope.Request(StorageMigrationBridgeDispatcher.ConfirmRequest,
            Guid.NewGuid().ToString("N"), generation, new { schemaVersion = 1, ticket = result.Payload.GetProperty("ticket").GetString() });
        if ((await composite.DispatchAsync(confirm)).Response.Status != "ok" || handoffs != 1) throw new Exception("Confirmation route failed.");
        if ((await composite.DispatchAsync(confirm)).Response.Status != "error" || handoffs != 1) throw new Exception("Confirmation replayed.");
        generation++;
        if ((await composite.DispatchAsync(choose)).Response.Status != "error") throw new Exception("Stale request accepted.");
        generation--;
        if ((await composite.DispatchAsync(choose, new CancellationToken(true))).Response.Status != "cancelled") throw new Exception("Cancellation ignored.");
        dispatcher.Dispose();
        if ((await composite.DispatchAsync(choose)).Response.Status != "error") throw new Exception("Disposed request accepted.");
        using var blocked = new StorageMigrationBridgeDispatcher(new StorageMigrationSelection(bootstrap,
            () => source, _ => Task.FromResult<string?>(target),
            (_, _, _) => throw new StorageMigrationWpfRunningException()), () => generation);
        var blockedChoice = (await blocked.DispatchAsync(choose)).Response;
        var blockedConfirm = confirm with { Payload = StarBridge.NativeBridge.BridgePayload.From(new {
            schemaVersion = 1, ticket = blockedChoice.Payload.GetProperty("ticket").GetString() }) };
        if ((await blocked.DispatchAsync(blockedConfirm)).Response.Error?.Code != "dataLocation.wpf_running")
            throw new Exception("WPF occupancy lost its actionable error code.");
    }

    private sealed class Reject : StarBridge.HostRuntime.IBridgeRequestDispatcher
    {
        public event Action<StarBridge.NativeBridge.BridgeEnvelope>? EventReady { add { } remove { } }
        public ValueTask<StarBridge.HostRuntime.BridgeDispatchBatch> DispatchAsync(StarBridge.NativeBridge.BridgeEnvelope request, CancellationToken cancellationToken = default)
            => throw new Exception("Incorrect migration route.");
        public void Dispose() { }
    }

    private static async Task Refused(Func<Task> action)
    {
        try { await action(); }
        catch (Exception error) when (error is InvalidOperationException or IOException or OperationCanceledException) { return; }
        throw new Exception("Unsafe confirmation accepted.");
    }
}
