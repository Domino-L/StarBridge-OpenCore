using System.Reflection;
using StarBridge.HostRuntime.Account;
using StarBridge.NativeBridge;

internal static partial class S2CompatibilityReadTests
{
    private static readonly BindingFlags OwnerFieldsR3 = BindingFlags.Instance | BindingFlags.NonPublic;
    private static object? OwnerFieldR3(ScmAccountBridgeHost host, string name) =>
        typeof(ScmAccountBridgeHost).GetField(name, OwnerFieldsR3)!.GetValue(host);

    private static void RetryableReadR3(Exception? error, string message) =>
        Check(error is AccountBridgeHostException failure &&
            failure.Code == AccountBridgeStableErrors.CompatibilityReadUnavailable && failure.Retryable, message);

    private static async Task VerifyOwnerCancellationLifetimeR2()
    {
        foreach (var mode in new[] { "cancel", "late-success", "late-io" })
        foreach (var priorFailure in new[] { false, true })
            await VerifyInitiatorCancellationR3(mode, priorFailure);
        await VerifyJoinedCancellationR3();
        foreach (var mode in new[] { "generation", "identity", "dispose" })
            await VerifyRetiredReadR3(mode);
        Console.WriteLine("PASS OWNER-BINDING-073-R3 initiator IO lifetime, retryable joiners, unchanged expiry and retired replies");
    }

    private static async Task VerifyInitiatorCancellationR3(string mode, bool priorFailure)
    {
        using var f = new OwnerFixture073();
        var host = f.Host;
        var owner = host.CurrentContext!;
        await host.GetCompatibilityStateAsync(owner, default);
        if (priorFailure)
        {
            f.Coordinator.Failure = true;
            await ReadUnavailable073(host);
            f.Coordinator.Failure = false;
        }
        var binding = OwnerFieldR3(host, "_localOwnerBinding");
        var failure = OwnerFieldR3(host, "_localOwnerTransportFailure");
        var resets = f.Relay.Resets;
        f.Clock.Advance(TimeSpan.FromMinutes(priorFailure ? 29 : 2));
        var pending = new TaskCompletionSource<AccountBridgeCompatibilityProjection>(TaskCreationOptions.RunContinuationsAsynchronously);
        f.Coordinator.Pending = pending;
        f.Coordinator.HonorReadCancellation = mode == "cancel";
        using var cancellation = new CancellationTokenSource();
        var first = host.GetCompatibilityStateAsync(owner, cancellation.Token);
        var physicalToken = f.Coordinator.LastReadToken;
        var joined = host.GetCompatibilityStateAsync(owner, default);
        try
        {
            cancellation.Cancel();
            Check(physicalToken.IsCancellationRequested, "Initiator cancellation must reach its physical IO token");
            if (mode != "cancel")
            {
                Check(!first.IsCompleted && !joined.IsCompleted,
                    "Initiator and joiner retain the original physical IO until its actual exit");
                if (mode == "late-io") pending.SetException(new IOException("Synthetic cancellation IO"));
                else pending.SetResult(Coordinator.LinkedProjection);
            }
            var firstResult = await CaptureRead073(first.WaitAsync(TimeSpan.FromSeconds(2)));
            var joinedResult = await CaptureRead073(joined.WaitAsync(TimeSpan.FromSeconds(2)));
            Check(firstResult.Error is OperationCanceledException, "The initiating request keeps cancellation semantics");
            RetryableReadR3(joinedResult.Error, "An uncancelled joiner must receive retryable compatibility unavailability");
            Check(ReferenceEquals(binding, OwnerFieldR3(host, "_localOwnerBinding")) &&
                ReferenceEquals(failure, OwnerFieldR3(host, "_localOwnerTransportFailure")) && f.Relay.Resets == resets,
                "Cancellation cannot clear or refresh ownership, record transport failure or reset the reader");
            Check(host.ResolveLocalDataOwner(owner) == f.LegacyOwner, "Cancellation preserves the unexpired confirmed owner");
            f.Clock.Advance(TimeSpan.FromMinutes(1));
            OwnerUnavailable073(host, "Cancellation cannot extend the original three-minute or thirty-minute deadline");
            f.Coordinator.Pending = null;
            await host.GetCompatibilityStateAsync(owner, default);
            Check(host.ResolveLocalDataOwner(owner) == f.LegacyOwner, "A subsequent successful request can restore ownership");
        }
        finally
        {
            pending.TrySetResult(Coordinator.LinkedProjection);
            await Task.WhenAll(CaptureRead073(first), CaptureRead073(joined));
        }
    }

    private static async Task VerifyJoinedCancellationR3()
    {
        using var f = new OwnerFixture073();
        var host = f.Host;
        var pending = new TaskCompletionSource<AccountBridgeCompatibilityProjection>(TaskCreationOptions.RunContinuationsAsynchronously);
        f.Coordinator.Pending = pending;
        f.Coordinator.HonorReadCancellation = true;
        using var cancellation = new CancellationTokenSource();
        var first = host.GetCompatibilityStateAsync(host.CurrentContext!, default);
        var cancelled = host.GetCompatibilityStateAsync(host.CurrentContext!, cancellation.Token);
        var joined = host.GetCompatibilityStateAsync(host.CurrentContext!, default);
        try
        {
            cancellation.Cancel();
            var outcome = await CaptureRead073(cancelled.WaitAsync(TimeSpan.FromSeconds(2)));
            Check(outcome.Error is OperationCanceledException && !first.IsCompleted && !joined.IsCompleted &&
                !f.Coordinator.LastReadToken.IsCancellationRequested,
                "A joiner cancels only its own wait without cancelling physical IO or other callers");
            pending.SetResult(Coordinator.LinkedProjection);
            var results = await Task.WhenAll(first, joined).WaitAsync(TimeSpan.FromSeconds(2));
            Check(ReferenceEquals(results[0], results[1]) && results[0].IdentityState == "linked" && f.Coordinator.Reads == 1,
                "Initiator and remaining joiner receive the same result from one physical read");
        }
        finally
        {
            pending.TrySetResult(Coordinator.LinkedProjection);
            await Task.WhenAll(CaptureRead073(first), CaptureRead073(cancelled), CaptureRead073(joined));
        }
    }

    private static async Task VerifyRetiredReadR3(string mode)
    {
        using var f = new OwnerFixture073();
        var host = f.Host;
        var pending = new TaskCompletionSource<AccountBridgeCompatibilityProjection>(TaskCreationOptions.RunContinuationsAsynchronously);
        f.Coordinator.Pending = pending; // Ignores cancellation and returns a late success.
        var first = host.GetCompatibilityStateAsync(host.CurrentContext!, default);
        var joined = host.GetCompatibilityStateAsync(host.CurrentContext!, default);
        try
        {
            if (mode == "dispose") host.Dispose();
            else
            {
                var publish = typeof(ScmAccountBridgeHost).GetMethod("PublishSession", OwnerFieldsR3)!;
                publish.Invoke(host, [f.Session with { Subject = mode == "identity" ? "replacement-subject" : f.Session.Subject },
                    false, null, false, null, null, null, null]);
                f.Coordinator.Pending = null;
                f.Coordinator.Linked = false;
                await host.GetCompatibilityStateAsync(host.CurrentContext!, default);
            }
            var binding = OwnerFieldR3(host, "_localOwnerBinding");
            pending.SetResult(Coordinator.LinkedProjection);
            var outcomes = await Task.WhenAll(CaptureRead073(first), CaptureRead073(joined)).WaitAsync(TimeSpan.FromSeconds(2));
            foreach (var outcome in outcomes) RetryableReadR3(outcome.Error, "Retired physical replies must be rejected");
            Check(ReferenceEquals(binding, OwnerFieldR3(host, "_localOwnerBinding")),
                "Generation, identity replacement or disposal must fence late ownership publication");
            if (mode != "dispose") Check(host.ResolveLocalDataOwner(host.CurrentContext!) == host.CurrentContext,
                "A retired linked reply cannot overwrite the replacement session's unlinked owner");
        }
        finally
        {
            pending.TrySetResult(Coordinator.LinkedProjection);
            await Task.WhenAll(CaptureRead073(first), CaptureRead073(joined));
        }
    }
}
