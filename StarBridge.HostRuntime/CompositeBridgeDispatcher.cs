namespace StarBridge.HostRuntime;

using StarBridge.NativeBridge;

/// <summary>
/// Routes lifecycle and account requests while presenting one dispatcher seam
/// to the pipe owner. Feature routing remains explicit and fail-closed.
/// </summary>
public sealed class CompositeBridgeDispatcher : IBridgeRequestDispatcher
{
    private readonly IBridgeRequestDispatcher _host;
    private readonly IBridgeRequestDispatcher _account;
    private readonly IBridgeRequestDispatcher _applicationPreferences;
    private readonly IBridgeRequestDispatcher? _hangarSandbox;
    private readonly IBridgeRequestDispatcher? _overlay;
    private readonly IBridgeRequestDispatcher? _audio;
    private readonly IBridgeRequestDispatcher? _support;
    private readonly IBridgeRequestDispatcher? _runtimeFacts;
    private readonly IBridgeRequestDispatcher? _clientLicense;
    private readonly IBridgeRequestDispatcher? _updates;
    private readonly IBridgeRequestDispatcher? _helpSupport;
    private readonly IBridgeRequestDispatcher? _storageMigration;
    private readonly IBridgeRequestDispatcher? _notificationPolicies;
    private readonly IBridgeRequestDispatcher? _overlayRuntimeStatus;
    private readonly IBridgeRequestDispatcher? _localHistory;
    private readonly IBridgeRequestDispatcher? _localEventExport;
    private readonly IBridgeRequestDispatcher? _localEventClear;
    private readonly IBridgeRequestDispatcher? _playReminder;
    private readonly Notifications.NotificationSettingsBridgeDispatcher? _notifications;
    private readonly Notifications.PlayerActivityRuntime? _playerActivity;
    private bool _disposed;

    public CompositeBridgeDispatcher(
        IBridgeRequestDispatcher host,
        IBridgeRequestDispatcher account,
        IBridgeRequestDispatcher applicationPreferences,
        IBridgeRequestDispatcher? hangarSandbox = null,
        IBridgeRequestDispatcher? overlay = null,
        IBridgeRequestDispatcher? audio = null,
        Notifications.NotificationSettingsBridgeDispatcher? notifications = null,
        IBridgeRequestDispatcher? support = null,
        IBridgeRequestDispatcher? playReminder = null,
        IBridgeRequestDispatcher? localHistory = null,
        IBridgeRequestDispatcher? localEventExport = null,
        IBridgeRequestDispatcher? localEventClear = null,
        IBridgeRequestDispatcher? runtimeFacts = null,
        IBridgeRequestDispatcher? overlayRuntimeStatus = null,
        IBridgeRequestDispatcher? clientLicense = null,
        Notifications.PlayerActivityRuntime? playerActivity = null,
        IBridgeRequestDispatcher? updates = null,
        IBridgeRequestDispatcher? storageMigration = null,
        IBridgeRequestDispatcher? notificationPolicies = null,
        IBridgeRequestDispatcher? helpSupport = null)
    {
        _host = host ?? throw new ArgumentNullException(nameof(host));
        _account = account ?? throw new ArgumentNullException(nameof(account));
        _applicationPreferences = applicationPreferences ??
            throw new ArgumentNullException(nameof(applicationPreferences));
        _host.EventReady += Publish;
        _hangarSandbox = hangarSandbox;
        _overlay = overlay;
        _audio = audio;
        _support = support;
        _runtimeFacts = runtimeFacts;
        _clientLicense = clientLicense;
        _updates = updates;
        if (_updates != null) _updates.EventReady += Publish;
        _helpSupport = helpSupport;
        _storageMigration = storageMigration;
        _notificationPolicies = notificationPolicies;
        _overlayRuntimeStatus = overlayRuntimeStatus;
        _localHistory = localHistory;
        _localEventExport = localEventExport;
        _localEventClear = localEventClear;
        _playReminder = playReminder;
        _playerActivity = playerActivity;
        if (_support != null) _support.EventReady += Publish;
        _notifications = notifications;
        if (_notifications != null) _notifications.EventReady += Publish;
        _account.EventReady += Publish;
        _applicationPreferences.EventReady += Publish;
    }

    public event Action<BridgeEnvelope>? EventReady;

    public ValueTask<BridgeDispatchBatch> DispatchAsync(
        BridgeEnvelope request,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(request);
        if (_helpSupport != null && Support.HelpSupportBridgeDispatcher.Capabilities.Contains(request.Name))
            return _helpSupport.DispatchAsync(request, cancellationToken);
        if (_storageMigration != null && request.Name is Storage.StorageMigrationBridgeDispatcher.ChooseRequest or Storage.StorageMigrationBridgeDispatcher.ConfirmRequest
            or Storage.StorageMigrationBridgeDispatcher.ResultRequest or Storage.StorageMigrationBridgeDispatcher.AcknowledgeRequest)
            return _storageMigration.DispatchAsync(request, cancellationToken);
        if (_updates != null && request.Name is Updates.FlutterUpdateBridgeDispatcher.RequestName or Updates.FlutterUpdateBridgeDispatcher.ReadyRequestName
            or Updates.FlutterUpdateBridgeDispatcher.PrepareRequestName or Updates.FlutterUpdateBridgeDispatcher.HandoffRequestName)
            return _updates.DispatchAsync(request, cancellationToken);
        if (_playerActivity != null && Notifications.PlayerActivityRuntime.Capabilities.Contains(request.Name))
            return _playerActivity.DispatchAsync(request, cancellationToken);
        if (_clientLicense != null && request.Name is Support.ClientLicenseBridgeDispatcher.RequestName
            or Support.ClientLicenseBridgeDispatcher.NoticeRead or Support.ClientLicenseBridgeDispatcher.NoticeAccept)
            return _clientLicense.DispatchAsync(request, cancellationToken);
        if (_overlayRuntimeStatus != null && request.Name == Support.OverlayRuntimeStatusBridgeDispatcher.RequestName)
            return _overlayRuntimeStatus.DispatchAsync(request, cancellationToken);
        if (_runtimeFacts != null && request.Name == Support.RuntimeFactsBridgeDispatcher.RequestName)
            return _runtimeFacts.DispatchAsync(request, cancellationToken);
        if (_localEventClear != null && request.Name == Support.LocalEventClearDispatcher.RequestName)
            return _localEventClear.DispatchAsync(request, cancellationToken);
        if (_localEventExport != null && request.Name == Support.LocalEventExportDispatcher.RequestName)
            return _localEventExport.DispatchAsync(request, cancellationToken);
        if (_localHistory != null && request.Name == Support.LocalEventHistoryBridgeDispatcher.RequestName)
            return _localHistory.DispatchAsync(request, cancellationToken);
        if (_playReminder != null && Reminders.ContinuousPlayBridgeDispatcher.AdvertisedCapabilities.Contains(request.Name))
            return _playReminder.DispatchAsync(request, cancellationToken);
        if (_support != null && request.Name.StartsWith("diagnostics.", StringComparison.Ordinal))
            return _support.DispatchAsync(request, cancellationToken);
        if (request.Name == Account.AccountBridgeRequestNames.GetPartyRooms && (_audio != null || _notifications != null))
            return ObserveRoomReadAsync(request, cancellationToken);
        if (request.Name == "directMessages.read" && _notifications != null)
            return ObserveRoomReadAsync(request, cancellationToken);
        if (_notificationPolicies != null && request.Name.StartsWith("notificationPolicies.", StringComparison.Ordinal))
            return _notificationPolicies.DispatchAsync(request, cancellationToken);
        if (_notifications != null && request.Name.StartsWith("notificationSettings.", StringComparison.Ordinal))
            return _notifications.DispatchAsync(request, cancellationToken);
        if (_audio != null && request.Name.StartsWith("notificationAudio.", StringComparison.Ordinal))
            return _audio.DispatchAsync(request, cancellationToken);
        if (_hangarSandbox != null && request.Name.StartsWith("hangarSandbox.", StringComparison.Ordinal))
            return _hangarSandbox.DispatchAsync(request, cancellationToken);
        if (request.Name.StartsWith("host.", StringComparison.Ordinal))
        {
            if (request.Name == "host.shutdown" && _account is AccountBridgeRuntime account)
                return StopAndShutdownAsync(account, request, cancellationToken);
            return _host.DispatchAsync(request, cancellationToken);
        }

        if (request.Name.StartsWith("account.", StringComparison.Ordinal) ||
            request.Name is "accountSafety.read" or "accountSafety.appeal" ||
            request.Name is "notificationInbox.read" or "notificationInbox.markRead" ||
            request.Name.StartsWith("overlayScenes.", StringComparison.Ordinal) ||
            request.Name.StartsWith("profile.", StringComparison.Ordinal) ||
            request.Name.StartsWith("personalProfile.", StringComparison.Ordinal) ||
            request.Name is "users.profile" or "users.social" ||
            request.Name.StartsWith("privacy.", StringComparison.Ordinal) ||
            request.Name is "eventSharing.read" or "eventSharing.save" or
                "friendSharing.read" or "friendSharing.save" or
                "gameIdVisibility.read" or "gameIdVisibility.save" or
                "friendRequests.privacyRead" or "friendRequests.privacyWrite" or
                "recentlyPlayed.privacyRead" or "recentlyPlayed.privacyWrite" ||
            request.Name is "presence.read" or "presence.set" ||
            request.Name.StartsWith("gameIdentity.", StringComparison.Ordinal) ||
            request.Name.StartsWith("gameplayTime.", StringComparison.Ordinal) ||
            request.Name.StartsWith("gameLog.", StringComparison.Ordinal) ||
            request.Name.StartsWith("officialFleet.", StringComparison.Ordinal) ||
            request.Name.StartsWith("friends.", StringComparison.Ordinal) ||
            request.Name.StartsWith("directMessages.", StringComparison.Ordinal) ||
            request.Name.StartsWith("communities.", StringComparison.Ordinal) ||
            request.Name.StartsWith("partyRooms.", StringComparison.Ordinal) ||
            request.Name.StartsWith("hangarReader.", StringComparison.Ordinal))
        {
            return _account.DispatchAsync(request, cancellationToken);
        }

        if (request.Name.StartsWith("applicationPreferences.", StringComparison.Ordinal))
        {
            return _applicationPreferences.DispatchAsync(request, cancellationToken);
        }

        if (_overlay != null && request.Name.StartsWith("overlay.", StringComparison.Ordinal))
        {
            return _overlay.DispatchAsync(request, cancellationToken);
        }

        return ValueTask.FromResult(
            new BridgeDispatchBatch(
                BridgeEnvelope.ErrorResponse(
                    request,
                    new BridgeError(
                        BridgeErrorCodes.CapabilityUnavailable,
                        "Native Host capability is unavailable.")),
                []));
    }

    private async ValueTask<BridgeDispatchBatch> ObserveRoomReadAsync(BridgeEnvelope request, CancellationToken token)
    {
        var batch = await _account.DispatchAsync(request, token).ConfigureAwait(false);
        if (_audio is Notifications.NotificationAudioBridgeDispatcher audio) audio.ObserveRoomRead(request, batch.Response, token);
        return _notifications == null ? batch : batch with { Response = await _notifications.ObserveAsync(request, batch.Response, token).ConfigureAwait(false) };
    }

    private void Publish(BridgeEnvelope envelope)
    {
        if (envelope.Name is "account.changed" or "bootstrap.invalidated") _notifications?.Reset();
        if (envelope.Name is "account.changed" or "bootstrap.invalidated" && _audio is Notifications.NotificationAudioBridgeDispatcher audio)
            audio.ResetAutomaticSession();
        EventReady?.Invoke(envelope);
    }

    private async ValueTask<BridgeDispatchBatch> StopAndShutdownAsync(AccountBridgeRuntime account,
        BridgeEnvelope request, CancellationToken token)
    {
        BridgeEnvelopeValidator.ValidateWireShape(request);
        BridgeEnvelopeValidator.RequireCurrentVersion(request);
        if (request.MessageType == BridgeMessageTypes.Request && request.SessionGeneration == account.Generation)
            await account.StopPrivacyPublicationAsync(token).ConfigureAwait(false);
        return await _host.DispatchAsync(request, token).ConfigureAwait(false);
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;
        _playerActivity?.Dispose();
        _runtimeFacts?.Dispose();
        _clientLicense?.Dispose();
        if (_updates != null) _updates.EventReady -= Publish;
        _updates?.Dispose();
        _helpSupport?.Dispose();
        _storageMigration?.Dispose();
        _overlayRuntimeStatus?.Dispose();
        _localHistory?.Dispose();
        _localEventExport?.Dispose();
        _localEventClear?.Dispose();
        _playReminder?.Dispose();
        _host.EventReady -= Publish;
        _account.EventReady -= Publish;
        _applicationPreferences.EventReady -= Publish;
        if (_notifications != null) _notifications.EventReady -= Publish;
        _host.Dispose();
        _account.Dispose();
        _applicationPreferences.Dispose();
        _hangarSandbox?.Dispose();
        _overlay?.Dispose();
        _audio?.Dispose();
        if (_support != null) _support.EventReady -= Publish;
        _support?.Dispose();
        _notifications?.Dispose();
        _notificationPolicies?.Dispose();
    }
}
