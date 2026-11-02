using System.Reflection;
using StarBridge.HostRuntime;
using StarBridge.NativeBridge;

internal static partial class AccountSessionRestoreTests
{
    // Internal regression process only. Controlled OAuth and actual Native
    // runtime routing; no production configuration, UI, or network endpoints.
    internal static async Task ImageCacheRuntimeWorker(string root)
    {
        await using var fixture = new ImageCacheFixture(root);
        await fixture.Authenticate();
        var codec = typeof(BridgeEnvelope).Assembly.GetType("StarBridge.NativeBridge.BridgeWireCodec", true)!;
        var read = codec.GetMethod("ReadFrameAsync", BindingFlags.NonPublic | BindingFlags.Static)!;
        var write = codec.GetMethod("WriteFrameAsync", BindingFlags.NonPublic | BindingFlags.Static)!;
        using var input = Console.OpenStandardInput();
        using var output = Console.OpenStandardOutput();
        await Send(BridgeEnvelope.Event("host.ready", fixture.Native.Generation, 1,
            new { capabilities = AccountBridgeRuntime.AdvertisedCapabilities }));
        while (await (ValueTask<BridgeEnvelope?>)read.Invoke(null, [input, CancellationToken.None])! is { } request)
        {
            var result = await fixture.Router.DispatchAsync(request);
            await Send(result.Response);
        }
        async Task Send(BridgeEnvelope envelope)
        {
            await (ValueTask)write.Invoke(null, [output, envelope, CancellationToken.None])!;
            await output.FlushAsync();
        }
    }
}
