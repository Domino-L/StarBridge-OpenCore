using System.Text.Json;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Onboarding;
using StarBridge.HostRuntime.Presence;
using StarBridge.NativeBridge;

// Local-profile history import: explicit, previewed, once only, and never clearing saved time.
internal static class LocalHistoryImportTests
{
    private const string Handle = "Pilot-Example";
    private static readonly DateTimeOffset Past = new(2025, 12, 30, 10, 0, 0, TimeSpan.Zero);
    private static void Check(bool value, string message) { if (!value) throw new InvalidOperationException(message); }
    private static BridgeEnvelope Request(string name, long generation = 1, object? payload = null) =>
        BridgeEnvelope.Request(name, Guid.NewGuid().ToString("N"), generation, payload ?? new { schemaVersion = 1 });
    private static async Task<JsonElement> Send(IBridgeRequestDispatcher d, string name, object? payload = null, long generation = 1)
    {
        var reply = (await d.DispatchAsync(Request(name, generation, payload))).Response;
        Check(reply.Status == "ok", name + " failed: " + reply.Error?.Code);
        return reply.Payload;
    }
    private static string State(JsonElement body) => body.GetProperty("state").GetString()!;
    private static string Line(DateTimeOffset at, string text) => $"<{at:yyyy-MM-dd'T'HH:mm:ss'Z'}> {text}\n";
    private static void Backup(LocalGameplayTimeTests.Fixture f, string name, DateTimeOffset start, double minutes, string handle = Handle)
    {
        var directory = Path.Combine(Path.GetDirectoryName(f.Log)!, "logbackups");
        Directory.CreateDirectory(directory);
        File.WriteAllText(Path.Combine(directory, name),
            Line(start, "boot") + Line(start.AddSeconds(1), $"nickname=\"{handle}\" playerGEID=100") +
            Line(start.AddMinutes(minutes), "<SystemQuit> CSystem::Quit"));
    }
    private static async Task<JsonElement> Scan(IBridgeRequestDispatcher d)
    {
        var body = await Send(d, LocalStatisticsChoiceBridgeDispatcher.HistoryScanStartRequest);
        for (var attempt = 0; State(body) == "scanning" && attempt < 500; attempt++)
        {
            await Task.Delay(20);
            body = await Send(d, LocalStatisticsChoiceBridgeDispatcher.HistoryScanReadRequest,
                new { schemaVersion = 1, scanId = body.GetProperty("scanId").GetString() });
        }
        return body;
    }
    private static Task<JsonElement> Confirm(IBridgeRequestDispatcher d, string previewId) =>
        Send(d, LocalStatisticsChoiceBridgeDispatcher.HistoryConfirmRequest, new { schemaVersion = 1, previewId });

    internal static async Task Run()
    {
        await RequiresRecording(); await PreviewThenImportOnce(); await KeepsLiveTimeAndCutoff(); await FailedWriteRetries();
        await EmptyAndCancel(); await StrictAndScoped(); await ResetRestoresImport(); await ResetFailureKeepsData();
    }

    private static async Task RequiresRecording()
    {
        using var f = new LocalGameplayTimeTests.Fixture(); Backup(f, "a.log", Past, 60);
        using var d = new LocalStatisticsChoiceBridgeDispatcher(f.Stats, () => 1);
        Check(State(await Send(d, LocalStatisticsChoiceBridgeDispatcher.HistoryReadRequest)) == "recordingRequired", "unknown consent blocks import");
        Check(State(await Send(d, LocalStatisticsChoiceBridgeDispatcher.HistoryScanStartRequest)) == "recordingRequired", "no scan without recording");
        f.Stats.ApplyConsent(f.Key, false);
        Check(State(await Send(d, LocalStatisticsChoiceBridgeDispatcher.HistoryReadRequest)) == "recordingRequired", "declined blocks import");
        Check(f.Saved.Seconds == 0 && f.Saved.HistoryImportedAt is null, "nothing imported automatically");
        Console.WriteLine("PASS local history import: requires saved recording consent and never starts automatically");
    }

    private static async Task PreviewThenImportOnce()
    {
        using var f = new LocalGameplayTimeTests.Fixture(); Backup(f, "a.log", Past, 60); Backup(f, "b.log", Past.AddHours(3), 30);
        using var d = new LocalStatisticsChoiceBridgeDispatcher(f.Stats, () => 1);
        f.Allow();
        Check(State(await Send(d, LocalStatisticsChoiceBridgeDispatcher.HistoryReadRequest)) == "available", "available after allow");
        var before = f.Bytes(f.Profile);
        var preview = await Scan(d);
        Check(State(preview) == "preview" && preview.GetProperty("sessions").GetInt32() == 2, "preview lists sessions");
        var seconds = preview.GetProperty("seconds").GetInt64();
        Check(seconds is > 5300 and < 5500, "preview seconds from both sessions: " + seconds);
        Check(f.Bytes(f.Profile).SequenceEqual(before), "preview writes nothing");
        var raw = preview.GetRawText();
        Check(new[] { Handle, f.Root, f.Profile, f.Key, "logbackups", ".log" }.All(v => !raw.Contains(v, StringComparison.OrdinalIgnoreCase)),
            "aggregate-only projection");
        Check(State(await Send(d, LocalStatisticsChoiceBridgeDispatcher.HistoryReadRequest)) == "preview", "pending preview survives reopen");
        var id = preview.GetProperty("previewId").GetString()!;
        var imported = await Confirm(d, id);
        Check(State(imported) == "imported" && imported.GetProperty("importedSeconds").GetInt64() == seconds &&
            f.Saved.Seconds == seconds && f.Saved.HistoricalSeconds == seconds && f.Saved.HistoryImportedAt is not null, "one atomic import");
        Check(State(await Confirm(d, id)) == "imported" && f.Saved.Seconds == seconds, "replayed confirm never adds again");
        Check(State(await Send(d, LocalStatisticsChoiceBridgeDispatcher.HistoryScanStartRequest)) == "imported" && f.Saved.Seconds == seconds,
            "no second scan after import");
        f.Reopen();
        using var reopened = new LocalStatisticsChoiceBridgeDispatcher(f.Stats, () => 1);
        var read = await Send(reopened, LocalStatisticsChoiceBridgeDispatcher.HistoryReadRequest);
        Check(State(read) == "imported" && read.GetProperty("importedSeconds").GetInt64() == seconds, "restart shows real imported state");
        Console.WriteLine("PASS local history import: preview is read-only; confirm imports once and survives restart");
    }

    private static async Task KeepsLiveTimeAndCutoff()
    {
        using var f = new LocalGameplayTimeTests.Fixture(); Backup(f, "a.log", Past, 60);
        using var d = new LocalStatisticsChoiceBridgeDispatcher(f.Stats, () => 1);
        f.RecordFive();
        var first = f.Saved.FirstRecordedAt!.Value;
        // A backup after live recording began is never history; it would overlap recorded samples.
        Backup(f, "late.log", first.AddMinutes(1), 10);
        var preview = await Scan(d);
        var seconds = preview.GetProperty("seconds").GetInt64();
        Check(State(preview) == "preview" && preview.GetProperty("sessions").GetInt32() == 1, "cutoff excludes overlapping sessions");
        await Confirm(d, preview.GetProperty("previewId").GetString()!);
        Check(f.Saved.Seconds == 5 + seconds && f.Saved.FirstRecordedAt == first, "live time kept and first-record time unchanged");
        f.Tick(5);
        Check(f.Saved.Seconds == 10 + seconds && f.Saved.HistoryImportedAt is not null, "recording continues on top of imported time");
        Console.WriteLine("PASS local history import: existing time preserved, cutoff prevents overlap, sampling continues");
    }

    private static async Task FailedWriteRetries()
    {
        using var f = new LocalGameplayTimeTests.Fixture(); Backup(f, "a.log", Past, 60);
        f.RecordFive();
        f.Reopen(); // A fresh owner holds no writer until its first save, so a foreign writer can block it.
        using var d = new LocalStatisticsChoiceBridgeDispatcher(f.Stats, () => 1);
        var preview = await Scan(d); var id = preview.GetProperty("previewId").GetString()!;
        var bytes = f.Bytes(f.Profile);
        using (f.Storage.Open(f.Profile, () => true))
            Check(State(await Confirm(d, id)) == "unavailable", "locked store does not import");
        Check(f.Bytes(f.Profile).SequenceEqual(bytes) && f.Saved.Seconds == 5 && f.Saved.HistoryImportedAt is null,
            "failed write keeps original data and consumes nothing");
        var retried = await Confirm(d, id);
        Check(State(retried) == "imported" && f.Saved.Seconds == 5 + preview.GetProperty("seconds").GetInt64(), "explicit retry imports once");
        Console.WriteLine("PASS local history import: failed write is retryable and never clears saved time");
    }

    private static async Task EmptyAndCancel()
    {
        using var f = new LocalGameplayTimeTests.Fixture();
        using var d = new LocalStatisticsChoiceBridgeDispatcher(f.Stats, () => 1);
        f.Allow();
        Backup(f, "other.log", Past, 60, "Another-Pilot");
        var empty = await Scan(d);
        Check(State(empty) is "empty" && f.Saved.Seconds == 0 && f.Saved.HistoryImportedAt is null, "foreign identity is not history: " + State(empty));
        Check(State(await Send(d, LocalStatisticsChoiceBridgeDispatcher.HistoryReadRequest)) == "available", "empty result keeps import available");
        for (var i = 0; i < 40; i++) Backup(f, $"s{i:00}.log", Past.AddHours(i), 30);
        var started = await Send(d, LocalStatisticsChoiceBridgeDispatcher.HistoryScanStartRequest);
        if (State(started) == "scanning")
        {
            var scanId = started.GetProperty("scanId").GetString();
            var body = await Send(d, LocalStatisticsChoiceBridgeDispatcher.HistoryScanCancelRequest, new { schemaVersion = 1, scanId });
            for (var attempt = 0; State(body) == "scanning" && attempt < 500; attempt++)
            {
                await Task.Delay(20);
                body = await Send(d, LocalStatisticsChoiceBridgeDispatcher.HistoryScanReadRequest, new { schemaVersion = 1, scanId });
            }
            Check(State(body) == "cancelled", "cancel reports cancelled: " + State(body));
        }
        Check(f.Saved.Seconds == 0 && f.Saved.HistoryImportedAt is null, "cancel imports nothing");
        Console.WriteLine("PASS local history import: empty and cancelled scans import nothing and stay retryable");
    }

    private static async Task StrictAndScoped()
    {
        using var f = new LocalGameplayTimeTests.Fixture(); Backup(f, "a.log", Past, 60);
        long generation = 1;
        using var d = new LocalStatisticsChoiceBridgeDispatcher(f.Stats, () => generation);
        f.Allow();
        foreach (var payload in new object[] { new { schemaVersion = 1, previewId = "bad" }, new { schemaVersion = 1, previewId = 1 },
            new { schemaVersion = 1, previewId = Guid.NewGuid().ToString("N"), seconds = 99 } })
            Check((await d.DispatchAsync(Request(LocalStatisticsChoiceBridgeDispatcher.HistoryConfirmRequest, payload: payload))).Response.Status == "error",
                "strict confirm fields");
        Check((await d.DispatchAsync(Request(LocalStatisticsChoiceBridgeDispatcher.HistoryReadRequest, payload: new { schemaVersion = 1, path = "x" }))).Response.Status == "error",
            "strict read fields");
        Check(State(await Confirm(d, Guid.NewGuid().ToString("N"))) == "previewExpired", "unknown preview cannot import");
        var preview = await Scan(d); var id = preview.GetProperty("previewId").GetString()!;
        generation = 2;
        Check((await d.DispatchAsync(Request(LocalStatisticsChoiceBridgeDispatcher.HistoryConfirmRequest, 1, new { schemaVersion = 1, previewId = id }))).Response.Status == "error",
            "old generation cannot confirm");
        f.Clock.Now = f.Clock.Now.AddMinutes(6);
        Check(State(await Send(d, LocalStatisticsChoiceBridgeDispatcher.HistoryConfirmRequest,
            new { schemaVersion = 1, previewId = id }, 2)) == "previewExpired", "expired preview cannot import");
        Check(f.Saved.HistoryImportedAt is null && f.Saved.Seconds == 0, "nothing imported");
        f.Mode = (false, f.Mode.Generation + 1);
        Check(State(await Send(d, LocalStatisticsChoiceBridgeDispatcher.HistoryReadRequest, generation: 2)) == "inactive", "inactive local owner");
        Console.WriteLine("PASS local history import: strict fields, generation, expiry and mode scope");
    }

    private static Task<JsonElement> ResetPreview(IBridgeRequestDispatcher d) =>
        Send(d, LocalStatisticsChoiceBridgeDispatcher.ResetPreviewRequest);
    private static Task<JsonElement> ResetConfirm(IBridgeRequestDispatcher d, string resetId) =>
        Send(d, LocalStatisticsChoiceBridgeDispatcher.ResetConfirmRequest, new { schemaVersion = 1, resetId });

    private static async Task ResetRestoresImport()
    {
        using var f = new LocalGameplayTimeTests.Fixture(); Backup(f, "a.log", Past, 60);
        using var d = new LocalStatisticsChoiceBridgeDispatcher(f.Stats, () => 1);
        Check(State(await ResetPreview(d)) == "empty", "nothing recorded: nothing to reset");
        f.RecordFive();
        var preview = await Scan(d);
        var history = preview.GetProperty("seconds").GetInt64();
        await Confirm(d, preview.GetProperty("previewId").GetString()!);
        var bytes = f.Bytes(f.Profile);
        var reset = await ResetPreview(d);
        Check(State(reset) == "ready" && reset.GetProperty("seconds").GetInt64() == 5 + history &&
            reset.GetProperty("historicalSeconds").GetInt64() == history, "preview shows what will be cleared");
        Check(f.Bytes(f.Profile).SequenceEqual(bytes), "reset preview writes nothing");
        var raw = reset.GetRawText();
        Check(new[] { Handle, f.Root, f.Profile, f.Key }.All(v => !raw.Contains(v, StringComparison.OrdinalIgnoreCase)), "aggregate-only reset projection");
        var id = reset.GetProperty("resetId").GetString()!;
        Check(State(await ResetConfirm(d, id)) == "reset", "explicit confirmation resets");
        var saved = f.Saved;
        Check(saved.Seconds == 0 && saved.FirstRecordedAt is null && saved.HistoryImportedAt is null &&
            saved.HistoricalSeconds is null && saved.Consent == GameplayRecordingConsent.Allowed, "time cleared, consent unchanged");
        var backup = f.Storage.ResetBackupPathFor(f.Profile);
        Check(File.Exists(backup) && File.ReadAllBytes(backup).SequenceEqual(bytes), "previous file kept as backup");
        Check(State(await ResetConfirm(d, id)) == "previewExpired" && f.Saved.Revision == saved.Revision, "confirmation is never replayed");
        Check(State(await Send(d, LocalStatisticsChoiceBridgeDispatcher.HistoryReadRequest)) == "available", "import eligibility restored");
        var again = await Scan(d);
        Check(State(await Confirm(d, again.GetProperty("previewId").GetString()!)) == "imported" &&
            f.Saved.Seconds == again.GetProperty("seconds").GetInt64(), "one new import after reset");
        f.Tick(5); f.Tick(5);
        Check(f.Saved.Seconds > again.GetProperty("seconds").GetInt64(), "recording continues after reset and import");
        foreach (var payload in new object[] { new { schemaVersion = 1, resetId = "bad" }, new { schemaVersion = 1, resetId = 1 },
            new { schemaVersion = 1, resetId = Guid.NewGuid().ToString("N"), seconds = 0 } })
            Check((await d.DispatchAsync(Request(LocalStatisticsChoiceBridgeDispatcher.ResetConfirmRequest, payload: payload))).Response.Status == "error",
                "strict reset fields");
        Console.WriteLine("PASS local time reset: explicit preview/confirm, backup kept, consent unchanged, import restored once");
    }

    private static async Task ResetFailureKeepsData()
    {
        using var f = new LocalGameplayTimeTests.Fixture();
        f.RecordFive(); f.Reopen();
        using var d = new LocalStatisticsChoiceBridgeDispatcher(f.Stats, () => 1);
        var id = (await ResetPreview(d)).GetProperty("resetId").GetString()!;
        var bytes = f.Bytes(f.Profile);
        using (f.Storage.Open(f.Profile, () => true))
            Check(State(await ResetConfirm(d, id)) == "unavailable", "locked store does not reset");
        Check(f.Bytes(f.Profile).SequenceEqual(bytes) && f.Saved.Seconds == 5, "failed reset keeps original data");
        Check(State(await ResetConfirm(d, id)) == "previewExpired", "failed reset needs a fresh explicit preview");
        f.Clock.Now = f.Clock.Now.AddMinutes(6);
        id = (await ResetPreview(d)).GetProperty("resetId").GetString()!;
        f.Clock.Now = f.Clock.Now.AddMinutes(6);
        Check(State(await ResetConfirm(d, id)) == "previewExpired" && f.Saved.Seconds == 5, "expired preview cannot reset");
        Console.WriteLine("PASS local time reset: failed or expired confirmation keeps original data");
    }
}
