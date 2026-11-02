using System.Reflection;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Privacy;

// Original race tests exercise the original community/room state machine.
// Pair-specific tests additionally exercise both lanes and their shared fence.
internal static class PrivacyPublicationTestAccess
{
    internal static PrivacyPublication Ordinary(AccountBridgeRuntime runtime) =>
        Lane(runtime, "_ordinary");
    internal static PrivacyPublication Official(AccountBridgeRuntime runtime) =>
        Lane(runtime, "_official");
    private static PrivacyPublication Lane(AccountBridgeRuntime runtime, string name)
    {
        const BindingFlags flags = BindingFlags.NonPublic | BindingFlags.Instance;
        var pair = typeof(AccountBridgeRuntime).GetField("_privacyPublication", flags)!.GetValue(runtime)!;
        return (PrivacyPublication)pair.GetType().GetField(name, flags)!.GetValue(pair)!;
    }
}
