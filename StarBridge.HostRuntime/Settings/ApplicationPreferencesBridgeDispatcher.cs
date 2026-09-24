namespace StarBridge.HostRuntime.Settings;

using StarBridge.NativeBridge;
using System.Text.Json;

public sealed class ApplicationPreferencesBridgeDispatcher : IBridgeRequestDispatcher
{
    public static IReadOnlyList<string> AdvertisedCapabilities { get; } =
        ["applicationPreferences.read", "applicationPreferences.write", "applicationPreferences.menu"];

    private readonly IApplicationPreferencesStore _store;
    private readonly IApplicationStartupRegistration _startupRegistration;
    private readonly Func<long> _generation;
    private readonly SemaphoreSlim _gate = new(1, 1);
    private ApplicationPreferencesReadResult? _current;
    private readonly MenuPreferencesStore? _menu;
    private readonly Lazy<string?> _initialLocale;

    // Native presentation reads the committed immutable snapshot, never a Flutter
    // draft. Before the first request, seed it without applying startup settings.
    public string? CurrentLocaleOverride
    {
        get
        {
            var current = Volatile.Read(ref _current);
            return current is null ? _initialLocale.Value : current.Snapshot.LocaleOverride;
        }
    }
    private bool _disposed;

    public ApplicationPreferencesBridgeDispatcher(
        string dataRoot,
        Func<long>? generation = null,
        string? applicationExecutablePath = null)
        : this(
            new ApplicationPreferencesStore(dataRoot),
            string.IsNullOrWhiteSpace(applicationExecutablePath)
                ? new InertApplicationStartupRegistration()
                : new WindowsApplicationStartupRegistration(applicationExecutablePath),
            generation)
    {
        _menu = new MenuPreferencesStore(dataRoot);
    }

    internal ApplicationPreferencesBridgeDispatcher(
        IApplicationPreferencesStore store,
        Func<long>? generation = null)
        : this(store, new InertApplicationStartupRegistration(), generation)
    {
    }

    internal ApplicationPreferencesBridgeDispatcher(
        IApplicationPreferencesStore store,
        IApplicationStartupRegistration startupRegistration,
        Func<long>? generation = null)
    {
        _store = store ?? throw new ArgumentNullException(nameof(store));
        _startupRegistration = startupRegistration ??
                               throw new ArgumentNullException(nameof(startupRegistration));
        _generation = generation ?? (() => 0);
        _initialLocale = new(() => _store.Load().Snapshot.LocaleOverride);
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
            ValidateRequest(request);
            var response = request.Name switch
            {
                ApplicationPreferencesRequestNames.Get => Read(request),
                ApplicationPreferencesRequestNames.Update => Update(request),
                "applicationPreferences.menu.get" => ReadMenu(request),
                "applicationPreferences.menu.update" => WriteMenu(request),
                _ => throw new BridgeProtocolException(
                    BridgeErrorCodes.InvalidEnvelope,
                    "Unsupported application preferences request.")
            };
            return new BridgeDispatchBatch(response, []);
        }
        catch (ApplicationPreferencesException exception)
        {
            return Error(request, exception.Code, exception.Retryable);
        }
        catch (BridgeProtocolException exception)
        {
            return Error(request, exception.Code);
        }
        catch (OperationCanceledException)
        {
            return new BridgeDispatchBatch(BridgeEnvelope.CancelledResponse(request), []);
        }
        catch (Exception)
        {
            return Error(request, BridgeErrorCodes.Disconnected, retryable: true);
        }
        finally
        {
            _gate.Release();
        }
    }

    private void ValidateRequest(BridgeEnvelope request)
    {
        BridgeEnvelopeValidator.ValidateWireShape(request);
        BridgeEnvelopeValidator.RequireCurrentVersion(request);
        if (request.MessageType != BridgeMessageTypes.Request)
        {
            throw new BridgeProtocolException(
                BridgeErrorCodes.InvalidEnvelope,
                "Application preferences dispatcher only accepts requests.");
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
                "Application preferences must not include account context.");
        }
        RequireSchemaVersion(request.Payload);
    }

    private BridgeEnvelope Read(BridgeEnvelope request)
    {
        RejectUnknownProperties(request.Payload, "schemaVersion");
        return ToResponse(request, Current());
    }

    private BridgeEnvelope ReadMenu(BridgeEnvelope request)
    {
        RejectUnknownProperties(request.Payload, "schemaVersion");
        var value = _menu?.Read() ?? MenuPreferencesStore.Default;
        return MenuResponse(request, value);
    }

    private BridgeEnvelope WriteMenu(BridgeEnvelope request)
    {
        RejectUnknownProperties(request.Payload, "schemaVersion", "expectedRevision", "layout", "settings");
        if (_menu is null) throw new ApplicationPreferencesException("menuPreferences.unavailable", "Storage unavailable");
        var revision = RequireNonNegativeInt64(request.Payload, "expectedRevision");
        var value = _menu.Save(revision, RequireObject(request.Payload, "layout"), RequireObject(request.Payload, "settings"));
        return MenuResponse(request, value);
    }

    private static BridgeEnvelope MenuResponse(BridgeEnvelope request, MenuPreferencesStore.Snapshot value) =>
        BridgeEnvelope.Response(request, new { schemaVersion = 1, revision = value.Revision, layout = value.Layout, settings = value.Settings }, preserveRequestAccountContext: false);

    private BridgeEnvelope Update(BridgeEnvelope request)
    {
        RejectUnknownProperties(
            request.Payload,
            "schemaVersion",
            "expectedRevision",
            "patch");
        var expectedRevision = RequireNonNegativeInt64(request.Payload, "expectedRevision");
        var patch = RequireObject(request.Payload, "patch");
        RejectUnknownProperties(
            patch,
            "localeOverride",
            "appearanceMode",
            "motionPreference",
            "applicationBehavior");
        if (!patch.EnumerateObject().Any())
        {
            throw new BridgeProtocolException(
                BridgeErrorCodes.InvalidEnvelope,
                "Application preferences patch must not be empty.");
        }

        var current = Current();
        if (expectedRevision != current.Snapshot.Revision)
        {
            throw new ApplicationPreferencesException(
                ApplicationPreferencesStableErrors.RevisionConflict,
                "Application preferences changed.",
                retryable: true);
        }

        var next = ApplyPatch(current.Snapshot, patch).Normalize() with
        {
            Revision = checked(current.Snapshot.Revision + 1)
        };
        if (!next.IsSupported())
        {
            throw new ApplicationPreferencesException(
                ApplicationPreferencesStableErrors.InvalidValue,
                "Application preferences contain an unsupported value.");
        }
        var startupRegistrationChanged =
            next.LaunchAtStartup != current.Snapshot.LaunchAtStartup ||
            (!current.Snapshot.StartupChoiceMade && next.StartupChoiceMade);
        if (startupRegistrationChanged &&
            !_startupRegistration.TrySave(next.LaunchAtStartup, current.Snapshot.LaunchAtStartup,
                () => _store.Save(next), out _))
        {
            throw new ApplicationPreferencesException(
                ApplicationPreferencesStableErrors.StartupRegistrationFailed,
                "Windows startup registration could not be updated.",
                retryable: true);
        }

        if (!startupRegistrationChanged) _store.Save(next);
        Volatile.Write(ref _current, new ApplicationPreferencesReadResult(
            next,
            ApplicationPreferencesStorageStates.Ready));
        return ToResponse(request, _current);
    }

    private ApplicationPreferencesReadResult Current()
    {
        if (_current is not null)
        {
            return _current;
        }

        var loaded = _store.Load();
        if (loaded.Snapshot.StartupChoiceMade &&
            !_startupRegistration.TrySetEnabled(
                loaded.Snapshot.LaunchAtStartup,
                out _))
        {
            throw new ApplicationPreferencesException(
                ApplicationPreferencesStableErrors.StartupRegistrationFailed,
                "Windows startup registration could not be synchronized.",
                retryable: true);
        }

        Volatile.Write(ref _current, loaded);
        return loaded;
    }

    private static ApplicationPreferencesSnapshot ApplyPatch(
        ApplicationPreferencesSnapshot current,
        JsonElement patch)
    {
        var localeOverride = current.LocaleOverride;
        if (patch.TryGetProperty("localeOverride", out var localeValue))
        {
            localeOverride = localeValue.ValueKind switch
            {
                JsonValueKind.Null => null,
                JsonValueKind.String when !string.IsNullOrWhiteSpace(localeValue.GetString()) =>
                    localeValue.GetString()!.Trim(),
                _ => throw new BridgeProtocolException(
                    BridgeErrorCodes.InvalidEnvelope,
                    "localeOverride must be null or a non-empty string.")
            };
        }

        var appearanceMode = patch.TryGetProperty("appearanceMode", out var appearanceValue)
            ? RequireNonEmptyString(appearanceValue, "appearanceMode")
            : current.AppearanceMode;
        var motionPreference = patch.TryGetProperty("motionPreference", out var motionValue)
            ? RequireNonEmptyString(motionValue, "motionPreference")
            : current.MotionPreference;

        var launchAtStartup = current.LaunchAtStartup;
        var keepRunningInBackground = current.KeepRunningInBackground;
        var startMinimized = current.StartMinimized;
        var startupChoiceMade = current.StartupChoiceMade;
        var closeBehaviorChoiceMade = current.CloseBehaviorChoiceMade;
        var backgroundHintShown = current.BackgroundHintShown;
        if (patch.TryGetProperty("applicationBehavior", out var behavior))
        {
            if (behavior.ValueKind != JsonValueKind.Object)
            {
                throw new BridgeProtocolException(
                    BridgeErrorCodes.InvalidEnvelope,
                    "applicationBehavior must be an object.");
            }
            RejectUnknownProperties(
                behavior,
                "launchAtStartup",
                "keepRunningInBackground",
                "startMinimized",
                "startupChoiceMade",
                "closeBehaviorChoiceMade",
                "backgroundHintShown");
            launchAtStartup = RequireBoolean(behavior, "launchAtStartup");
            keepRunningInBackground = RequireBoolean(behavior, "keepRunningInBackground");
            startMinimized = RequireBoolean(behavior, "startMinimized");
            startupChoiceMade = RequireBoolean(behavior, "startupChoiceMade");
            closeBehaviorChoiceMade = RequireBoolean(behavior, "closeBehaviorChoiceMade");
            backgroundHintShown = RequireBoolean(behavior, "backgroundHintShown");
        }

        return current with
        {
            LocaleOverride = localeOverride,
            AppearanceMode = appearanceMode,
            MotionPreference = motionPreference,
            LaunchAtStartup = launchAtStartup,
            KeepRunningInBackground = keepRunningInBackground,
            StartMinimized = startMinimized,
            StartupChoiceMade = startupChoiceMade,
            CloseBehaviorChoiceMade = closeBehaviorChoiceMade,
            BackgroundHintShown = backgroundHintShown
        };
    }

    private static BridgeEnvelope ToResponse(
        BridgeEnvelope request,
        ApplicationPreferencesReadResult result) =>
        BridgeEnvelope.Response(
            request,
            new
            {
                schemaVersion = result.Snapshot.SchemaVersion,
                revision = result.Snapshot.Revision,
                storageState = result.StorageState,
                preferences = new Dictionary<string, object?>
                {
                    ["localeOverride"] = result.Snapshot.LocaleOverride,
                    ["appearanceMode"] = result.Snapshot.AppearanceMode,
                    ["motionPreference"] = result.Snapshot.MotionPreference,
                    ["applicationBehavior"] = new Dictionary<string, object?>
                    {
                        ["launchAtStartup"] = result.Snapshot.LaunchAtStartup,
                        ["keepRunningInBackground"] = result.Snapshot.KeepRunningInBackground,
                        ["startMinimized"] = result.Snapshot.StartMinimized,
                        ["startupChoiceMade"] = result.Snapshot.StartupChoiceMade,
                        ["closeBehaviorChoiceMade"] = result.Snapshot.CloseBehaviorChoiceMade,
                        ["backgroundHintShown"] = result.Snapshot.BackgroundHintShown
                    }
                }
            },
            preserveRequestAccountContext: false);

    private static BridgeDispatchBatch Error(
        BridgeEnvelope request,
        string code,
        bool retryable = false) =>
        new(
            BridgeEnvelope.ErrorResponse(
                request,
                new BridgeError(code, "Application preferences operation failed.", retryable)),
            []);

    private static void RequireSchemaVersion(JsonElement payload)
    {
        if (payload.ValueKind != JsonValueKind.Object ||
            !payload.TryGetProperty("schemaVersion", out var value) ||
            value.ValueKind != JsonValueKind.Number ||
            !value.TryGetInt32(out var version) ||
            version != ApplicationPreferencesSchema.Version)
        {
            throw new BridgeProtocolException(
                BridgeErrorCodes.InvalidEnvelope,
                "Application preferences schema version is invalid.");
        }
    }

    private static JsonElement RequireObject(JsonElement payload, string name)
    {
        if (!payload.TryGetProperty(name, out var value) ||
            value.ValueKind != JsonValueKind.Object)
        {
            throw new BridgeProtocolException(
                BridgeErrorCodes.InvalidEnvelope,
                $"{name} must be an object.");
        }
        return value;
    }

    private static long RequireNonNegativeInt64(JsonElement payload, string name)
    {
        if (!payload.TryGetProperty(name, out var value) ||
            value.ValueKind != JsonValueKind.Number ||
            !value.TryGetInt64(out var result) ||
            result < 0)
        {
            throw new BridgeProtocolException(
                BridgeErrorCodes.InvalidEnvelope,
                $"{name} must be a non-negative integer.");
        }
        return result;
    }

    private static string RequireNonEmptyString(JsonElement value, string name)
    {
        if (value.ValueKind != JsonValueKind.String ||
            string.IsNullOrWhiteSpace(value.GetString()))
        {
            throw new BridgeProtocolException(
                BridgeErrorCodes.InvalidEnvelope,
                $"{name} must be a non-empty string.");
        }
        return value.GetString()!.Trim();
    }

    private static bool RequireBoolean(JsonElement payload, string name)
    {
        if (!payload.TryGetProperty(name, out var value) ||
            value.ValueKind is not (JsonValueKind.True or JsonValueKind.False))
        {
            throw new BridgeProtocolException(
                BridgeErrorCodes.InvalidEnvelope,
                $"{name} must be a boolean.");
        }
        return value.GetBoolean();
    }

    private static void RejectUnknownProperties(
        JsonElement payload,
        params string[] allowed)
    {
        if (payload.ValueKind != JsonValueKind.Object)
        {
            throw new BridgeProtocolException(
                BridgeErrorCodes.InvalidEnvelope,
                "Application preferences payload must be an object.");
        }

        var names = new HashSet<string>(allowed, StringComparer.Ordinal);
        foreach (var property in payload.EnumerateObject())
        {
            if (!names.Contains(property.Name))
            {
                throw new BridgeProtocolException(
                    BridgeErrorCodes.InvalidEnvelope,
                    $"Unexpected property '{property.Name}'.");
            }
        }
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }
        _disposed = true;
        _gate.Dispose();
    }
}
