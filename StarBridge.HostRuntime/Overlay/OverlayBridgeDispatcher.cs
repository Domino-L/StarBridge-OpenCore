namespace StarBridge.HostRuntime.Overlay;

using System.Text.Json;
using StarBridge.HostRuntime.Presence;
using StarBridge.NativeBridge;

public sealed partial class OverlayBridgeDispatcher : IBridgeRequestDispatcher
{
    public static IReadOnlyList<string> AdvertisedCapabilities { get; } =
        ["overlay.settings", "overlay.workspace", "overlay.runtime", "overlay.presetSharing"];

    private readonly IOverlaySettingsStore _store;
    private readonly IOverlayWorkspaceStore _workspaceStore;
    private readonly Func<long> _generation;
    private readonly Func<GameLogSessionSnapshot> _currentSession;
    private readonly IInformationOverlayRuntime _runtime;
    private readonly SemaphoreSlim _gate = new(1, 1);
    private OverlaySettingsReadResult? _current;
    private bool _disposed;

    public OverlayBridgeDispatcher(
        string dataRoot,
        Func<long> generation,
        Func<GameLogSessionSnapshot> currentSession,
        IInformationOverlayRuntime? runtime = null)
        : this(
            new OverlaySettingsStore(dataRoot),
            new OverlayWorkspaceStore(dataRoot, Path.Combine(AppContext.BaseDirectory, "config")),
            generation,
            currentSession,
            runtime) { }

    internal OverlayBridgeDispatcher(
        IOverlaySettingsStore store,
        IOverlayWorkspaceStore workspaceStore,
        Func<long> generation,
        Func<GameLogSessionSnapshot> currentSession,
        IInformationOverlayRuntime? runtime = null)
    {
        _store = store;
        _workspaceStore = workspaceStore;
        _generation = generation;
        _currentSession = currentSession;
        _runtime = runtime ?? new UnavailableInformationOverlayRuntime();
    }

    public event Action<BridgeEnvelope>? EventReady { add { } remove { } }

    public async ValueTask<BridgeDispatchBatch> DispatchAsync(
        BridgeEnvelope request,
        CancellationToken cancellationToken = default)
    {
        await _gate.WaitAsync(cancellationToken);
        try
        {
            Validate(request);
            var response = request.Name switch
            {
                OverlayRequestNames.GetState => Read(request),
                OverlayRequestNames.Update => Update(request),
                OverlayRequestNames.GetWorkspace => ReadWorkspace(request),
                OverlayRequestNames.UpdateWorkspace => await UpdateWorkspaceAsync(request, cancellationToken),
                OverlayRequestNames.RuntimeGetState => await RuntimeAsync(
                    request, InformationOverlayRuntimeCommand.Sync, cancellationToken),
                OverlayRequestNames.RuntimeOpen => await RuntimeAsync(
                    request, InformationOverlayRuntimeCommand.Open, cancellationToken),
                OverlayRequestNames.RuntimeClose => await RuntimeAsync(
                    request, InformationOverlayRuntimeCommand.Close, cancellationToken),
                OverlayRequestNames.RuntimeRetry => await RuntimeAsync(
                    request, InformationOverlayRuntimeCommand.Retry, cancellationToken),
                OverlayRequestNames.Preview => throw new BridgeProtocolException(
                    BridgeErrorCodes.CapabilityUnavailable,
                    "Game overlay window is unavailable."),
                _ => throw new BridgeProtocolException(
                    BridgeErrorCodes.CapabilityUnavailable,
                    "Overlay capability is unavailable.")
            };
            return new(response, []);
        }
        catch (OverlaySettingsException exception)
        {
            return Error(request, exception.Code, exception.Retryable);
        }
        catch (BridgeProtocolException exception)
        {
            return Error(request, exception.Code);
        }
        catch (OperationCanceledException)
        {
            return new(BridgeEnvelope.CancelledResponse(request), []);
        }
        catch
        {
            return Error(request, "overlay.read_failed", true);
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
        if (_disposed || request.MessageType != BridgeMessageTypes.Request)
            throw new BridgeProtocolException(BridgeErrorCodes.InvalidEnvelope, "Overlay request is invalid.");
        if (request.SessionGeneration != _generation())
            throw new BridgeStaleGenerationException(request.SessionGeneration, _generation());
        if (request.AccountContext is not null ||
            request.Payload.ValueKind != JsonValueKind.Object ||
            !request.Payload.TryGetProperty("schemaVersion", out var schema) ||
            !schema.TryGetInt32(out var version) || version != OverlaySettingsSchema.Version)
            throw new BridgeProtocolException(BridgeErrorCodes.InvalidEnvelope, "Overlay request is invalid.");
    }

    private BridgeEnvelope Read(BridgeEnvelope request)
    {
        RejectUnknown(request.Payload, "schemaVersion");
        return Response(request, Current());
    }

    private BridgeEnvelope ReadWorkspace(BridgeEnvelope request)
    {
        RejectUnknown(request.Payload, "schemaVersion");
        return WorkspaceResponse(request, _workspaceStore.Load());
    }

    public async Task InitializeRuntimeAsync(CancellationToken cancellationToken = default)
    {
        var workspace = _workspaceStore.Load();
        await _runtime.ExecuteAsync(
            InformationOverlayRuntimeCommand.Sync,
            ToRuntimeWorkspace(workspace, ResolveLanguage(null)),
            cancellationToken);
    }

    private async Task<BridgeEnvelope> UpdateWorkspaceAsync(
        BridgeEnvelope request,
        CancellationToken cancellationToken)
    {
        if (!request.Payload.TryGetProperty("action", out var actionValue) ||
            actionValue.ValueKind != JsonValueKind.String ||
            !request.Payload.TryGetProperty("expectedRevision", out var revisionValue) ||
            !revisionValue.TryGetInt64(out var expectedRevision) || expectedRevision < 0)
        {
            throw new BridgeProtocolException(BridgeErrorCodes.InvalidEnvelope, "Overlay workspace update is invalid.");
        }

        var action = actionValue.GetString();
        if (action is "exportSharedPreset" or "importSharedPreset")
            return SharePreset(request, action, expectedRevision);
        var kind = action switch
        {
            "saveActive" => OverlayWorkspaceMutationKind.SaveActive,
            "activatePreset" => OverlayWorkspaceMutationKind.ActivatePreset,
            "createPreset" => OverlayWorkspaceMutationKind.CreatePreset,
            "duplicatePreset" => OverlayWorkspaceMutationKind.DuplicatePreset,
            "renamePreset" => OverlayWorkspaceMutationKind.RenamePreset,
            "deletePreset" => OverlayWorkspaceMutationKind.DeletePreset,
            "resetPreset" => OverlayWorkspaceMutationKind.ResetPreset,
            "importPreset" => OverlayWorkspaceMutationKind.ImportPreset,
            _ => throw new OverlaySettingsException("overlay.workspace_invalid_action")
        };

        RejectUnknown(request.Payload, AllowedWorkspaceFields(kind));
        RequireWorkspaceFields(request.Payload, RequiredWorkspaceFields(kind));
        var settings = request.Payload.TryGetProperty("settings", out var settingsValue)
            ? OverlayWorkspaceWireProjection.ParseSettings(settingsValue)
            : null;
        var layout = request.Payload.TryGetProperty("layout", out var layoutValue)
            ? OverlayWorkspaceWireProjection.ParseLayout(layoutValue)
            : null;
        var hotkey = request.Payload.TryGetProperty("hotkey", out var hotkeyValue)
            ? ParseHotkey(hotkeyValue)
            : null;
        var mutation = new OverlayWorkspaceMutation(
            expectedRevision,
            kind,
            OptionalString(request.Payload, "presetId"),
            OptionalString(request.Payload, "name"),
            settings,
            layout,
            OptionalString(request.Payload, "renderMode"),
            hotkey);
        var workspace = _workspaceStore.Apply(mutation);
        await _runtime.ExecuteAsync(
            InformationOverlayRuntimeCommand.Sync,
            ToRuntimeWorkspace(workspace, ResolveLanguage(null)),
            cancellationToken);
        return WorkspaceResponse(request, workspace);
    }

    private async Task<BridgeEnvelope> RuntimeAsync(
        BridgeEnvelope request,
        InformationOverlayRuntimeCommand command,
        CancellationToken cancellationToken)
    {
        RejectUnknown(request.Payload, "schemaVersion", "language", "workspace");
        var language = OptionalString(request.Payload, "language");
        var workspace = _workspaceStore.Load();
        var runtimeWorkspace = request.Payload.TryGetProperty("workspace", out var draft)
            ? ParseRuntimeDraft(draft, workspace, ResolveLanguage(language))
            : ToRuntimeWorkspace(workspace, ResolveLanguage(language));
        var snapshot = await _runtime.ExecuteAsync(
            command,
            runtimeWorkspace,
            cancellationToken);
        return BridgeEnvelope.Response(request, new
        {
            schemaVersion = 1,
            windowState = snapshot.WindowState,
            isVisible = snapshot.IsVisible,
            appliedRevision = snapshot.AppliedRevision,
            hotkeyState = snapshot.HotkeyState,
            followGameState = snapshot.FollowGameState,
            requestedSkin = snapshot.RequestedSkin,
            effectiveSkin = snapshot.EffectiveSkin,
            usedFallbackSkin = snapshot.UsedFallbackSkin,
            failureCode = snapshot.FailureCode,
            retryable = snapshot.Retryable
        }, preserveRequestAccountContext: false);
    }

    private InformationOverlayRuntimeWorkspace ToRuntimeWorkspace(
        OverlayWorkspaceReadResult workspace,
        string language) => new(
            workspace.Revision,
            workspace.Settings,
            workspace.Layout,
            workspace.Hotkey.Binding,
            workspace.Hotkey.Enabled,
            _currentSession(),
            language);

    private InformationOverlayRuntimeWorkspace ParseRuntimeDraft(
        JsonElement value,
        OverlayWorkspaceReadResult persisted,
        string language)
    {
        if (value.ValueKind != JsonValueKind.Object)
        {
            throw new BridgeProtocolException(
                BridgeErrorCodes.InvalidEnvelope,
                "Overlay runtime workspace draft is invalid.");
        }
        RejectUnknown(value, "expectedRevision", "settings", "layout", "hotkey");
        RequireWorkspaceFields(value, ["expectedRevision", "settings", "layout", "hotkey"]);
        if (!value.GetProperty("expectedRevision").TryGetInt64(out var expectedRevision) ||
            expectedRevision < 0)
        {
            throw new BridgeProtocolException(
                BridgeErrorCodes.InvalidEnvelope,
                "Overlay runtime workspace revision is invalid.");
        }
        if (expectedRevision != persisted.Revision)
        {
            throw new OverlaySettingsException("overlay.workspace_revision_conflict", true);
        }

        var settings = OverlayWorkspaceStore.NormalizeSettings(
            OverlayWorkspaceWireProjection.ParseSettings(value.GetProperty("settings")));
        var layout = OverlayWorkspaceStore.ValidateLayout(
            OverlayWorkspaceWireProjection.ParseLayout(value.GetProperty("layout")));
        var hotkey = OverlayWorkspaceStore.NormalizeHotkey(
            ParseHotkey(value.GetProperty("hotkey")));
        return new InformationOverlayRuntimeWorkspace(
            persisted.Revision,
            settings,
            layout,
            hotkey.Binding,
            hotkey.Enabled,
            _currentSession(),
            language);
    }

    private static string ResolveLanguage(string? value)
        => InformationOverlayLanguage.Resolve(value);

    private BridgeEnvelope WorkspaceResponse(
        BridgeEnvelope request,
        OverlayWorkspaceReadResult workspace)
    {
        var appearances = _runtime is IInformationOverlayAppearanceCatalog catalog
            ? catalog.GetAppearances()
            : Array.Empty<InformationOverlayAppearanceProfile>();
        return BridgeEnvelope.Response(request, new
        {
            schemaVersion = workspace.SchemaVersion,
            revision = workspace.Revision,
            storageState = workspace.StorageState,
            activePresetId = workspace.ActivePresetId,
            renderMode = workspace.RenderMode,
            appearances = appearances.Select(appearance => new
            {
                id = appearance.Id,
                displayNameZh = appearance.DisplayNameZh,
                displayNameEn = appearance.DisplayNameEn,
                summaryZh = appearance.SummaryZh,
                summaryEn = appearance.SummaryEn,
                traitsZh = appearance.TraitsZh,
                traitsEn = appearance.TraitsEn,
                previewSurface = appearance.PreviewSurface,
                previewPrimary = appearance.PreviewPrimary,
                previewSecondary = appearance.PreviewSecondary,
                locksTheme = appearance.LocksTheme,
                supportsBloom = appearance.SupportsBloom,
                startupTransition = appearance.StartupTransition,
                requiresEntitlement = appearance.RequiresEntitlement,
                isReleased = appearance.IsReleased,
                isPreviewAvailable = appearance.IsPreviewAvailable ?? appearance.IsReleased,
                isAvailable = appearance.IsAvailable
            }).ToArray(),
            hotkey = new
            {
                binding = workspace.Hotkey.Binding,
                enabled = workspace.Hotkey.Enabled,
                runtimeState = workspace.Hotkey.RuntimeState
            },
            settings = OverlayWorkspaceWireProjection.Settings(workspace.Settings),
            layout = workspace.Layout.Select(OverlayWorkspaceWireProjection.Layout).ToArray(),
            presets = workspace.Presets.Select(preset => new
            {
                id = preset.Id,
                name = preset.Name,
                isActive = preset.IsActive,
                storageState = preset.StorageState,
                settings = OverlayWorkspaceWireProjection.Settings(preset.Settings),
                layout = preset.Layout.Select(OverlayWorkspaceWireProjection.Layout).ToArray()
            }).ToArray()
        }, preserveRequestAccountContext: false);
    }

    private static OverlayWorkspaceHotkeySnapshot ParseHotkey(JsonElement value)
    {
        if (value.ValueKind != JsonValueKind.Object ||
            !value.TryGetProperty("binding", out var binding) ||
            binding.ValueKind != JsonValueKind.String ||
            !value.TryGetProperty("enabled", out var enabled) ||
            enabled.ValueKind is not (JsonValueKind.True or JsonValueKind.False))
        {
            throw new OverlaySettingsException("overlay.workspace_invalid_hotkey");
        }

        RejectUnknown(value, "binding", "enabled");

        return new OverlayWorkspaceHotkeySnapshot(
            binding.GetString() ?? string.Empty,
            enabled.GetBoolean(),
            "unavailable");
    }

    private static string? OptionalString(JsonElement value, string name)
    {
        if (!value.TryGetProperty(name, out var property))
        {
            return null;
        }
        if (property.ValueKind != JsonValueKind.String)
        {
            throw new BridgeProtocolException(BridgeErrorCodes.InvalidEnvelope, "Overlay workspace field is invalid.");
        }
        return property.GetString();
    }

    private static string[] AllowedWorkspaceFields(OverlayWorkspaceMutationKind kind) => kind switch
    {
        OverlayWorkspaceMutationKind.SaveActive =>
            ["schemaVersion", "expectedRevision", "action", "settings", "layout", "renderMode", "hotkey"],
        OverlayWorkspaceMutationKind.ActivatePreset or
        OverlayWorkspaceMutationKind.DeletePreset or
        OverlayWorkspaceMutationKind.ResetPreset =>
            ["schemaVersion", "expectedRevision", "action", "presetId"],
        OverlayWorkspaceMutationKind.CreatePreset =>
            ["schemaVersion", "expectedRevision", "action", "name"],
        OverlayWorkspaceMutationKind.DuplicatePreset or
        OverlayWorkspaceMutationKind.RenamePreset =>
            ["schemaVersion", "expectedRevision", "action", "presetId", "name"],
        OverlayWorkspaceMutationKind.ImportPreset =>
            ["schemaVersion", "expectedRevision", "action", "name", "settings", "layout"],
        _ => []
    };

    private static string[] RequiredWorkspaceFields(OverlayWorkspaceMutationKind kind) =>
        AllowedWorkspaceFields(kind);

    private static void RequireWorkspaceFields(JsonElement value, IEnumerable<string> required)
    {
        if (required.Any(name => !value.TryGetProperty(name, out _)))
        {
            throw new BridgeProtocolException(BridgeErrorCodes.InvalidEnvelope, "Overlay workspace field is missing.");
        }
    }

    private BridgeEnvelope Update(BridgeEnvelope request)
    {
        RejectUnknown(request.Payload, "schemaVersion", "expectedRevision", "settings");
        if (!request.Payload.TryGetProperty("expectedRevision", out var revisionValue) ||
            !revisionValue.TryGetInt64(out var expectedRevision) || expectedRevision < 0 ||
            !request.Payload.TryGetProperty("settings", out var settings) ||
            settings.ValueKind != JsonValueKind.Object)
            throw new BridgeProtocolException(BridgeErrorCodes.InvalidEnvelope, "Overlay update is invalid.");
        RejectUnknown(settings, "enabled", "opacity", "position", "showTeam");
        var current = Current();
        if (current.Snapshot.Revision != expectedRevision)
            throw new OverlaySettingsException("overlay.revision_conflict", true);
        if (!settings.TryGetProperty("enabled", out var enabled) ||
            enabled.ValueKind is not (JsonValueKind.True or JsonValueKind.False) ||
            !settings.TryGetProperty("opacity", out var opacity) || !opacity.TryGetDouble(out var opacityValue) ||
            !settings.TryGetProperty("position", out var position) || position.ValueKind != JsonValueKind.String ||
            !settings.TryGetProperty("showTeam", out var showTeam) ||
            showTeam.ValueKind is not (JsonValueKind.True or JsonValueKind.False))
            throw new BridgeProtocolException(BridgeErrorCodes.InvalidEnvelope, "Overlay settings are invalid.");
        var next = new OverlaySettingsSnapshot(
            OverlaySettingsSchema.Version,
            checked(expectedRevision + 1),
            enabled.GetBoolean(),
            opacityValue,
            position.GetString()!,
            showTeam.GetBoolean()).Normalize();
        if (!next.IsSupported())
            throw new OverlaySettingsException("overlay.invalid_value");
        _store.Save(next);
        _current = new(next, "ready");
        return Response(request, _current);
    }

    private OverlaySettingsReadResult Current() => _current ??= _store.Load();

    private BridgeEnvelope Response(BridgeEnvelope request, OverlaySettingsReadResult result)
    {
        var session = _currentSession();
        return BridgeEnvelope.Response(request, new
        {
            schemaVersion = OverlaySettingsSchema.Version,
            revision = result.Snapshot.Revision,
            storageState = result.StorageState,
            windowState = "unavailable",
            settings = new
            {
                enabled = result.Snapshot.Enabled,
                opacity = result.Snapshot.Opacity,
                position = result.Snapshot.Position,
                showTeam = result.Snapshot.ShowTeam
            },
            session = new
            {
                schemaVersion = 1,
                server = session.Server,
                location = session.Location,
                ship = session.Ship
            }
        }, preserveRequestAccountContext: false);
    }

    private static void RejectUnknown(JsonElement value, params string[] allowed)
    {
        var names = new HashSet<string>(allowed, StringComparer.Ordinal);
        if (value.EnumerateObject().Any(item => !names.Contains(item.Name)))
            throw new BridgeProtocolException(BridgeErrorCodes.InvalidEnvelope, "Overlay request contains unknown fields.");
    }

    private static BridgeDispatchBatch Error(BridgeEnvelope request, string code, bool retryable = false) =>
        new(BridgeEnvelope.ErrorResponse(request,
            new BridgeError(code, "Overlay operation failed.", retryable)), []);

    public void Dispose()
    {
        _disposed = true;
        _runtime.Dispose();
        _gate.Dispose();
    }
}
