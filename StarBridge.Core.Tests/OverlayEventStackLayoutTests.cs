using StarBridge.Desktop;

namespace StarBridge.Core.Tests;

internal static class OverlayEventStackLayoutTests
{
    internal static void RunAll()
    {
        static void Check(bool value, string message)
        {
            if (!value) throw new InvalidOperationException(message);
        }
        foreach (var (height, gap) in new[] { (48f, 5f), (64f, 8f), (56f, 0f), (96f, 0f) })
        {
            var previous = height;
            for (var step = 0; step <= 100; step++)
            {
                var p = step / 100f;
                var entering = OverlayEventStackLayout.Arrange([new(height), new(height, p, Entering: true)], gap);
                Check(entering.Height >= previous && entering.Height <= height * 2 + gap, "Entry must expand continuously without overshoot");
                Check(entering.Slots[0].Top == 0, "New lower event must not move the older upper event");
                Check(entering.Slots[1].OffsetY >= 0, "New event enters from below");
                previous = entering.Height;
                var exiting = OverlayEventStackLayout.Arrange([new(height, p, Exiting: true), new(height)], gap);
                Check(exiting.Slots[0].OffsetY <= 0, "Old event exits upward");
                Check(Math.Abs(exiting.Slots[1].Top - (height + gap) * (1 - p * p * (3 - 2 * p))) < 0.001, "Survivor follows the collapsing old slot");
            }
            var beforeRemoval = OverlayEventStackLayout.Arrange([new(height, 1, Exiting: true), new(height)], gap);
            var afterRemoval = OverlayEventStackLayout.Arrange([new(height)], gap);
            Check(beforeRemoval.Slots[1].Top == afterRemoval.Slots[0].Top && beforeRemoval.Height == afterRemoval.Height, "Removal must not snap the survivor");
            var middleGone = OverlayEventStackLayout.Arrange([new(height), new(height, 1, Exiting: true), new(height)], gap);
            var two = OverlayEventStackLayout.Arrange([new(height), new(height)], gap);
            Check(middleGone.Height == two.Height && middleGone.Slots[2].Top == two.Slots[1].Top, "Multiple events retain the gap after middle removal");
            var single = OverlayEventStackLayout.Arrange([new(height, 0.5f, Entering: true)], gap);
            Check(single.Height == height && single.Slots[0].OffsetY == 0, "Single-event skin animation remains unchanged");
        }
        // Fused appearances use no inter-row gap and must retain variable text heights.
        var variable = OverlayEventStackLayout.Arrange([new(56, .5f, Exiting: true), new(96)], 0);
        Check(variable.Slots[1].Top == 28 && variable.Height == 124, "Variable-height fused rows reflow from their real heights");
        var variableRemoved = OverlayEventStackLayout.Arrange([new(56, 1, Exiting: true), new(96)], 0);
        Check(variableRemoved.Slots[1].Top == 0 && variableRemoved.Height == 96, "Fused survivor preserves its own height after removal");
    }
}
