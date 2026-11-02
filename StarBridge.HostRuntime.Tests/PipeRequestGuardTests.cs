using System.Text.Json;
using StarBridge.HostRuntime;
using StarBridge.NativeBridge;

/// <summary>Build 44: clearing a hall filter threw InvalidDataException out of one request; the pipe
/// session ended, the Host restarted and the client dropped its signed-in state. One request's
/// unexpected failure must only ever answer that request.</summary>
internal static class PipeRequestGuardTests
{
    private const string PrivateMarker = "private-exception-marker";

    private sealed class Probe : IBridgeRequestDispatcher
    {
        public event Action<BridgeEnvelope>? EventReady { add { } remove { } }
        public async ValueTask<BridgeDispatchBatch> DispatchAsync(BridgeEnvelope request, CancellationToken cancellationToken = default)
        {
            await Task.Yield();
            return request.Name switch
            {
                "marketplace.invalidData" => throw new InvalidDataException(PrivateMarker),
                "probe.transition" => await NativeHostPipeServer.KeepEventsOnFailureAsync(request,
                    new(BridgeEnvelope.Response(request, new { schemaVersion = 1 }), [BridgeEnvelope.Event("account.changed", 1, 1, new { schemaVersion = 1 })]),
                    () => throw new InvalidDataException(PrivateMarker)),
                "probe.nullValue" => throw new NullReferenceException(PrivateMarker),
                "probe.otherCancel" => throw new OperationCanceledException(PrivateMarker),
                "probe.protocol" => throw new BridgeProtocolException(BridgeErrorCodes.InvalidEnvelope, PrivateMarker),
                "probe.scm-v1:0123456789abcdef" => throw new InvalidDataException(PrivateMarker),
                _ => new BridgeDispatchBatch(BridgeEnvelope.Response(request, new { schemaVersion = 1 }), [])
            };
        }
        public void Dispose() { }
    }

    internal static async Task Run()
    {
        var previous = HostDataRoot.CurrentRoot;
        var root = Directory.CreateTempSubdirectory("pipe-request-guard-").FullName;
        HostDataRoot.UsePreparedRoot(root);
        try
        {
            var pair = InMemoryBridgeConnection.CreatePair();
            using var dispatcher = new Probe();
            using var lifetime = new CancellationTokenSource(TimeSpan.FromSeconds(10));
            var server = NativeHostPipeServer.ServeConnectionAsync(pair.Right, dispatcher, lifetime.Token);
            var responses = pair.Left.ReadAllAsync(lifetime.Token).GetAsyncEnumerator(lifetime.Token);
            async Task<BridgeEnvelope> Send(string name)
            {
                var id = Guid.NewGuid().ToString("N");
                await pair.Left.SendAsync(BridgeEnvelope.Request(name, id, 1, new { schemaVersion = 1 }), lifetime.Token);
                if (!await responses.MoveNextAsync()) throw new InvalidOperationException("The pipe session ended on " + name);
                Check(responses.Current.CorrelationId == id, "the response answers its own request");
                return responses.Current;
            }
            foreach (var name in new[] { "marketplace.invalidData", "probe.nullValue", "probe.otherCancel", "probe.scm-v1:0123456789abcdef" })
            {
                var failed = await Send(name);
                Check(failed.Status == "error" && failed.Error?.Code == BridgeErrorCodes.HostError && failed.Error?.Retryable == false,
                    "an unexpected failure answers with a host error: " + name);
                Check(!JsonSerializer.Serialize(failed).Contains(PrivateMarker, StringComparison.Ordinal), "the response carries no exception text");
                Check((await Send("probe.ok")).Status == "ok", "the session keeps serving after " + name);
            }
            var log = Path.Combine(root, "scm-auth-diagnostics.log");
            var lines = File.ReadAllLines(log);
            Check(lines.Length == 4 && lines.All(line => line.Contains("step=bridge-dispatch outcome=failed", StringComparison.Ordinal)),
                "each failure leaves one diagnostic line");
            Check(lines[0].EndsWith("area=marketplace exceptionType=InvalidDataException", StringComparison.Ordinal) &&
                lines[1].EndsWith("area=other exceptionType=NullReferenceException", StringComparison.Ordinal) &&
                lines[3].EndsWith("area=other exceptionType=InvalidDataException", StringComparison.Ordinal),
                "the diagnostic names a fixed area and the exception type; request names are not logged");
            Check(!File.ReadAllText(log).Contains(PrivateMarker, StringComparison.Ordinal), "diagnostics exclude exception text");

            // Review: decoration failing after an account transition keeps the transition's event.
            var transition = await Send("probe.transition");
            Check(transition.Status == "error" && transition.Error?.Code == BridgeErrorCodes.HostError, "the failed decoration answers with a host error");
            if (!await responses.MoveNextAsync()) throw new InvalidOperationException("The pipe session ended after the transition");
            Check(responses.Current.Name == "account.changed", "the account event still reaches the client");
            Check((await Send("probe.ok")).Status == "ok", "the session keeps serving after the transition");

            // A broken or malformed client still ends its own lease, as before.
            await pair.Left.SendAsync(BridgeEnvelope.Request("probe.protocol", "protocol", 1, new { schemaVersion = 1 }), lifetime.Token);
            var ended = false;
            try { await server.WaitAsync(TimeSpan.FromSeconds(5)); ended = true; }
            catch (BridgeProtocolException) { ended = true; }
            Check(ended, "a protocol failure still ends its own lease");
            Console.WriteLine("PASS pipe request guard: unexpected failures answer alone, session and Host survive, one safe diagnostic");
        }
        finally
        {
            HostDataRoot.UsePreparedRoot(previous);
            try { Directory.Delete(root, true); } catch (IOException) { }
        }
    }

    private static void Check(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException(message);
    }
}
