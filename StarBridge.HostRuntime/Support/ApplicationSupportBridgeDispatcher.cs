namespace StarBridge.HostRuntime.Support;

using StarBridge.NativeBridge;
using System.Text.Json;

public sealed class ApplicationSupportBridgeDispatcher : IBridgeRequestDispatcher
{
    public static IReadOnlyList<string> AdvertisedCapabilities { get; } =
        ["diagnostics.safeSummary", "diagnostics.openDataDirectory", "diagnostics.dataLocation", "diagnostics.clearImageCache", "diagnostics.openInstalledApps", "diagnostics.flutterInstallation"];

    private readonly IApplicationSupportInspector _inspector;
    private readonly IApplicationSupportActions _actions;
    private readonly Func<long> _generation;
    private readonly SemaphoreSlim _gate = new(1, 1);
    private bool _disposed;
    private readonly Uri? _relayUri;
    private FlutterInstallationMaintenance? _installation;
    private long _installationGeneration;

    public ApplicationSupportBridgeDispatcher(
        string dataRoot,
        string? applicationExecutablePath,
        Func<string?>? gameLogPath = null,
        Func<long>? generation = null,
        Uri? relayUri = null)
        : this(CreateWindowsRuntime(
            dataRoot,
            applicationExecutablePath,
            gameLogPath), generation)
    {
        _relayUri = relayUri;
        _installation = new FlutterInstallationMaintenance(applicationExecutablePath);
    }

    private ApplicationSupportBridgeDispatcher(
        WindowsApplicationSupportInspector runtime,
        Func<long>? generation)
        : this(runtime, runtime, generation)
    {
    }

    internal ApplicationSupportBridgeDispatcher(
        IApplicationSupportInspector inspector,
        Func<long>? generation = null)
        : this(inspector, UnavailableApplicationSupportActions.Instance, generation)
    {
    }

    internal ApplicationSupportBridgeDispatcher(
        IApplicationSupportInspector inspector,
        IApplicationSupportActions actions,
        Func<long>? generation = null)
    {
        _inspector = inspector ?? throw new ArgumentNullException(nameof(inspector));
        _actions = actions ?? throw new ArgumentNullException(nameof(actions));
        _generation = generation ?? (() => 0);
    }

    public event Action<BridgeEnvelope>? EventReady
    {
        add { }
        remove { }
    }

    public async ValueTask<BridgeDispatchBatch> DispatchAsync(
        BridgeEnvelope request,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(request);
        await _gate.WaitAsync(cancellationToken);
        try
        {
            Validate(request);
            if (request.Name == "diagnostics.flutterInstallation")
            {
                var plan = (_installation ?? throw new InvalidOperationException()).Prepare();
                _installationGeneration = request.SessionGeneration;
                return new(BridgeEnvelope.Response(request, new { schemaVersion = 1, ticket = plan.Ticket,
                    mode = plan.Mode, directory = plan.Directory, canUninstall = plan.CanUninstall,
                    canClean = plan.CanClean }, preserveRequestAccountContext: false), []);
            }
            if (request.Name == "diagnostics.flutterInstallationExecute")
            {
                if (_installationGeneration != request.SessionGeneration) throw new InvalidOperationException();
                (_installation ?? throw new InvalidOperationException()).Execute(
                    request.Payload.GetProperty("ticket").GetString()!, request.Payload.GetProperty("action").GetString()!);
                return new(BridgeEnvelope.Response(request, new { schemaVersion = 1, completed = true },
                    preserveRequestAccountContext: false), []);
            }
            if (request.Name == ApplicationSupportRequestNames.ClearImageCache)
                return new(BridgeEnvelope.Response(request, new { schemaVersion = 1, count = _actions.ClearImageCache() }, preserveRequestAccountContext: false), []);
            if (request.Name == ApplicationSupportRequestNames.OpenInstalledApps)
            {
                _actions.OpenInstalledApps();
                return new(BridgeEnvelope.Response(request, new { schemaVersion = 1, opened = true }, preserveRequestAccountContext: false), []);
            }
            if (request.Name == ApplicationSupportRequestNames.GetDataLocation)
            {
                var location = (_inspector as IApplicationDataLocationReader)?.GetDataLocation()
                    ?? throw new InvalidOperationException();
                return new BridgeDispatchBatch(BridgeEnvelope.Response(request,
                    new { schemaVersion = ApplicationSupportSchema.Version, path = location.Path, exists = location.Exists },
                    preserveRequestAccountContext: false), []);
            }
            if (request.Name == ApplicationSupportRequestNames.OpenDataDirectory)
            {
                try
                {
                    _actions.OpenDataDirectory();
                    return new BridgeDispatchBatch(
                        BridgeEnvelope.Response(
                            request,
                            new { schemaVersion = ApplicationSupportSchema.Version, opened = true },
                            preserveRequestAccountContext: false),
                        []);
                }
                catch
                {
                    return Error(
                        request,
                        ApplicationSupportStableErrors.OpenFailed,
                        retryable: true);
                }
            }

            var snapshot = _inspector.Inspect();
            if (_relayUri != null)
                snapshot = snapshot with { Connection = await DiagnosticConnectionProbe.CheckAsync(_relayUri, cancellationToken) };
            return new BridgeDispatchBatch(ToResponse(request, snapshot), []);
        }
        catch (BridgeProtocolException exception)
        {
            return Error(request, exception.Code);
        }
        catch (OperationCanceledException)
        {
            return new BridgeDispatchBatch(BridgeEnvelope.CancelledResponse(request), []);
        }
        catch
        {
            return Error(
                request,
                ApplicationSupportStableErrors.InspectionFailed,
                retryable: true);
        }
        finally
        {
            _gate.Release();
        }
    }

    private void Validate(BridgeEnvelope request)
    {
        BridgeEnvelopeValidator.ValidateWireShape(request);
        BridgeEnvelopeValidator.RequireCurrentVersion(request);
        if (request.MessageType != BridgeMessageTypes.Request ||
            request.Name is not (ApplicationSupportRequestNames.Inspect or
                ApplicationSupportRequestNames.OpenDataDirectory or ApplicationSupportRequestNames.GetDataLocation or
                ApplicationSupportRequestNames.ClearImageCache or ApplicationSupportRequestNames.OpenInstalledApps or
                "diagnostics.flutterInstallation" or "diagnostics.flutterInstallationExecute"))
        {
            throw new BridgeProtocolException(
                BridgeErrorCodes.InvalidEnvelope,
                "Application support dispatcher only accepts inspection requests.");
        }
        if (request.SessionGeneration != _generation())
        {
            throw new BridgeStaleGenerationException(
                request.SessionGeneration,
                _generation());
        }
        if (request.AccountContext is not null)
        {
            throw new BridgeProtocolException(
                BridgeErrorCodes.InvalidEnvelope,
                "Application support inspection must not include account context.");
        }
        if (request.Name == "diagnostics.flutterInstallationExecute")
        {
            var p = request.Payload;
            if (p.ValueKind != JsonValueKind.Object || p.EnumerateObject().Count() != 3 ||
                !p.TryGetProperty("schemaVersion", out var schema) || !schema.TryGetInt32(out var number) || number != 1 ||
                !p.TryGetProperty("ticket", out var ticket) || ticket.ValueKind != JsonValueKind.String ||
                !Guid.TryParseExact(ticket.GetString(), "N", out _) ||
                !p.TryGetProperty("action", out var action) || action.ValueKind != JsonValueKind.String ||
                action.GetString() is not ("clean" or "uninstall"))
                throw new BridgeProtocolException(BridgeErrorCodes.InvalidEnvelope, "Invalid installation action.");
            return;
        }
        if (request.Payload.ValueKind != JsonValueKind.Object ||
            request.Payload.EnumerateObject().Count() != 1 ||
            request.Payload.EnumerateObject().Any(property => property.Name != "schemaVersion") ||
            !request.Payload.TryGetProperty("schemaVersion", out var version) ||
            version.ValueKind != JsonValueKind.Number ||
            !version.TryGetInt32(out var value) ||
            value != ApplicationSupportSchema.Version)
        {
            throw new BridgeProtocolException(
                BridgeErrorCodes.InvalidEnvelope,
                "Application support schema version is invalid.");
        }
    }

    private static BridgeEnvelope ToResponse(
        BridgeEnvelope request,
        ApplicationSupportSnapshot snapshot) =>
        BridgeEnvelope.Response(
            request,
            new
            {
                schemaVersion = ApplicationSupportSchema.Version,
                hasIssues = snapshot.HasIssues,
                hasUnavailableChecks = snapshot.HasUnavailableChecks,
                checks = new
                {
                    dataDirectory = Basic(snapshot.DataDirectory),
                    gameLog = Basic(snapshot.GameLog),
                    connection = snapshot.Connection == null ? null : Basic(snapshot.Connection),
                    startup = new
                    {
                        state = snapshot.Startup.State,
                        detail = snapshot.Startup.Detail,
                        registered = snapshot.Startup.Registered,
                        targetExists = snapshot.Startup.TargetExists,
                        targetsCurrentExecutable = snapshot.Startup.TargetsCurrentExecutable
                    },
                    installation = new
                    {
                        state = snapshot.Installation.State,
                        detail = snapshot.Installation.Detail,
                        mode = snapshot.Installation.Mode,
                        currentInstallations = snapshot.Installation.CurrentInstallations,
                        otherInstallations = snapshot.Installation.OtherInstallations,
                        orphanedRegistrations = snapshot.Installation.OrphanedRegistrations,
                        scanWarnings = snapshot.Installation.ScanWarnings
                    }
                }
            },
            preserveRequestAccountContext: false);

    private static object Basic(ApplicationSupportCheck check) => new
    {
        state = check.State,
        detail = check.Detail
    };

    private static BridgeDispatchBatch Error(
        BridgeEnvelope request,
        string code,
        bool retryable = false) =>
        new(
            BridgeEnvelope.ErrorResponse(
                request,
                new BridgeError(code, "Application support inspection failed.", retryable)),
            []);

    private static WindowsApplicationSupportInspector CreateWindowsRuntime(
        string dataRoot,
        string? applicationExecutablePath,
        Func<string?>? gameLogPath) =>
        new(dataRoot, applicationExecutablePath, gameLogPath);

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;
        _gate.Dispose();
    }

    private sealed class UnavailableApplicationSupportActions : IApplicationSupportActions
    {
        internal static UnavailableApplicationSupportActions Instance { get; } = new();

        public void OpenDataDirectory() => throw new InvalidOperationException();
    }
}
