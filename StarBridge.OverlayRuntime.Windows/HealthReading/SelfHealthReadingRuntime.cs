using System;
using System.IO;
using StarBridge.HostRuntime.HealthReading;
using StarBridge.HostRuntime.Presence;

namespace StarBridge.OverlayRuntime.Windows.HealthReading;

// Composition for the "读取自己的血量" feature: the settings switch (default off), the game
// process check, the foreground check, the private model file and the game-window capture.
public sealed class SelfHealthReadingRuntime : IDisposable
{
    readonly SelfHealthReadingService _service;
    readonly SelfHealthLifeContext _life;
    internal SelfHealthReadingHub Hub { get; } = new();

    // The model is a private resource staged next to the executable; without it the feature stays off.
    internal static string ModelPath => Path.Combine(AppContext.BaseDirectory, "Assets", "HudHealth", HudHealthModel.FileName);

    public static bool ModelAvailable => File.Exists(ModelPath);

    // The shipped model, pinned: a missing, damaged or different file is never loaded (the feature stays off).
    internal const string ModelSha256 = "490973bb8b9c90c94781d82aa6fbd24ff7b90e8760a825f0afa625afedeed66c";

    internal static HudHealthModel? LoadPinnedModel(string path, string sha256)
    {
        if (!File.Exists(path)) return null;
        var bytes = File.ReadAllBytes(path);
        var actual = Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(bytes));
        if (!string.Equals(actual, sha256, StringComparison.OrdinalIgnoreCase)) return null;
        // Parse exactly the bytes that were checked, never the file again (it could be swapped in between).
        using var stream = new MemoryStream(bytes, writable: false);
        return HudHealthModel.Load(stream);
    }

    // overlay: the visor runtime; each change goes to the visor's own row only (never shared).
    // background: "游戏在后台时也读取" (default off): also read while the game window is behind other windows or
    // on another screen, never while it is minimized.
    // journal: the local game-event journal the client already keeps (null: no log facts; then only the "last reading
    // was full" memory applies). diagnosticsRoot: where self-health-diagnostics.log goes (counts only; null: none).
    // menuOpen + clientProcessId: StarBridge's own in-game menu is shown (11-13 user: keep reading while it is open):
    // with it shown and a StarBridge window in front, the game behind it is read as if it were in front (shown, not
    // minimized), whatever the background switch says. Switching to any other program follows the background switch.
    // gameLogLive: the game log says the player is in a server now (11-17 review R5/R6 P1: the log page's "stop", an
    // unreadable log or the main menu ends the log-based full; null: taken as yes).
    public SelfHealthReadingRuntime(Func<bool> enabled, object? overlay = null, Func<bool>? background = null,
        StarBridge.HostRuntime.Support.LocalGameEventJournal? journal = null, string? diagnosticsRoot = null,
        Func<bool>? menuOpen = null, int? clientProcessId = null, Func<bool>? gameLogLive = null)
    {
        _life = new SelfHealthLifeContext(journal);
        var backgroundSwitch = background ?? (() => false);
        var ours = new HashSet<uint> { (uint)Environment.ProcessId };
        if (clientProcessId is > 0) ours.Add((uint)clientProcessId.Value);
        Func<bool> inBackground = menuOpen == null ? backgroundSwitch
            : () => backgroundSwitch() || (menuOpen() && HudGameWindow.ForegroundBelongsTo(ours));
        if (overlay is StarBridge.Desktop.NativeInformationOverlayRuntime visor)
            Hub.Changed += reading =>
            {
                var (kind, health) = reading.ToVisor();
                visor.ReportLocalVitals((StarBridge.Desktop.OverlayVisorVitals)(int)kind, health);
            };
        _service = new SelfHealthReadingService(
            enabled,
            SharedGameProcesses.IsRunning,
            () => HudGameWindow.CanRead(HudWindowCaptureFactory.Allowed(inBackground)),
            () => LoadPinnedModel(ModelPath, ModelSha256),
            new HudWindowCaptureFactory(inBackground),
            Hub.Publish)
        {
            Life = () => _life.Current,
            Diagnostics = diagnosticsRoot == null ? null : new SelfHealthDiagnostics(SelfHealthDiagnosticsFile.For(diagnosticsRoot)),
            // 11-17: kept next to the diagnostics in the data root (sizes only); without one, for this run only.
            ReadableSizes = new SelfHealthReadableSizes(diagnosticsRoot),
            LogLive = gameLogLive,
        };
        _service.Start();
    }

    public void Dispose()
    {
        _service.Dispose();
        _life.Dispose();
    }
}
