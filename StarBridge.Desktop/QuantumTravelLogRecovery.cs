using System.IO;
using StarBridge.Core.Events;
using StarBridge.Core.Parsing;
using StarBridge.Core.State;

namespace StarBridge.Desktop;

internal static class QuantumTravelLogRecovery
{
    public static void ReplayInto(
        QuantumTravelContextTracker tracker,
        string path,
        int maxBytes,
        int maxLines)
    {
        ArgumentNullException.ThrowIfNull(tracker);
        if (string.IsNullOrWhiteSpace(path) || !File.Exists(path))
        {
            return;
        }

        var parser = new RegexLogEventParser();
        foreach (var line in GameLogInitialReplayReader.ReadTailLines(path, maxBytes, maxLines))
        {
            if (!CouldContainQuantumContext(line))
            {
                continue;
            }

            var fleetEvent = parser.TryParse(line);
            if (fleetEvent?.Type is FleetEventType.PlayerNavigationTargetChanged or FleetEventType.PlayerLocationChanged)
            {
                tracker.Resolve(fleetEvent);
            }
        }
    }

    private static bool CouldContainQuantumContext(string line) =>
        line.Contains("<Player Selected Quantum Target - Local>", StringComparison.OrdinalIgnoreCase) ||
        line.Contains("<Calculate Route>", StringComparison.OrdinalIgnoreCase) ||
        line.Contains("<Quantum Drive Arrived - Arrived at Final Destination>", StringComparison.OrdinalIgnoreCase);
}
