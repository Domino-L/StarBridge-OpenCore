using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Presence;
using StarBridge.NativeBridge;

internal static class LocalGamePresenceTests
{
    internal static async Task Verify()
    {
        bool? running = false;
        var time = new Clock();
        var reader = new LocalGamePresenceReader(() => running, time);
        Require(reader.Read().State == "notRunning", "Confirmed absence is not unknown.");
        running = true;
        Require(reader.Read().State == "running", "Game process is independent of app authentication.");
        running = false;
        Require(reader.Read().State == "running", "One missed poll must not terminate a session.");
        time.Now += TimeSpan.FromSeconds(9);
        Require(reader.Read().State == "running", "WPF exit grace is preserved.");
        time.Now += TimeSpan.FromSeconds(1);
        Require(reader.Read().State == "notRunning", "Stable absence confirms exit.");
        running = true;
        _ = reader.Read();
        running = null;
        Require(reader.Read().State == "unknown", "Failed observation must not keep stale in-game status.");

        LocalGameProcessObservation? observation = new(true, "EPTU");
        var versioned = new LocalGamePresenceReader(() => observation, time);
        var eptu = versioned.Read();
        Require(eptu.State == "running" && eptu.Version == "EPTU",
            "A running game with a readable log exposes its version.");
        string? confirmedVersion = null;
        var guarded = new LocalGamePresenceReader(() => observation, time, () => confirmedVersion);
        Require(guarded.Read().State == "running" && guarded.Read().Version is null,
            "A readable log cannot expose an unconfirmed version.");
        confirmedVersion = "EPTU";
        Require(guarded.Read().Version == "EPTU",
            "Only the account-matched Game.log version crosses the presence boundary.");
        observation = new(false);
        Require(versioned.Read().Version == "EPTU", "Exit grace preserves the last confirmed version.");
        time.Now += TimeSpan.FromSeconds(10);
        var stopped = versioned.Read();
        Require(stopped.State == "notRunning" && stopped.Version is null,
            "Confirmed exit clears the version.");
        observation = new(true, "../EPTU");
        Require(versioned.Read().State == "running" && versioned.Read().Version is null,
            "Invalid version labels are never exposed.");

        using var host = new HostBridgeDispatcher("local-test", () => 4,
            ["host.lifecycle", "host.gamePresence"], reader);
        var result = await host.DispatchAsync(BridgeEnvelope.Request("host.getGamePresence", "presence", 4));
        Require(result.Response.Status == BridgeResponseStatuses.Ok, "Local read requires no account context.");
        Require(result.Response.Payload.GetProperty("schemaVersion").GetInt32() == 1, "Versioned snapshot.");
        Require(result.Response.Payload.GetProperty("state").GetString() == "unknown", "Unknown survives wire.");
        Require(result.Events.Count == 0, "Read must not publish user presence.");
        var stale = await host.DispatchAsync(BridgeEnvelope.Request("host.getGamePresence", "old", 3));
        Require(stale.Response.Status != BridgeResponseStatuses.Ok, "Old generation rejected.");
        using var unsupported = new HostBridgeDispatcher("old-host");
        var rejected = await unsupported.DispatchAsync(BridgeEnvelope.Request("host.getGamePresence", "missing", 0));
        Require(rejected.Response.Error?.Code == BridgeErrorCodes.CapabilityUnavailable, "Optional capability fails closed.");
    }

    private static void Require(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException(message);
    }

    private sealed class Clock : TimeProvider
    {
        public DateTimeOffset Now { get; set; } = DateTimeOffset.UnixEpoch;
        public override DateTimeOffset GetUtcNow() => Now;
    }
}
