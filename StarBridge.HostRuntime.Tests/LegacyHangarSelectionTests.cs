using StarBridge.Core.Hangar;
using StarBridge.HostRuntime.Hangar;
using StarBridge.NativeBridge;

internal static class LegacyHangarSelectionTests
{
    internal static async Task Verify()
    {
        var directory = Path.Combine(Path.GetTempPath(), "starbridge-selection-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(directory);
        var file = Path.Combine(directory, "synthetic.database");
        var picker = new Picker { Path = file };
        var clock = new Clock();
        var owner = (Owner: (MigrationOwner?)new MigrationOwner("test", "relay", "synthetic"), Generation: 1L);
        var leased = true;
        using var selection = new LegacyHangarSelection(picker, () => owner, () => leased, clock);
        try
        {
            var selected = await selection.SelectAsync("en", default);
            Check(selected.State == "selected" && selected.FileName == "synthetic.database", "picker selection before file exists");
            Reject(() => selection.Read(selected.SelectionRef!), "no read before confirmation");
            Reject(() => selection.Confirm(selected.SelectionRef!, false), "ownership required");
            var date = DateTimeOffset.UnixEpoch.ToString("O");
            var row = $"same\tSame ship\tsource\t{date}\t{date}\t\tid-1\t\t0.5\t0.5\t1";
            var original = row + "\n" + row.Replace("id-1", "id-2");
            File.WriteAllText(file, original);
            var read = selection.Confirm(selected.SelectionRef!, true);
            Check(read.State == "read" && read.Snapshot!.Rows.Count == 2, "same-model instances retained");
            Check(File.ReadAllText(file) == original, "no writes");
            File.WriteAllText(file, "changed");
            Check(selection.Read(selected.SelectionRef!) == read, "snapshot does not silently reread");
            clock.Now += TimeSpan.FromMinutes(6);
            Reject(() => selection.Read(selected.SelectionRef!), "expired selection rejected");
            selected = await selection.SelectAsync("en", default);
            owner = (owner.Owner! with { Subject = "other" }, 2);
            Reject(() => selection.Confirm(selected.SelectionRef!, true), "account change rejected");
            leased = false;
            await RejectAsync(() => selection.SelectAsync("en", default), "lease required");
            leased = true;
            picker.Pending = new();
            var pending = selection.SelectAsync("en", default);
            selection.Invalidate();
            picker.Pending.SetResult(file);
            await RejectAsync(() => pending, "late picker rejected");
            picker.Pending = null;
            File.WriteAllText(file, string.Concat(Enumerable.Repeat("bad\n", 10001)));
            selected = await selection.SelectAsync("en", default);
            Check(selection.Confirm(selected.SelectionRef!, true).State == "needs-review", "row limit is not empty or crash");

            var context = new BridgeAccountContext("test", "relay", "synthetic");
            var serverOwner = new MigrationOwner(context.Environment, context.Authority, context.Subject);
            var remoteSource = LegacyHangarMigrationReader.Read(System.Text.Encoding.UTF8.GetBytes(original), serverOwner).Source;
            var remoteHash = new string('A', 64);
            TaskCompletionSource<ServerHangarMigrationRead>? pendingServer = null;
            using var bridge = new LegacyHangarSelectionBridge(picker, () => (context, 3), () => true,
                (_, _) => pendingServer?.Task ?? Task.FromResult(new ServerHangarMigrationRead("available", remoteHash,
                    remoteSource with { State = MigrationSourceState.Partial })));
            async Task<BridgeEnvelope> Send(string name, object payload) =>
                (await bridge.DispatchAsync(BridgeEnvelope.Request(name, Guid.NewGuid().ToString("N"), 3, payload, context), default)).Response;
            var badPath = await Send("hangar.migrationSelectLocal", new { schemaVersion = 1, locale = "en", path = file });
            Check(badPath.Error is not null, "Bridge cannot supply path");
            File.WriteAllText(file, original);
            var pick = await Send("hangar.migrationSelectLocal", new { schemaVersion = 1, locale = "en" });
            Check(!pick.Payload.GetRawText().Contains(directory), "full path not exposed");
            var reference = pick.Payload.GetProperty("selectionRef").GetString();
            var premature = await Send("hangar.migrationReadLocal", new { schemaVersion = 1, selectionRef = reference, offset = 0 });
            Check(premature.Error is not null, "Bridge confirmation enforced");
            var confirmed = await Send("hangar.migrationConfirmLocal", new { schemaVersion = 1, selectionRef = reference, belongsToCurrentAccount = true });
            Check(confirmed.Payload.GetProperty("rows").GetArrayLength() == 2 &&
                confirmed.Payload.GetProperty("ownership").GetString() == "user-confirmed", "declaration not authenticated ownership");
            var localHash = confirmed.Payload.GetProperty("snapshotSha256").GetString();
            object ComparePayload(string? hash = null) => new { schemaVersion = 1, selectionRef = reference,
                localSha256 = localHash, serverSha256 = hash ?? remoteHash, offset = 0 };
            var compared = await Send("hangar.migrationCompare", ComparePayload());
            Check(compared.Error is null && compared.Payload.GetProperty("rows").GetArrayLength() == 2 &&
                !compared.Payload.GetProperty("bothSourcesComplete").GetBoolean(), "comparison preserves unknown coverage");
            Check(compared.Payload.GetProperty("rows")[0].GetProperty("state").GetString() == "SharedFieldsMatch", "exact instance match");
            Check((await Send("hangar.migrationCompare", ComparePayload(new string('B', 64)))).Error is not null,
                "changed server snapshot rejected");
            pendingServer = new();
            var pendingComparison = Send("hangar.migrationCompare", ComparePayload());
            await Send("hangar.migrationClearLocal", new { schemaVersion = 1, selectionRef = reference });
            pendingServer.SetResult(new("available", remoteHash, remoteSource));
            Check((await pendingComparison).Error is not null, "cleared selection rejects late comparison");
            pendingServer = null;
            pick = await Send("hangar.migrationSelectLocal", new { schemaVersion = 1, locale = "en" });
            reference = pick.Payload.GetProperty("selectionRef").GetString();
            await Send("hangar.migrationConfirmLocal", new { schemaVersion = 1, selectionRef = reference, belongsToCurrentAccount = true });
            await Send("hangar.migrationClearLocal", new { schemaVersion = 1, selectionRef = "unrelated" });
            Check((await Send("hangar.migrationReadLocal", new { schemaVersion = 1, selectionRef = reference, offset = 0 })).Error is null, "old clear cannot cancel newer selection");
            await Send("hangar.migrationClearLocal", new { schemaVersion = 1, selectionRef = reference });
            Check((await Send("hangar.migrationReadLocal", new { schemaVersion = 1, selectionRef = reference, offset = 0 })).Error is not null, "cleared selection rejected");
            Check(File.ReadAllText(file) == original, "Bridge never changes source");
        }
        finally { Directory.Delete(directory, true); }
        Console.WriteLine("PASS explicit local hangar selection, owner consent, expiry, immutable preview and Bridge path isolation");
    }
    private static void Check(bool value, string message) { if (!value) throw new Exception(message); }
    private static void Reject(Action action, string message)
    { try { action(); } catch (InvalidOperationException) { return; } throw new Exception(message); }
    private static async Task RejectAsync(Func<Task> action, string message)
    { try { await action(); } catch (Exception e) when (e is InvalidOperationException or OperationCanceledException) { return; } throw new Exception(message); }
    private sealed class Picker : ILegacyHangarFilePicker
    {
        internal string? Path;
        internal TaskCompletionSource<string?>? Pending;
        public Task<string?> PickAsync(string locale, CancellationToken token) => Pending?.Task ?? Task.FromResult(Path);
    }
    private sealed class Clock : TimeProvider
    {
        internal DateTimeOffset Now = DateTimeOffset.UnixEpoch;
        public override DateTimeOffset GetUtcNow() => Now;
    }
}
