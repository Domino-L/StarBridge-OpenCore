using System.Text;
using StarBridge.HostRuntime.Presence;
using StarBridge.NativeBridge;

// OWNER-GATE-073 review addition: a fault in the downstream city-arrival consumer
// (for example an unreadable city achievement outbox) must not turn the whole
// recognition into a storage error, and must not replay on every sample.
internal static class OwnerGate073CityTests
{
    private static readonly BridgeAccountContext Owner = new("test", "scm", "synthetic-city-fault-owner");
    private static readonly DateTimeOffset Now = DateTimeOffset.Parse("2026-10-28T12:00:30Z");
    private const string Stamp = "<2026-10-28T12:00:20Z> ";
    private sealed class Clock : TimeProvider { public override DateTimeOffset GetUtcNow() => Now; }

    internal static Task<int> Run()
    {
        var failed = 0;
        foreach (var (name, run) in new (string, Action)[] {
            ("CityArrivalFaultIsIsolated", CityArrivalFaultIsIsolated),
            ("CorruptCachedSettingsStayVisible", CorruptCachedSettingsStayVisible) })
        {
            try { run(); Console.WriteLine("PASS CX073 " + name); }
            catch (RestrictedSampleAbsentException e) { e.Report(name); }
            catch (Exception e) { failed++; Console.WriteLine("FAIL CX073 " + name + " " + e.Message); }
        }
        return Task.FromResult(failed);
    }

    // Review P2: a healthy sample must not mask a persistent settings storage fault
    // just because the settings were already cached before the file went bad.
    private static void CorruptCachedSettingsStayVisible()
    {
        var root = Path.Combine(Path.GetTempPath(), "sb-cx073-settings-" + Guid.NewGuid().ToString("N"));
        var log = Path.Combine(root, "StarCitizen", "LIVE", "Game.log");
        Directory.CreateDirectory(Path.GetDirectoryName(log)!);
        File.WriteAllText(log, Stamp + "[Notice] nickname=\"Pilot_A\" playerGEID=12345\n" +
            Stamp + "<Join PU> connected to shard[pub_sc_alpha_apse1_123]\n", new UTF8Encoding(false));
        using var capture = StarBridge.HostRuntime.Support.IdentityGateJournal.Capture((_, _) => { });
        try
        {
            using var game = new GameLogRuntime(new GameLogSettingsStore(root), () => (Owner, 1), () => "Pilot_A",
                () => new("running", log, Now.AddMinutes(-1), "synthetic-process"), new Clock(), startTimer: false);
            game.Dispatch(BridgeEnvelope.Request("gameLog.select", Guid.NewGuid().ToString("N"), 1,
                new { schemaVersion = 1, path = log }, Owner));
            game.Sample();
            Require(game.DetectedHandle == "Pilot_A", "baseline recognition with cached settings");
            var settings = Directory.GetFiles(Path.Combine(root, "game-log-local-v1"), "*.json").Single();
            File.WriteAllText(settings, "{\"broken\":");
            var retry = game.Dispatch(BridgeEnvelope.Request("gameLog.retry", Guid.NewGuid().ToString("N"), 1,
                new { schemaVersion = 1 }, Owner)).Response;
            Require(retry.Error is not null, "retry must surface the corrupt settings file");
            game.Sample(); game.Sample();
            Require(game.DetectedHandle is null, "a later sample must reread the settings and keep the fault visible");
        }
        finally { if (Directory.Exists(root)) Directory.Delete(root, true); }
    }

    private static void CityArrivalFaultIsIsolated()
    {
        RestrictedSamples.RequireCityLocationCatalog();
        var root = Path.Combine(Path.GetTempPath(), "sb-cx073-city-" + Guid.NewGuid().ToString("N"));
        var log = Path.Combine(root, "StarCitizen", "LIVE", "Game.log");
        Directory.CreateDirectory(Path.GetDirectoryName(log)!);
        File.WriteAllText(log, Stamp + "[Notice] nickname=\"Pilot_A\" playerGEID=12345\n" +
            Stamp + "<Join PU> connected to shard[pub_sc_alpha_apse1_123]\n", new UTF8Encoding(false));
        var diagnostics = new List<string>();
        using var capture = StarBridge.HostRuntime.Support.IdentityGateJournal.Capture((stage, code) => diagnostics.Add(stage + " " + code));
        try
        {
            using var game = new GameLogRuntime(new GameLogSettingsStore(root), () => (Owner, 1), () => "Pilot_A",
                () => new("running", log, Now.AddMinutes(-1), "synthetic-process"), new Clock(), startTimer: false);
            var deliveries = 0;
            game.CityArrival += _ => { deliveries++; throw new InvalidDataException("synthetic unreadable city outbox"); };
            game.Dispatch(BridgeEnvelope.Request("gameLog.select", Guid.NewGuid().ToString("N"), 1,
                new { schemaVersion = 1, path = log }, Owner));
            game.Sample();
            Require(game.DetectedHandle == "Pilot_A", "baseline recognition");
            File.AppendAllText(log, Stamp + "<RequestLocationInventory> Player[Pilot_A] requested inventory for Location[Stanton1_Lorville]\n");
            game.Sample();
            Require(deliveries == 1, "the live arrival is delivered once: " + deliveries);
            Require(game.DetectedHandle == "Pilot_A" && game.CurrentSession.Server.State == "connected",
                "a city consumer fault must keep recognition and the session");
            game.Sample(); game.Sample();
            Require(deliveries == 1, "a faulted arrival is dropped, not replayed on every sample: " + deliveries);
            var read = game.Dispatch(BridgeEnvelope.Request("gameLog.read", Guid.NewGuid().ToString("N"), 1,
                new { schemaVersion = 1 }, Owner)).Response;
            Require(read.Error is null && read.Payload.GetProperty("state").GetString() == "identified",
                "settings page read stays healthy: " + read.Error?.Code);
            Require(diagnostics.Any(d => d.StartsWith("city-arrival code=deliver exception=InvalidDataException", StringComparison.Ordinal)),
                "fault is recorded with its type only");
        }
        finally { if (Directory.Exists(root)) Directory.Delete(root, true); }
    }

    private static void Require(bool value, string reason) { if (!value) throw new Exception(reason); }
}
