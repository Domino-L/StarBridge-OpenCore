using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Privacy;
using StarBridge.NativeBridge;

internal static partial class FirstUseBusinessOwnerTests
{
    internal static async Task RunRuntimeReady()
    {
        using var f = new Fixture(); f.Original.Clock.AllowTimers = true; await f.Start();
        await using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
        bool hold = false; var entered=Signal(); using var release=new ManualResetEventSlim();
        IReadOnlyList<string> Additional() => native.Read(owner => {
            if(hold) { entered.TrySetResult(); if(!release.Wait(TimeSpan.FromSeconds(5))) throw new TimeoutException(); }
            return owner.OfficialFleetRealtimeCapabilities;
        }, (IReadOnlyList<string>)Array.Empty<string>());
        using var lifecycle=new HostBridgeDispatcher(Id(),()=>native.Generation,["host.lifecycle","friends.read"],additionalCapabilities:Additional);
        Task<BridgeDispatchBatch> Ready(long? generation=null)=>lifecycle.DispatchAsync(BridgeEnvelope.Request("host.ready",Id(),generation??native.Generation,new{})).AsTask();
        static string[] Caps(BridgeDispatchBatch response)=>response.Response.Payload.GetProperty("hostCapabilities").EnumerateArray().Select(x=>x.GetString()!).ToArray();
        var local=await Ready();
        Check(local.Response.Status=="ok" && Caps(local).SequenceEqual(new[]{"host.lifecycle","friends.read"}),"real local shell Ready preserves base capabilities and has no official runtime protocol");
        var (prepared,callbacks,sources)=await AdmissionPreparation(f,native);
        var install=prepared.StageInstallation(callbacks,sources)!;
        using var noNetwork=new RuntimeReadyNoNetwork();
        Check(install.Configure(_=> {
            f.Original.Host!.ConfigurePrivacyWriter(new PrivacyRelayWriter(new Uri("https://no-network.example.invalid/"),noNetwork));
            f.Original.Host.ConfigureOfficialRealtime(true);
        }) && install.TryActivate() && native.InstallBusiness(install) is not null,"original native installation owns configured SCM runtime");
        var installed=await Ready();
        Check(installed.Response.Status=="ok" && Caps(installed).Contains("officialFleet.runtimeMembers") && Caps(installed).Contains("privacy.officialFleetScopes") &&
            Caps(installed).Contains("officialFleet.runtimeActivity") && Caps(installed).Contains("friends.read"),"same Ready handshake gains only configured installed SCM protocol without restart");
        f.Original.Host!.ConfigureOfficialRealtime(false);
        Check(!(Caps(await Ready())).Contains("officialFleet.runtimeMembers"),"disabled installed owner cannot retain stale protocol capabilities");
        f.Original.Host.ConfigureOfficialRealtime(true);
        var admitted=native.Generation; hold=true;
        var late=Task.Run(()=>Ready(admitted)); await Finish(entered.Task);
        var retirement=install.RetireAsync();
        Check(native.Generation==-1 && !retirement.IsCompleted,"actual installation closes admission before held Ready observation exits");
        release.Set();
        var retired=await Finish(late);
        Check(retired.Response.Status!="ok","late old-owner Ready cannot restore retired protocol capabilities");
        await Finish(retirement); hold=false;
        Check((await Finish(f.Original.Cancel())).State=="local" && !Caps(await Ready()).Contains("officialFleet.runtimeMembers"),"reconstructed local owner does not inherit installed runtime capabilities");
        using var old=new HostBridgeDispatcher(Id());
        var oldReady=await old.DispatchAsync(BridgeEnvelope.Request("host.ready",Id(),0,new{}));
        Check(!oldReady.Response.Payload.TryGetProperty("hostCapabilities",out _),"old Host constructor preserves optional-field-free Ready wire");
        using var failed=new HostBridgeDispatcher(Id(),capabilities:["host.lifecycle"],additionalCapabilities:()=>throw new InvalidOperationException());
        var failedReady=await failed.DispatchAsync(BridgeEnvelope.Request("host.ready",Id(),0,new{}));
        Check(Caps(failedReady).SequenceEqual(new[]{"host.lifecycle"}),"failed current-owner capability observation retains base and adds no protocol");
        Console.WriteLine("PASS real local→SCM Native installation dynamic Ready, disabled/old/exception and late-retirement capability boundaries");
    }
    private sealed class RuntimeReadyNoNetwork:HttpMessageHandler {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request,CancellationToken token)=>throw new InvalidOperationException("Ready must never contact a service");
    }
}
