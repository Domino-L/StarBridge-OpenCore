using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Support;
using StarBridge.NativeBridge;

internal static partial class FirstUseBusinessOwnerTests
{
    internal static async Task RunDeviceNetworkResume()
    {
        using var f = new Fixture(); f.Original.Clock.AllowTimers = true; await f.Start();
        await using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
        using var transport = new DeviceNetworkOfflineTests.Transport();
        using var support = new HelpSupportBridgeDispatcher(new Uri("https://synthetic-support.example.invalid/"), () => native.Generation, transport,
            network: f.Original.Local.Runtime.DeviceNetwork);
        Task<BridgeDispatchBatch> Stats() => support.DispatchAsync(BridgeEnvelope.Request("helpSupport.stats", Id(), native.Generation, new { schemaVersion = 1 })).AsTask();
        Check((await Stats()).Response.Status != "ok" && transport.Calls == 0, "Confirmed authentication does not admit general device networking");
        await native.InstallConfirmedOnlineAsync(f.Original.Mode.Current.Revision, _ => { });
        Check((await Stats()).Response.Status == "ok" && transport.Calls == 1, "Actual installed online graph admits device requests");
        await f.Original.Mode.ApplyOfflineAsync(f.Original.Mode.Current.Revision, Id(), native.Generation);
        Check((await Stats()).Response.Status != "ok" && transport.Calls == 1, "Physical offline closes old device epoch");
        f.Original.Mode.RequestResume(f.Original.Mode.Current.Revision, Id()); await ConfirmRetained(f);
        Check((await Stats()).Response.Status != "ok" && transport.Calls == 1, "Retained authentication/review cannot reopen device networking");
        await native.InstallConfirmedOnlineAsync(f.Original.Mode.Current.Revision, _ => { });
        Check((await Stats()).Response.Status == "ok" && transport.Calls == 2, "Only second actual Native installation and old exit permit a new device epoch");
        Console.WriteLine("PASS device network re-admits only after actual original online installation, not retained authentication/review");
    }
}
