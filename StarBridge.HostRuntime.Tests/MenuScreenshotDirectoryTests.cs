using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Settings;
using StarBridge.NativeBridge;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

internal static class MenuScreenshotDirectoryTests
{
    private static int _checks;
    internal static async Task Verify()
    {
        _checks = 0;
        Store();
        await Dispatch();
        await StagedSelection();
        Console.WriteLine($"PASS screenshot directory: {_checks} assertions; native-only selection, encrypted persistence, CAS, cancellation and exact routing");
    }

    private static async Task StagedSelection()
    {
        var root = Directory.CreateTempSubdirectory("starbridge-screenshot-draft-").FullName;
        long generation = 1;
        var chosen = Path.Combine(root, "synthetic-selected");
        using var dispatcher = new MenuScreenshotDirectoryBridgeDispatcher(root, () => generation,
            _ => Task.FromResult<string?>(chosen), () => Path.Combine(root, "synthetic-default"), (_, _) => { });
        async Task<BridgeEnvelope> Send(string action, object payload) => (await dispatcher.DispatchAsync(
            BridgeEnvelope.Request("menuScreenshotDirectory." + action, Guid.NewGuid().ToString("N"), generation, payload))).Response;
        try
        {
            var draft = await Send("chooseDraft", new { schemaVersion = 1, expectedRevision = 0 });
            Require(draft.Status == "ok", "draft folder picker is supported");
            var token = draft.Payload.GetProperty("token").GetString();
            Require(token?.Length == 32 && draft.Payload.GetProperty("directory").GetString() == chosen, "draft returns opaque selection and display path");
            Require(new MenuScreenshotDirectoryStore(root).Read().Revision == 0 && Directory.GetFileSystemEntries(root).Length == 0,
                "selecting folder does not save or create files before shared Save");
            var bad = await Send("commitDraft", new { schemaVersion = 1, expectedRevision = 0, token, directory = chosen });
            Require(bad.Error?.Code == "menuScreenshotDirectory.invalid_value", "renderer path injection rejected");
            var saved = await Send("commitDraft", new { schemaVersion = 1, expectedRevision = 0, token });
            Require(saved.Status == "ok" && saved.Payload.GetProperty("revision").GetInt64() == 1, "shared Save commits native selection");
            Require((await Send("commitDraft", new { schemaVersion = 1, expectedRevision = 1, token })).Error?.Code == "menuScreenshotDirectory.selection_unavailable", "selection token consumed once");
            draft = await Send("chooseDraft", new { schemaVersion = 1, expectedRevision = 1 });
            token = draft.Payload.GetProperty("token").GetString();
            generation++;
            Require((await Send("commitDraft", new { schemaVersion = 1, expectedRevision = 1, token })).Error?.Code == "menuScreenshotDirectory.selection_unavailable", "selection token cannot cross account generation");
            Require(new MenuScreenshotDirectoryStore(root).Read().Revision == 1, "stale selection leaves committed directory unchanged");
            draft = await Send("chooseDraft", new { schemaVersion = 1, expectedRevision = 1 });
            token = draft.Payload.GetProperty("token").GetString();
            new MenuScreenshotDirectoryStore(root).Save(1, null, () => true);
            Require((await Send("commitDraft", new { schemaVersion = 1, expectedRevision = 1, token })).Error?.Code == "menuScreenshotDirectory.revision_conflict", "external directory change cannot be overwritten by selected draft");
            Require(new MenuScreenshotDirectoryStore(root).Read().Directory == null, "failed selection commit preserves external destination");
        }
        finally { Directory.Delete(root, true); }
    }

    private static void Store()
    {
        var root = Directory.CreateTempSubdirectory("starbridge-screenshot-directory-").FullName;
        var path = Path.Combine(root, "menu-screenshot-directory-v1", "settings.bin");
        var first = Path.Combine(root, "synthetic-截图");
        var second = Path.Combine(root, "synthetic-second");
        var store = new MenuScreenshotDirectoryStore(root);
        try
        {
            Require(store.Read() == new MenuScreenshotDirectoryStore.Snapshot(), "absent preference is default");
            Require(!Directory.Exists(Path.GetDirectoryName(path)), "read creates no settings or screenshot directory");
            store.Save(0, first, () => true);
            Require(new MenuScreenshotDirectoryStore(root).Read() == new MenuScreenshotDirectoryStore.Snapshot(1, first), "selection survives restart");
            Require(!Directory.Exists(first), "choosing only a destination never creates it or saves an image");
            var committed = File.ReadAllBytes(path);
            Require(!Encoding.UTF8.GetString(committed).Contains(first), "selected path is not plaintext on disk");
            Require(store.Save(1, first, () => true).Revision == 1 && File.ReadAllBytes(path).SequenceEqual(committed), "same selection is a no-op");
            foreach (var bad in new[] { "", "relative", @"C:relative", @"\\?\C:\synthetic", @"\\.\pipe\synthetic",
                first + "\n", first + " ", Path.Combine(root, "a", "..", "b"), new string('x', 32768) })
                Reject(() => store.Save(1, bad, () => true), "unsafe or non-canonical directory rejected");
            Require(MenuScreenshotDirectoryStore.ValidDirectory(@"\\server.invalid\synthetic-share\screenshots"), "canonical UNC selection is supported, not probed on read");
            Reject(() => store.Save(0, second, () => true), "stale revision rejected");
            Reject(() => store.Save(long.MaxValue, second, () => true), "revision cannot overflow");
            int checks = 0;
            Reject(() => store.Save(1, second, () => ++checks == 1), "generation change during file write prevents commit");
            Require(checks == 2 && File.ReadAllBytes(path).SequenceEqual(committed), "stale write preserves committed ciphertext");
            Require(Directory.GetFiles(Path.GetDirectoryName(path)!, "*.tmp").Length == 0, "stale write leaves no temporary file");
            using (var locked = new FileStream(path + ".lock", FileMode.OpenOrCreate, FileAccess.Write, FileShare.None))
                Reject(() => store.Save(1, second, () => true), "another process owns the write lock");
            Require(File.ReadAllBytes(path).SequenceEqual(committed), "invalid and failed writes preserve settings bytes");
            Require(store.Save(1, null, () => true) == new MenuScreenshotDirectoryStore.Snapshot(2), "explicit reset persists default without a path");
            Require(new MenuScreenshotDirectoryStore(root).Read() == new MenuScreenshotDirectoryStore.Snapshot(2), "reset survives restart");
            Require(!Directory.Exists(first) && !Directory.Exists(second), "reset does not migrate or delete screenshot directories");

            foreach (var bad in new[] { "{}", "{\"version\":2,\"value\":{\"revision\":2,\"directory\":null}}",
                "{\"version\":1,\"value\":{\"revision\":-1,\"directory\":null}}",
                "{\"version\":1,\"value\":{\"revision\":2}}",
                "{\"version\":1,\"value\":{\"revision\":2,\"directory\":null,\"account\":\"forbidden\"}}",
                "{\"version\":1,\"value\":{\"revision\":2,\"directory\":null,\"directory\":null}}",
                "{\"version\":1,\"value\":{\"revision\":2,\"directory\":\"relative\"}}" })
            {
                var encrypted = ProtectedData.Protect(Encoding.UTF8.GetBytes(bad),
                    Encoding.UTF8.GetBytes("StarBridge.menu-screenshot-directory.v1"), DataProtectionScope.CurrentUser);
                File.WriteAllBytes(path, encrypted);
                Reject(() => store.Read(), "unknown, malformed or duplicate stored document is unavailable");
                Reject(() => store.Save(2, first, () => true), "corrupt document cannot be silently overwritten");
                Require(File.ReadAllBytes(path).SequenceEqual(encrypted), "corruption retained for explicit recovery");
            }
            File.WriteAllBytes(path, [1, 2, 3]);
            Reject(() => store.Read(), "invalid DPAPI document fails closed");
            File.Delete(path);
            Directory.CreateDirectory(path);
            Reject(() => store.Read(), "directory in place of settings is failure, not missing/default");
            Reject(() => store.Save(0, first, () => true), "invalid storage type cannot be overwritten");
        }
        finally { Directory.Delete(root, true); }
    }

    private static async Task Dispatch()
    {
        var root = Directory.CreateTempSubdirectory("starbridge-screenshot-directory-bridge-").FullName;
        long generation = 1;
        int pickerCalls = 0, openCalls = 0;
        bool failOpen = false;
        string? opened = null;
        var defaultPath = Path.Combine(root, "synthetic-default");
        var chosenPath = Path.Combine(root, "synthetic-selected");
        Func<CancellationToken, Task<string?>> picker = _ => Task.FromResult<string?>(null);
        using var directory = new MenuScreenshotDirectoryBridgeDispatcher(root, () => generation,
            token => { pickerCalls++; return picker(token); }, () => defaultPath,
            (path, current) => { Require(current(), "opening checks current lease"); if (failOpen) throw new IOException("synthetic open failure"); openCalls++; opened = path; });
        try
        {
            async Task<BridgeEnvelope> Send(string action, object payload, long? revisionGeneration = null,
                CancellationToken token = default) => (await directory.DispatchAsync(BridgeEnvelope.Request(
                    "menuScreenshotDirectory." + action, Guid.NewGuid().ToString("N"), revisionGeneration ?? generation, payload), token)).Response;
            var initial = await Send("read", new { schemaVersion = 1 });
            Require(initial.Status == "ok" && initial.AccountContext is null && initial.Payload.GetProperty("directory").GetString() == defaultPath &&
                initial.Payload.GetProperty("isDefault").GetBoolean(), "device-local read returns only the committed default destination");
            Require(Directory.GetFileSystemEntries(root).Length == 0 && pickerCalls == 0 && openCalls == 0, "read has no native UI, file or capture side effects");
            var cancelled = await Send("choose", new { schemaVersion = 1, expectedRevision = 0 });
            Require(cancelled.Status == "ok" && cancelled.Payload.GetProperty("cancelled").GetBoolean() &&
                cancelled.Payload.GetProperty("revision").GetInt64() == 0 && Directory.GetFileSystemEntries(root).Length == 0, "cancelled selection preserves absent default");
            var menu = new MenuPreferencesStore(root);
            var menuBefore = menu.Read();
            menu.Save(0, menuBefore.Layout, menuBefore.Settings);
            menuBefore = menu.Read();
            picker = _ => Task.FromResult<string?>(chosenPath);
            var chosen = await Send("choose", new { schemaVersion = 1, expectedRevision = 0 });
            Require(chosen.Status == "ok" && chosen.Payload.GetProperty("directory").GetString() == chosenPath &&
                !chosen.Payload.GetProperty("isDefault").GetBoolean(), "only native chooser supplies the committed custom destination");
            var file = Path.Combine(root, "menu-screenshot-directory-v1", "settings.bin");
            var bytes = File.ReadAllBytes(file);
            var callsBeforeInvalid = pickerCalls;
            foreach (var payload in new object[] { new { schemaVersion = 2, expectedRevision = 1 },
                new { schemaVersion = 1, expectedRevision = 1, directory = chosenPath },
                new { schemaVersion = 1, expectedRevision = 1, owner = "forbidden" },
                new { schemaVersion = 1, expectedRevision = 1, bytes = new[] { 1 } },
                new { schemaVersion = 1, expectedRevision = 1.5 }, new { schemaVersion = 1 },
                JsonSerializer.Deserialize<JsonElement>("{\"schemaVersion\":1,\"expectedRevision\":1,\"expectedRevision\":1}") })
                Require((await Send("choose", payload)).Error?.Code == "menuScreenshotDirectory.invalid_value", "strict payload cannot inject paths, bytes, owners or duplicate fields");
            Require(pickerCalls == callsBeforeInvalid && File.ReadAllBytes(file).SequenceEqual(bytes), "invalid request never starts picker or writes storage");
            var opening = await Send("open", new { schemaVersion = 1, expectedRevision = 1 });
            Require(opening.Status == "ok" && opening.Payload.GetProperty("opened").GetBoolean() && openCalls == 1 && opened == chosenPath, "explicit open uses the committed destination");
            Require((await Send("open", new { schemaVersion = 1, expectedRevision = 0 })).Error?.Code == "menuScreenshotDirectory.revision_conflict" && openCalls == 1, "stale view cannot open a different destination");
            failOpen = true;
            var failedOpen = await Send("open", new { schemaVersion = 1, expectedRevision = 1 });
            Require(failedOpen.Error?.Code == "menuScreenshotDirectory.unavailable" && failedOpen.Payload.GetRawText() == "{}" &&
                File.ReadAllBytes(file).SequenceEqual(bytes), "failed open does not report success, disclose a path or change settings");
            failOpen = false;
            Require((await Send("choose", new { schemaVersion = 1, expectedRevision = 1 }, 0)).Error?.Code == BridgeErrorCodes.StaleGeneration && pickerCalls == callsBeforeInvalid, "stale generation never starts native picker");
            picker = _ => throw new IOException("synthetic picker failure");
            Require((await Send("choose", new { schemaVersion = 1, expectedRevision = 1 })).Error?.Code == "menuScreenshotDirectory.unavailable" &&
                File.ReadAllBytes(file).SequenceEqual(bytes), "picker failure preserves committed destination");
            picker = _ => Task.FromResult<string?>("relative");
            Require((await Send("choose", new { schemaVersion = 1, expectedRevision = 1 })).Error?.Code == "menuScreenshotDirectory.invalid_value" &&
                File.ReadAllBytes(file).SequenceEqual(bytes), "invalid native selection is not persisted or used as fallback");

            var pending = new TaskCompletionSource<string?>(TaskCreationOptions.RunContinuationsAsynchronously);
            picker = _ => pending.Task;
            var late = Send("choose", new { schemaVersion = 1, expectedRevision = 1 });
            generation++; pending.SetResult(defaultPath);
            Require((await late).Error?.Code == BridgeErrorCodes.StaleGeneration && File.ReadAllBytes(file).SequenceEqual(bytes), "account transition drops late picker path without committing");
            pending = new(TaskCreationOptions.RunContinuationsAsynchronously);
            using var cancel = new CancellationTokenSource();
            var interrupted = Send("choose", new { schemaVersion = 1, expectedRevision = 1 }, token: cancel.Token);
            cancel.Cancel(); pending.SetResult(defaultPath);
            Require((await interrupted).Status == "cancelled" && File.ReadAllBytes(file).SequenceEqual(bytes), "cancelled native picker cannot commit or leak a destination reply");

            picker = _ => { new MenuScreenshotDirectoryStore(root).Save(1, defaultPath, () => true); return Task.FromResult<string?>(chosenPath); };
            Require((await Send("choose", new { schemaVersion = 1, expectedRevision = 1 })).Error?.Code == "menuScreenshotDirectory.revision_conflict", "another process changing preference during picker wins CAS");
            Require(new MenuScreenshotDirectoryStore(root).Read().Directory == defaultPath, "late picker cannot overwrite another process choice");
            Require((await Send("reset", new { schemaVersion = 1, expectedRevision = 2 })).Status == "ok" &&
                new MenuScreenshotDirectoryStore(root).Read() == new MenuScreenshotDirectoryStore.Snapshot(3), "explicit reset restores default");
            Require(menu.Read().Revision == menuBefore.Revision && menu.Read().Layout.GetRawText() == menuBefore.Layout.GetRawText() &&
                menu.Read().Settings.GetRawText() == menuBefore.Settings.GetRawText(), "directory actions cannot rewrite shareable menu layout or scalar settings");

            var spoof = BridgeEnvelope.Request("menuScreenshotDirectory.read", Guid.NewGuid().ToString("N"), generation,
                new { schemaVersion = 1 }, new BridgeAccountContext("synthetic", "synthetic", "synthetic"));
            Require((await directory.DispatchAsync(spoof)).Response.Status == "error", "renderer cannot attach account context");
            using var inert = new Inert();
            using var composed = new CompositeBridgeDispatcher(inert, inert, inert, menuScreenshotDirectory: directory);
            var request = spoof with { AccountContext = null };
            Require((await composed.DispatchAsync(request)).Response.Status == "ok", "production composite routes exact capability to the directory owner");
            Require((await composed.DispatchAsync(request with { Name = "menuScreenshotDirectory.unknown" })).Response.Error?.Code == BridgeErrorCodes.CapabilityUnavailable, "unknown action cannot reach directory owner");
            foreach (var capability in MenuScreenshotDirectoryBridgeDispatcher.Capabilities)
                Require(!BridgeRequestPolicy.RequiresAccountContext(capability), "directory is machine-local, not an account or sharing capability");
            using var alreadyCancelled = new CancellationTokenSource(); alreadyCancelled.Cancel();
            Require((await Send("read", new { schemaVersion = 1 }, token: alreadyCancelled.Token)).Status == "cancelled", "pre-cancelled read discloses no path");
            pending = new(TaskCreationOptions.RunContinuationsAsynchronously);
            picker = _ => pending.Task;
            bytes = File.ReadAllBytes(file);
            var disposedPending = Send("choose", new { schemaVersion = 1, expectedRevision = 3 });
            using var queuedCancel = new CancellationTokenSource();
            var queuedRead = Send("read", new { schemaVersion = 1 }, token: queuedCancel.Token);
            queuedCancel.Cancel();
            Require((await queuedRead).Status == "cancelled", "queued read cancels without waiting for a native picker");
            directory.Dispose();
            pending.SetResult(chosenPath);
            Require((await disposedPending).Error?.Code == BridgeErrorCodes.StaleGeneration && File.ReadAllBytes(file).SequenceEqual(bytes), "disposed pending picker cannot commit or return a directory");
            Require((await Send("read", new { schemaVersion = 1 })).Status == "error", "disposed owner cannot return path");
        }
        finally { Directory.Delete(root, true); }
    }

    private static void Reject(Action action, string name)
    { try { action(); } catch (Exception) { _checks++; return; } throw new Exception(name); }
    private static void Require(bool value, string name) { if (!value) throw new Exception(name); _checks++; }
    private sealed class Inert : IBridgeRequestDispatcher
    {
        public event Action<BridgeEnvelope>? EventReady { add { } remove { } }
        public ValueTask<BridgeDispatchBatch> DispatchAsync(BridgeEnvelope request, CancellationToken cancellationToken = default) => throw new Exception("wrong directory owner");
        public void Dispose() { }
    }
}
