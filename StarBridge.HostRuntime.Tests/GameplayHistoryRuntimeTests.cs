using StarBridge.HostRuntime.Presence;
using StarBridge.NativeBridge;
using System.Text.Json;

internal static class GameplayHistoryRuntimeTests
{
    private sealed class ResetRemote : IGameplayHistoryRemote
    {
        internal int Writes;
        internal bool LoseReply;
        internal bool ReadFails;
        internal bool DropWrite;
        internal Action? AfterWrite;
        public Task<bool> PublishGameplayStatisticsAsync(BridgeAccountContext owner,
            StarBridge.Core.Profiles.PersonalProfileGameplayStatisticsUpdateRequestContract update, CancellationToken token)
        {
            Writes++;
            if (DropWrite) throw new IOException("isolated request never reached server");
            if (State.Revision != update.ExpectedGameplayRevision) return Task.FromResult(false);
            State = State with { Revision = State.Revision + 1, PlayTimeSeconds = update.PlayTimeSeconds,
                HistoricalPlayTimeSeconds = update.HistoricalPlayTimeSeconds, HistoryImportedAt = update.HistoryImportedAt,
                HistoryImportOperationId = update.HistoryImportOperationId, IsPublic = update.IsPublic,
                HistoricalSessionCount = update.HistoricalSessionCount,
                HistoricalIncompleteSessionCount = update.HistoricalIncompleteSessionCount };
            AfterWrite?.Invoke();
            if (LoseReply) throw new IOException("isolated lost import reply");
            return Task.FromResult(true);
        }
        internal StarBridge.Core.Profiles.GameplayTimeResetState State = new(1, 4, null, null, 3600, 3600, DateTimeOffset.UtcNow);
        public Task<StarBridge.Core.Profiles.GameplayTimeResetState> ReadAsync(BridgeAccountContext owner, CancellationToken token) =>
            ReadFails ? throw new IOException("isolated transport") : Task.FromResult(State);
        public Task<StarBridge.Core.Profiles.GameplayTimeResetResult> ResetAsync(BridgeAccountContext owner,
            StarBridge.Core.Profiles.GameplayTimeResetRequest request, CancellationToken token)
        {
            Writes++;
            if (DropWrite) throw new IOException("isolated reset never reached server");
            if (request.ExpectedRevision != State.Revision)
                return Task.FromResult(new StarBridge.Core.Profiles.GameplayTimeResetResult("conflict", State));
            State = new(1, State.Revision + 1, request.OperationId, request.ExpectedRevision, 0, 0, null);
            AfterWrite?.Invoke();
            if (LoseReply) throw new IOException("isolated lost response");
            return Task.FromResult(new StarBridge.Core.Profiles.GameplayTimeResetResult("completed", State));
        }
    }

    internal static async Task ResetRecovery()
    {
        using (var imported = new Harness())
        {
            var importRemote = new ResetRemote { State = new(1, 0, null, null, 0, 0, null), LoseReply = true };
            imported.Remote = importRemote;
            imported.Reopen();
            var importPreview = await imported.Preview();
            importRemote.AfterWrite = () => importRemote.ReadFails = true;
            await imported.Confirm(importPreview.GetProperty("previewId").GetString()!);
            Require(imported.Read().GetProperty("seconds").GetInt64() == 0, "Lost response cannot prematurely count import.");
            imported.Reopen();
            importRemote.ReadFails = false;
            await imported.Runtime.RecoverHistoryImportAsync();
            Require(imported.Read().GetProperty("seconds").GetInt64() == 3600, "Read-only receipt recovery completes import after restart.");
            await imported.Runtime.RecoverHistoryImportAsync();
            Require(importRemote.Writes == 1 && imported.Read().GetProperty("seconds").GetInt64() == 3600,
                "Recovery never uploads or counts import twice.");
            importRemote.AfterWrite = null;
            importRemote.LoseReply = false;
            imported.Runtime.Dispatch(imported.Request("setVisibility", new { schemaVersion = 1, showOnProfile = false }));
            await imported.Runtime.PublishCurrentGameplayAsync();
            var count = importRemote.Writes;
            await imported.Runtime.PublishCurrentGameplayAsync();
            Require(!importRemote.State.IsPublic && importRemote.State.PlayTimeSeconds == 3600 &&
                count == 2 && importRemote.Writes == count, "Background publication preserves history and suppresses unchanged writes.");
        }
        using (var missing = new Harness())
        {
            var remoteMissing = new ResetRemote { State = new(1, 0, null, null, 0, 0, null), DropWrite = true };
            missing.Remote = remoteMissing;
            missing.Reopen();
            var ticket = await missing.Preview();
            await missing.Confirm(ticket.GetProperty("previewId").GetString()!);
            Require(State(await missing.Preview()) == "busy", "Unknown delivery remains pending before deadline.");
            remoteMissing.State = remoteMissing.State with { ObservedAt = DateTimeOffset.UtcNow.AddMinutes(3) };
            await missing.Runtime.RecoverHistoryImportAsync();
            Require(State(await missing.Preview()) == "preview" && remoteMissing.Writes == 1,
                "Server deadline releases unexecuted import without another upload.");
            Require(await missing.Runtime.ResetAsync(Owner, 1, 0, remoteMissing) == "conflict",
                "Server deadline releases unexecuted reset without clearing time.");
        }
        using var h = new Harness();
        var journalOwner = Owner with { Subject = "synthetic-import-journal" };
        var store = new GameplayTimeStore(h.Root);
        var pendingImport = new GameplayPendingImport(new(false, 120, 0, 0, 100,
            HistoryImportedAt: DateTimeOffset.UtcNow, ExpectedGameplayRevision: 0,
            HistoryImportOperationId: Guid.NewGuid().ToString("N")));
        using (var lease = store.Open(journalOwner))
        {
            var saved = lease.Save(lease.Read(), GameplayRecordingConsent.Allowed, 20, () => true);
            saved = lease.BeginImport(saved, pendingImport, () => true);
            Require(saved.Seconds == 20 && saved.HistoryImportedAt is null, "Journal does not prematurely count imported time.");
        }
        using (var lease = store.Open(journalOwner))
        {
            var saved = lease.Read();
            Require(saved.PendingImport == pendingImport, "Pending import survives restart.");
            try { lease.FinishImport(saved, pendingImport, true, () => false); throw new Exception("Expected changed owner"); }
            catch (GameplayTimeException) { }
            Require(lease.Read() == saved, "Rejected local completion preserves recovery journal.");
            saved = lease.FinishImport(saved, pendingImport, true, () => true);
            Require(saved.Seconds == 120 && saved.HistoryConsumed == true && saved.PendingImport is null &&
                saved.Consent == GameplayRecordingConsent.Allowed, "Confirmed import commits total and marker atomically.");
            try { lease.FinishImport(saved, pendingImport, true, () => true); throw new Exception("Expected duplicate rejection"); }
            catch (GameplayTimeException) { }
            Require(lease.Read() == saved, "Duplicate completion cannot count twice.");
        }
        var preview = await h.Preview();
        await h.Confirm(preview.GetProperty("previewId").GetString()!);
        h.Runtime.Dispatch(h.Request("setVisibility", new { schemaVersion = 1, showOnProfile = false }));
        var remote = new ResetRemote { LoseReply = true, ReadFails = true };
        Require(await h.Runtime.ResetAsync(Owner, 1, 4, remote) == "pending", "Unknown reset stays pending.");
        Require(h.Read().GetProperty("seconds").GetInt64() == 3600, "Unknown reset preserves local total.");
        Require(State(await h.Preview()) == "busy", "Pending reset blocks import.");
        h.Reopen();
        remote.ReadFails = false;
        await h.Runtime.RecoverResetAsync(remote);
        Require(await h.Runtime.ResetAsync(Owner, 1, null, remote) == "idle", "Background recovery reads persisted receipt.");
        Require(remote.Writes == 1, "Recovery never replays POST.");
        var read = h.Read();
        Require(read.GetProperty("seconds").GetInt64() == 0 && read.GetProperty("consent").GetString() == "allowed" &&
            !read.GetProperty("showOnProfile").GetBoolean(), "Reset keeps consent and visibility.");
        preview = await h.Preview();
        Require(State(preview) == "preview", "Confirmed reset restores LIVE import.");
        Require(State(await h.Confirm(preview.GetProperty("previewId").GetString()!)) == "imported", "LIVE can import again once.");
        Require(State(await h.Preview()) == "imported", "Second import still blocked.");
        Require(await h.Runtime.ResetAsync(Owner, 1, 0, remote) == "conflict", "Stale confirmation rejected.");
        Require(h.Read().GetProperty("seconds").GetInt64() == 3600, "Conflict never clears local total.");

        remote.LoseReply = false;
        remote.AfterWrite = () => h.Current = (Owner with { Subject = "other" }, 2);
        Require(await h.Runtime.ResetAsync(Owner, 1, remote.State.Revision, remote) == "accountChanged", "Account change blocks completion.");
        Require(h.Read().GetProperty("seconds").GetInt64() == 0, "Other account stays independent.");
        h.Current = (Owner, 3);
        Require(await h.Runtime.ResetAsync(Owner, 3, null, remote) == "completed", "Original account resumes by receipt.");
        using var otherDevice = new Harness();
        preview = await otherDevice.Preview();
        await otherDevice.Confirm(preview.GetProperty("previewId").GetString()!);
        var writes = remote.Writes;
        await otherDevice.Runtime.RecoverResetAsync(remote);
        Require(otherDevice.Read().GetProperty("seconds").GetInt64() == 0, "Other device observes account-wide reset.");
        preview = await otherDevice.Preview();
        await otherDevice.Confirm(preview.GetProperty("previewId").GetString()!);
        otherDevice.Reopen();
        await otherDevice.Runtime.RecoverResetAsync(remote);
        Require(otherDevice.Read().GetProperty("seconds").GetInt64() == 3600, "Same reset epoch never erases a new import after restart.");
        Require(remote.Writes == writes, "Other device recovery is read-only.");
        Console.WriteLine("PASS gameplay reset Host journal, lost reply, restart, conflict, ownership and restored LIVE import");
    }

    internal static async Task ResetBridgeConfirmation()
    {
        using var h = new Harness();
        var remote = new ResetRemote();
        var invalid = await h.Runtime.DispatchResetAsync(h.Request("resetConfirm", new { schemaVersion = 1, previewId = "unknown" }), remote);
        Require(State(invalid.Response.Payload) == "previewExpired" && remote.Writes == 0, "No reset without Host preview.");
        var preview = await h.Runtime.DispatchResetAsync(h.Request("resetPreview"), remote);
        Require(State(preview.Response.Payload) == "ready" && remote.Writes == 0, "Preview reads only.");
        var id = preview.Response.Payload.GetProperty("previewId").GetString()!;
        var confirmation = h.Request("resetConfirm", new { schemaVersion = 1, previewId = id });
        Require(State((await h.Runtime.DispatchResetAsync(confirmation, remote)).Response.Payload) == "completed", "Explicit confirmation resets.");
        Require(State((await h.Runtime.DispatchResetAsync(confirmation, remote)).Response.Payload) == "previewExpired" && remote.Writes == 1,
            "Duplicate confirmation never creates another reset.");
        preview = await h.Runtime.DispatchResetAsync(h.Request("resetPreview"), remote);
        id = preview.Response.Payload.GetProperty("previewId").GetString()!;
        h.Current = (Owner, 2);
        Require(State((await h.Runtime.DispatchResetAsync(h.Request("resetConfirm", new { schemaVersion = 1, previewId = id }), remote)).Response.Payload) == "previewExpired",
            "Generation changes invalidate confirmation.");
        Require(remote.Writes == 1, "Stale confirmation does not write.");
    }
    private static readonly BridgeAccountContext Owner = new("test", "scm", "synthetic-history-owner");
    private sealed class Harness : IDisposable
    {
        internal readonly string Root = Path.Combine(Path.GetTempPath(), "starbridge-history-runtime-" + Guid.NewGuid().ToString("N"));
        internal (BridgeAccountContext? Context, long Generation) Current = (Owner, 1);
        internal GameplayHistoryEligibility Eligibility = new("available");
        internal string? Handle = "SyntheticPilot";
        internal Func<CancellationToken, Task>? BeforeEligibility;
        internal IGameplayHistoryRemote? Remote;
        internal GameplayTimeRuntime Runtime;
        internal string GameLog => Path.Combine(Root, "LIVE", "Game.log");
        internal Harness()
        {
            Directory.CreateDirectory(Path.Combine(Root, "LIVE", "logbackups"));
            File.WriteAllText(GameLog, "");
            File.WriteAllText(Path.Combine(Root, "LIVE", "logbackups", "session.log"),
                "<2020-01-01T00:00:00Z> boot\n" +
                "<2020-01-01T00:00:01Z> nickname=\"SyntheticPilot\" playerGEID=123\n" +
                "<2020-01-01T01:00:00Z> <SystemQuit> CSystem::Quit\n");
            Runtime = Create();
        }
        internal GameplayTimeRuntime Create() => new(new GameplayTimeStore(Root), () => Current,
            startTimer: false, verifiedHandle: () => Handle, historyEligibility: async (_, token) => {
                if (BeforeEligibility is not null) await BeforeEligibility(token);
                return Eligibility;
            }, historyRemote: Remote);
        internal BridgeEnvelope Request(string name, object? body = null, long? generation = null) =>
            BridgeEnvelope.Request("gameplayTime." + name, Guid.NewGuid().ToString("N"), generation ?? Current.Generation,
                body ?? new { schemaVersion = 1 }, Current.Context);
        internal JsonElement Read() => Runtime.Dispatch(Request("read")).Response.Payload;
        internal async Task<JsonElement> History(string name, object? body = null) =>
            (await Runtime.DispatchHistoryAsync(Request(name, body))).Response.Payload;
        internal Task<JsonElement> Preview() => History("historyPreview", new { schemaVersion = 1, path = GameLog });
        internal Task<JsonElement> Confirm(string id) => History("historyConfirm", new { schemaVersion = 1, previewId = id });
        internal void Reopen() { Runtime.Dispose(); Runtime = Create(); }
        public void Dispose() { Runtime.Dispose(); Directory.Delete(Root, true); } // Unique test fixture only.
    }

    internal static async Task OnceOnlyAndMigration()
    {
        using var h = new Harness();
        var before = h.Read();
        Require(before.GetProperty("showOnProfile").GetBoolean(), "Display default enabled.");
        var hidden = h.Runtime.Dispatch(h.Request("setVisibility", new { schemaVersion = 1, showOnProfile = false })).Response;
        Require(!hidden.Payload.GetProperty("showOnProfile").GetBoolean(), "Visibility independently saved.");
        h.Reopen();
        Require(!h.Read().GetProperty("showOnProfile").GetBoolean(), "Explicit hidden choice survives reopen.");
        var preview = await h.Preview();
        Require(State(preview) == "preview" && preview.GetProperty("seconds").GetInt64() == 3600, "Preview genuine parsed duration.");
        Require(h.Read().GetProperty("seconds").GetInt64() == 0, "Preview/cancel does not import.");
        var id = preview.GetProperty("previewId").GetString()!;
        Require(State(await h.Confirm(id)) == "imported", "Confirmation imports.");
        Require(h.Read().GetProperty("seconds").GetInt64() == 3600, "Imported once.");
        Require(State(await h.Confirm(id)) == "imported", "Lost response retry is idempotent.");
        h.Reopen();
        Require(State(await h.Preview()) == "imported" && h.Read().GetProperty("seconds").GetInt64() == 3600,
            "Restart does not grant another opportunity.");
        h.Eligibility = new("available");
        Require(State(await h.History("historyStatus")) == "imported", "Later unused migration cannot reset local consumed state.");

        using var migrated = new Harness();
        migrated.Eligibility = new("imported", DateTimeOffset.Parse("2020-02-01T00:00:00Z"));
        Require(State(await migrated.Preview()) == "imported", "Migrated consumed flag blocks scanning.");
        Require(migrated.Read().GetProperty("seconds").GetInt64() == 0, "Do not add migrated history twice.");
        migrated.Reopen(); migrated.Eligibility = new("available");
        Require(State(await migrated.History("historyStatus")) == "imported", "Migrated used flag persisted.");
        using var unknown = new Harness();
        unknown.Eligibility = new("unavailable");
        Require(State(await unknown.Preview()) == "unavailable", "Missing eligibility never grants a fresh chance.");
        unknown.Eligibility = new("available");
        Require(State(await unknown.Preview()) == "preview", "Explicitly unused migrated account retains its opportunity.");
        using var undated = new Harness();
        undated.Eligibility = new("imported");
        Require(State(await undated.History("historyStatus")) == "imported", "Known consumed can lack an original timestamp.");
        Require(!undated.Read().TryGetProperty("historyImportedAt", out _), "Unknown date is never fabricated.");
        undated.Reopen(); undated.Eligibility = new("available");
        Require(State(await undated.Preview()) == "imported", "Undated consumed marker also survives reopen.");
    }

    internal static async Task FailureAndOwnership()
    {
        using var h = new Harness();
        var preview = await h.Preview();
        var id = preview.GetProperty("previewId").GetString()!;
        var path = Directory.GetFiles(Path.Combine(h.Root, "gameplay-time-local-v1"), "*.json").Single();
        var original = File.ReadAllText(path);
        File.WriteAllText(path, "{}");
        Require(State(await h.Confirm(id)) == "unavailable", "Failed atomic save reported.");
        Require(File.ReadAllText(path) == "{}", "Unreadable data not replaced.");
        File.WriteAllText(path, original);
        Require(State(await h.Confirm(id)) == "imported", "Failed write did not consume eligibility.");
        Require(h.Read().GetProperty("seconds").GetInt64() == 3600, "Retry adds exactly once.");
        using var changed = new Harness();
        preview = await changed.Preview(); id = preview.GetProperty("previewId").GetString()!;
        changed.BeforeEligibility = _ => { changed.Current = (Owner with { Subject = "other" }, 2); return Task.CompletedTask; };
        Require(State(await changed.Confirm(id)) == "accountChanged", "Account changes across authority check invalidate confirmation.");
        changed.BeforeEligibility = null;
        Require(changed.Read().GetProperty("seconds").GetInt64() == 0, "Other account receives no imported seconds.");
        using var missingIdentity = new Harness();
        missingIdentity.Handle = null;
        Require(State(await missingIdentity.Preview()) == "identityRequired", "Handle required before scanning.");
        using var stopped = new Harness();
        stopped.Runtime.Dispatch(stopped.Request("setConsent", new { schemaVersion = 1, allowed = false }));
        Require(State(await stopped.Preview()) == "recordingRequired", "Explicitly stopped recording stays stopped; import cannot enable it.");
        using var revoked = new Harness();
        preview = await revoked.Preview(); id = preview.GetProperty("previewId").GetString()!;
        revoked.Eligibility = new("imported", DateTimeOffset.Parse("2020-02-02T00:00:00Z"));
        Require(State(await revoked.Confirm(id)) == "imported" && revoked.Read().GetProperty("seconds").GetInt64() == 0,
            "Migration consuming eligibility between preview and confirmation prevents import.");
        using var cancelled = new CancellationTokenSource();
        cancelled.Cancel();
        Require(State((await revoked.Runtime.DispatchHistoryAsync(revoked.Request("historyStatus"), cancelled.Token)).Response.Payload) == "cancelled",
            "Cancellation returns no data.");
    }

    internal static Task OldSnapshotCompatibility()
    {
        using var h = new Harness();
        h.Runtime.Dispose();
        using (var lease = new GameplayTimeStore(h.Root).Open(Owner))
            lease.Save(lease.Read(), GameplayRecordingConsent.Declined, 60, () => true);
        h.Runtime = h.Create();
        var state = h.Read();
        Require(state.GetProperty("consent").GetString() == "declined" && state.GetProperty("seconds").GetInt64() == 60,
            "Old v1 record checksum remains compatible and explicit declined is retained.");
        Require(state.GetProperty("showOnProfile").GetBoolean(), "Only newly introduced unset display defaults on.");
        return Task.CompletedTask;
    }
    private static string? State(JsonElement body) => body.GetProperty("state").GetString();
    private static void Require(bool value, string message) { if (!value) throw new InvalidOperationException(message); }
}
