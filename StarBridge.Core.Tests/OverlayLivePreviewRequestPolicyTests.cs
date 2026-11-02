using StarBridge.NativeBridge;

namespace StarBridge.Core.Tests;

internal static class OverlayLivePreviewRequestPolicyTests
{
    internal static void RunAll()
    {
        // Exercise the real platform-free bridge assembly, not a copied policy.
        foreach (var action in new[] { "open", "update", "close", "protect", "playback", "renew" })
        {
            var name = "overlay.appearanceLivePreview." + action;
            BridgeEnvelopeValidator.RequireAccountContext(name, null);
            if (BridgeRequestPolicy.RequiresAccountContext(name))
                throw new InvalidOperationException("Finite preview unexpectedly requires renderer account context: " + name);
        }
        foreach (var protectedName in new[] {
            "overlay.appearanceLivePreview", "overlay.appearanceLivePreview.report",
            "overlay.appearanceLivePreview.renew.extra", "overlay.appearanceLivePreview.petAction",
            "overlay.appearanceLivePreview.Open", "overlay.appearanceProgress.report",
            "overlay.appearance.apply", "presence.set", "account.logout"
        })
        {
            if (!BridgeRequestPolicy.RequiresAccountContext(protectedName))
                throw new InvalidOperationException("Accountless preview widened an unrelated request: " + protectedName);
            try
            {
                BridgeEnvelopeValidator.RequireAccountContext(protectedName, null);
                throw new InvalidOperationException("Protected request accepted without account context: " + protectedName);
            }
            catch (BridgeProtocolException error) when (error.Code == BridgeErrorCodes.AccountContextRequired) { }
        }
    }
}
