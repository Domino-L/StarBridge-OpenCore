namespace StarBridge.HostRuntime;

using StarBridge.NativeBridge;
using System.IO;
using System.Threading.Channels;

/// <summary>
/// Owns connection replacement, bounded event delivery and response-before-
/// event ordering for one headless Native Host. Callers only provide the pipe
/// name and one feature dispatcher.
/// </summary>
public sealed class NativeHostPipeServer(
    string pipeName,
    IBridgeRequestDispatcher dispatcher) : IAsyncDisposable
{
    // Workers are async tasks, not threads. An SCM session runs account requests
    // one at a time, and a request waiting at that gate still holds its worker.
    // With four workers a startup burst parked three of them there, so local reads
    // waited seconds and the account gate could order only what it had been
    // handed (DL-137 device traces 2026-10-21). Domains keep their own gates.
    internal const int RequestWorkerCount = 16;
    private const int ActivityWaitWorkerCount = 3;
    private const int ActivityWaitQueuedCapacity = 2;
    internal const int ActivityWaitCapacity = ActivityWaitWorkerCount + ActivityWaitQueuedCapacity;

    private readonly NamedPipeBridgeListener _listener = new(pipeName);
    private readonly IBridgeRequestDispatcher _dispatcher = dispatcher ??
        throw new ArgumentNullException(nameof(dispatcher));
    private int _disposed;

    public async Task RunAsync(CancellationToken cancellationToken = default)
    {
        ObjectDisposedException.ThrowIf(Volatile.Read(ref _disposed) != 0, this);
        while (!cancellationToken.IsCancellationRequested)
        {
            IBridgeConnection? connection = null;
            try
            {
                connection = await _listener.AcceptAsync(cancellationToken).ConfigureAwait(false);
                await ServeConnectionAsync(connection, _dispatcher, cancellationToken).ConfigureAwait(false);
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                return;
            }
            catch (Exception exception) when (exception is IOException or BridgeProtocolException)
            {
                // A broken or malformed client only ends its own lease. The
                // next Flutter process can reconnect to a fresh pipe instance.
            }
            finally
            {
                if (connection is not null)
                {
                    await connection.DisposeAsync().ConfigureAwait(false);
                }
            }
        }
    }

    public static async Task ServeConnectionAsync(
        IBridgeConnection connection,
        IBridgeRequestDispatcher dispatcher,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(connection);
        ArgumentNullException.ThrowIfNull(dispatcher);
        using var outgoing = new BridgeConnectionWriter(connection);

        using var connectionLifetime = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        await using var readCancellation = new Lifecycle.BridgeReadCancellation(connectionLifetime.Token);
        var events = Channel.CreateBounded<BridgeEnvelope>(new BoundedChannelOptions(
            BridgeProtocol.DefaultQueueCapacity)
        {
            FullMode = BoundedChannelFullMode.Wait,
            SingleReader = true,
            SingleWriter = false
        });
        var requests = Channel.CreateBounded<BridgeEnvelope>(new BoundedChannelOptions(
            BridgeProtocol.DefaultQueueCapacity)
        {
            // The reader loop intentionally uses TryWrite so a saturated Host
            // returns bridge.backpressure immediately instead of silently
            // dropping a request or waiting forever behind long-lived work.
            FullMode = BoundedChannelFullMode.Wait,
            SingleReader = false,
            SingleWriter = true
        });
        var controls = Channel.CreateUnbounded<BridgeEnvelope>(new UnboundedChannelOptions
        {
            SingleReader = true,
            SingleWriter = true
        });
        // This audited endpoint performs bounded local IO only. A full set of
        // ordinary workers waiting for private HTTP must not delay local paint.
        var displayReads = Channel.CreateBounded<BridgeEnvelope>(new BoundedChannelOptions(8)
        {
            FullMode = BoundedChannelFullMode.Wait, SingleReader = true, SingleWriter = true
        });
        // Menu interaction is bounded local IO (see BridgeRequestPolicy.IsMenuInteraction).
        // One serial worker keeps its order and keeps it out of the ordinary pool.
        var menuRequests = Channel.CreateBounded<BridgeEnvelope>(new BoundedChannelOptions(8)
        {
            FullMode = BoundedChannelFullMode.Wait, SingleReader = true, SingleWriter = true
        });
        // Social, community and official-fleet each fit concurrently: three
        // active workers plus two removable queued slots. Excess is rejected;
        // ordinary requests and control keep their separate workers.
        var activityWaits = new Lifecycle.BridgeActivityWaitQueue(ActivityWaitWorkerCount, ActivityWaitQueuedCapacity);

        void QueueEvent(BridgeEnvelope envelope)
        {
            if (!events.Writer.TryWrite(envelope))
            {
                connectionLifetime.Cancel();
            }
        }

        dispatcher.EventReady += QueueEvent;
        var eventPump = PumpEventsAsync(
            outgoing,
            events.Reader,
            connectionLifetime);
        var requestPumps = Enumerable
            .Range(0, RequestWorkerCount)
            .Select(_ => PumpRequestsAsync(
                outgoing,
                dispatcher,
                requests.Reader,
                connectionLifetime, readCancellation))
            .ToArray();
        var controlPump = PumpRequestsAsync(
            outgoing,
            dispatcher,
            controls.Reader,
            connectionLifetime, readCancellation);
        var displayPump = PumpRequestsAsync(outgoing, dispatcher, displayReads.Reader, connectionLifetime, readCancellation);
        var menuPump = PumpRequestsAsync(outgoing, dispatcher, menuRequests.Reader, connectionLifetime, readCancellation);
        var activityPumps = Enumerable.Range(0, ActivityWaitWorkerCount)
            .Select(_ => PumpRequestsAsync(outgoing, dispatcher, activityWaits, connectionLifetime, readCancellation))
            .ToArray();
        try
        {
            await foreach (var request in connection
                .ReadAllAsync(connectionLifetime.Token)
                .WithCancellation(connectionLifetime.Token)
                .ConfigureAwait(false))
            {
                if (readCancellation.Cancel(request))
                {
                    foreach (var cancelled in activityWaits.RemoveCancelled(readCancellation.TokenFor))
                    {
                        await readCancellation.CompleteAsync(cancelled).ConfigureAwait(false);
                        await outgoing.SendAsync(BridgeEnvelope.CancelledResponse(cancelled), connectionLifetime.Token).ConfigureAwait(false);
                    }
                    await outgoing.SendAsync(BridgeEnvelope.Response(request, new { cancelled = true }), connectionLifetime.Token).ConfigureAwait(false);
                    continue;
                }
                if (BridgeRequestPolicy.IsOutOfBandControl(request.Name))
                {
                    if (!controls.Writer.TryWrite(request))
                    {
                        connectionLifetime.Cancel();
                    }

                    continue;
                }

                var queue = request.Name == Account.AccountBridgeRequestNames.ReadProfileDisplayCache ? displayReads
                    : BridgeRequestPolicy.IsMenuInteraction(request.Name) ? menuRequests : requests;
                if (!readCancellation.Register(request))
                {
                    await outgoing.SendAsync(BridgeEnvelope.ErrorResponse(request,
                        new BridgeError(BridgeErrorCodes.Backpressure, "Native read capacity is exhausted.", true)), connectionLifetime.Token).ConfigureAwait(false);
                    continue;
                }
                if (!(BridgeRequestPolicy.IsActivityWait(request.Name) ? activityWaits.TryWrite(request) : queue.Writer.TryWrite(request)))
                {
                    await readCancellation.CompleteAsync(request).ConfigureAwait(false);
                    await outgoing.SendAsync(
                        BridgeEnvelope.ErrorResponse(
                            request,
                            new BridgeError(
                                BridgeErrorCodes.Backpressure,
                                "Native Host request capacity is exhausted.",
                                true)),
                        connectionLifetime.Token).ConfigureAwait(false);
                }
            }
        }
        finally
        {
            dispatcher.EventReady -= QueueEvent;
            events.Writer.TryComplete();
            requests.Writer.TryComplete();
            controls.Writer.TryComplete();
            activityWaits.Complete();
            displayReads.Writer.TryComplete();
            menuRequests.Writer.TryComplete();
            connectionLifetime.Cancel();
            try
            {
                await Task.WhenAll(requestPumps.Concat(activityPumps).Append(displayPump).Append(menuPump).Append(controlPump).Append(eventPump))
                    .ConfigureAwait(false);
            }
            catch (OperationCanceledException)
            {
                // Expected when the client disconnects or the Host exits.
            }
        }
    }

    private static async Task PumpRequestsAsync(
        BridgeConnectionWriter outgoing,
        IBridgeRequestDispatcher dispatcher,
        ChannelReader<BridgeEnvelope> requests,
        CancellationTokenSource connectionLifetime,
        Lifecycle.BridgeReadCancellation readCancellation)
    {
        try
        {
            await foreach (var request in requests
                .ReadAllAsync(connectionLifetime.Token)
                .ConfigureAwait(false))
            {
                try
                {
                    var token = readCancellation.TokenFor(request);
                    BridgeDispatchBatch batch;
                    try {
                        batch = token.IsCancellationRequested
                            ? new(BridgeEnvelope.CancelledResponse(request), [])
                            : await dispatcher.DispatchAsync(request, token).ConfigureAwait(false);
                    } catch (OperationCanceledException) when (token.IsCancellationRequested && !connectionLifetime.IsCancellationRequested) {
                        batch = new(BridgeEnvelope.CancelledResponse(request), []);
                    } catch (Exception exception) when (!connectionLifetime.IsCancellationRequested && exception is not BridgeProtocolException) {
                        // One request's unexpected failure answers that request alone. It must not
                        // end the pipe session: that restarts the Host and drops the signed-in state.
                        batch = new(UnexpectedFailure(request, exception), []);
                    }
                    if (token.IsCancellationRequested)
                        batch = new(BridgeEnvelope.CancelledResponse(request), batch.Events);
                    await outgoing
                        .SendAsync(batch.Response, connectionLifetime.Token)
                        .ConfigureAwait(false);
                    foreach (var envelope in batch.Events)
                        await outgoing.SendAsync(envelope, connectionLifetime.Token).ConfigureAwait(false);
                }
                finally
                {
                    await readCancellation.CompleteAsync(request).ConfigureAwait(false);
                    if (requests is Lifecycle.BridgeActivityWaitQueue activityLane) activityLane.CompleteRequest();
                }
            }
        }
        catch
        {
            connectionLifetime.Cancel();
            throw;
        }
    }

    private static readonly HashSet<string> DiagnosticAreas = new(StringComparer.Ordinal)
    {
        "account", "accountSafety", "bridge", "communities", "diagnostics", "eventSharing", "friends", "gameIdentity", "hangar",
        "host", "marketplace", "menuHotkey", "notificationAudio", "notificationInbox", "notificationPolicies", "notificationSettings",
        "officialFleet", "overlayRoster", "overlayScenes", "partyRooms", "personalProfile", "presence", "privacy", "profile",
        "scmAchievements", "social", "tradeProfile", "users"
    };

    /// <summary>A batch whose response decoration failed still delivers its events: a real account
    /// transition has already happened and the client must hear about it.</summary>
    internal static async ValueTask<BridgeDispatchBatch> KeepEventsOnFailureAsync(BridgeEnvelope request,
        BridgeDispatchBatch batch, Func<ValueTask<BridgeDispatchBatch>> decorate)
    {
        try { return await decorate().ConfigureAwait(false); }
        catch (Exception failure) when (failure is not (OperationCanceledException or BridgeProtocolException))
        { return batch with { Response = UnexpectedFailure(request, failure) }; }
    }

    internal static BridgeEnvelope UnexpectedFailure(BridgeEnvelope request, Exception exception)
    {
        // A fixed area and the type only: request names are not trusted for logs, and
        // exception text can carry server content or private values.
        var separator = request.Name.IndexOf('.');
        var area = separator > 0 && DiagnosticAreas.Contains(request.Name[..separator]) ? request.Name[..separator] : "other";
        Auth.ScmAuthDiagnostics.Write("bridge", "bridge-dispatch", "failed",
            $"area={area} exceptionType={exception.GetType().Name}");
        return BridgeEnvelope.ErrorResponse(request,
            new BridgeError(BridgeErrorCodes.HostError, "The Native Host could not complete this request.", false));
    }

    private static async Task PumpEventsAsync(
        BridgeConnectionWriter outgoing,
        ChannelReader<BridgeEnvelope> events,
        CancellationTokenSource connectionLifetime)
    {
        try
        {
            await foreach (var envelope in events
                .ReadAllAsync(connectionLifetime.Token)
                .ConfigureAwait(false))
            {
                await outgoing
                    .SendAsync(envelope, connectionLifetime.Token)
                    .ConfigureAwait(false);
            }
        }
        catch
        {
            connectionLifetime.Cancel();
            throw;
        }
    }

    public ValueTask DisposeAsync()
    {
        if (Interlocked.Exchange(ref _disposed, 1) == 0)
        {
            _dispatcher.Dispose();
        }

        return ValueTask.CompletedTask;
    }
}
