namespace StarBridge.HostRuntime.Account;

using StarBridge.Core.Profiles;
using StarBridge.NativeBridge;
using System.Text.Json;

internal sealed record AccountBridgeDispatchResult(
    BridgeEnvelope Response,
    IReadOnlyList<BridgeEnvelope> Events);

/// <summary>
/// Converts the account host's narrow projections into the frozen Bridge v1
/// wire shape. Callers must send Response before Events so a successful
/// account transition completes before account.changed advances generation.
/// </summary>
internal sealed class AccountBridgeDispatcher : IDisposable
{
    private readonly IAccountBridgeHost _host;
    private readonly string[] _profileActions;
    private readonly AccountDispatchGate _dispatchGate = new();
    private readonly object _eventGate = new();
    private readonly List<BridgeEnvelope> _pendingEvents = [];
    private long _eventSequence;
    private int _activeDispatches;
    private bool _disposed;

    internal AccountBridgeDispatcher(
        IAccountBridgeHost host, IReadOnlyCollection<string>? enabledRequests = null)
    {
        _host = host ?? throw new ArgumentNullException(nameof(host));
        _profileActions = new[] {
            AccountBridgeRequestNames.PatchPreferences, AccountBridgeRequestNames.ClearProfileCache
        }.Where(name => enabledRequests?.Contains(name) == true).ToArray();
        _host.AccountChanged += OnAccountChanged;
    }

    /// <summary>
    /// Publishes account invalidations that happen outside a request. The pipe
    /// owner forwards these immediately; request-scoped transitions remain in
    /// <see cref="AccountBridgeDispatchResult.Events"/> so the response can be
    /// written first.
    /// </summary>
    internal event Action<BridgeEnvelope>? EventReady;

    internal BridgeEnvelope DomainInvalidation(string name, long generation)
    {
        lock (_eventGate)
            return BridgeEnvelope.Event(name, generation, ++_eventSequence, new { schemaVersion = AccountBridgeSchema.Version });
    }

    internal void PublishDomainInvalidation(string name, long generation)
    {
        BridgeEnvelope envelope;
        Action<BridgeEnvelope>? publish = null;
        lock (_eventGate)
        {
            if (_disposed || generation != _host.Generation) return;
            envelope = DomainInvalidation(name, generation);
            if (_activeDispatches > 0) _pendingEvents.Add(envelope);
            else publish = EventReady;
        }
        publish?.Invoke(envelope);
    }

    internal async Task<AccountBridgeDispatchResult> DispatchAsync(
        BridgeEnvelope request,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(request);
        if (request.Name == AccountBridgeRequestNames.CancelLogin)
        {
            return await DispatchLoginCancellationAsync(request);
        }

        var concurrentRead = _host.SupportsConcurrentReads && IsIndependentRead(request.Name);
        bool drainEvents;
        lock (_eventGate) drainEvents = _pendingEvents.Count > 0;
        // Once an invalidation is pending, fence later readers so a continuous
        // stream of reads cannot indefinitely postpone its delivery.
        await using var lease = await _dispatchGate.EnterAsync(concurrentRead && !drainEvents, cancellationToken);
        try
        {
            BeginDispatchEventCollection();
            var response = await DispatchCoreAsync(request, cancellationToken);
            // A read may have been invalidated by another reader's credential
            // failure or an external account transition while it awaited I/O.
            // GetCurrent itself can restore the session and owns that transition.
            if (concurrentRead && request.Name != AccountBridgeRequestNames.GetCurrent &&
                request.SessionGeneration != _host.Generation)
                throw new BridgeStaleGenerationException(request.SessionGeneration, _host.Generation);
            return Result(response);
        }
        catch (AccountBridgeHostException exception)
        {
            return Result(
                BridgeEnvelope.ErrorResponse(
                    request,
                    new BridgeError(exception.Code, "Account operation failed.", exception.Retryable)));
        }
        catch (BridgeProtocolException exception)
        {
            return Result(
                BridgeEnvelope.ErrorResponse(
                    request,
                    new BridgeError(exception.Code, "Bridge request was rejected.")));
        }
        catch (OperationCanceledException) when (request.Name == AccountBridgeRequestNames.Login)
        {
            return Result(
                BridgeEnvelope.ErrorResponse(
                    request,
                    new BridgeError(AccountBridgeStableErrors.LoginCancelled, "Sign-in was cancelled.")));
        }
        catch (OperationCanceledException)
        {
            return Result(BridgeEnvelope.CancelledResponse(request));
        }
        catch (Exception)
        {
            return Result(
                BridgeEnvelope.ErrorResponse(
                    request,
                    new BridgeError(BridgeErrorCodes.Disconnected, "Account host is unavailable.", true)));
        }
    }

    // Explicitly audited read-only surfaces, not a suffix/prefix heuristic.
    // Authentication and writes, and unaudited reads, remain exclusive.
    private static bool IsIndependentRead(string name) => name is
        AccountBridgeRequestNames.GetCurrent or
        AccountBridgeRequestNames.ReadFriends or
        AccountBridgeRequestNames.ReadCommunities or
        AccountBridgeRequestNames.ReadCommunityWorkspace or
        AccountBridgeRequestNames.ReadCommunityMedia;

    private async Task<AccountBridgeDispatchResult> DispatchLoginCancellationAsync(
        BridgeEnvelope request)
    {
        try
        {
            BridgeEnvelopeValidator.ValidateWireShape(request);
            BridgeEnvelopeValidator.RequireCurrentVersion(request);
            RequireSchemaVersion(request.Payload);
            if (request.SessionGeneration != _host.Generation)
            {
                throw new BridgeStaleGenerationException(
                    request.SessionGeneration,
                    _host.Generation);
            }

            return new AccountBridgeDispatchResult(
                await CancelLoginAsync(request),
                []);
        }
        catch (BridgeProtocolException exception)
        {
            return new AccountBridgeDispatchResult(
                BridgeEnvelope.ErrorResponse(
                    request,
                    new BridgeError(exception.Code, "Bridge request was rejected.")),
                []);
        }
        catch (Exception)
        {
            return new AccountBridgeDispatchResult(
                BridgeEnvelope.ErrorResponse(
                    request,
                    new BridgeError(BridgeErrorCodes.Disconnected, "Account host is unavailable.", true)),
                []);
        }
    }

    private async Task<BridgeEnvelope> DispatchCoreAsync(
        BridgeEnvelope request,
        CancellationToken cancellationToken)
    {
        BridgeEnvelopeValidator.ValidateWireShape(request);
        BridgeEnvelopeValidator.RequireCurrentVersion(request);
        if (request.MessageType != BridgeMessageTypes.Request)
        {
            throw new BridgeProtocolException(
                BridgeErrorCodes.InvalidEnvelope,
                "Account dispatcher only accepts requests.");
        }

        RequireSchemaVersion(request.Payload);
        if (request.SessionGeneration != _host.Generation)
        {
            throw new BridgeStaleGenerationException(
                request.SessionGeneration,
                _host.Generation);
        }

        BridgeEnvelopeValidator.RequireAccountContext(request.Name, request.AccountContext);
        return request.Name switch
        {
            AccountBridgeRequestNames.RedeemLegacyEntitlements =>
                BridgeEnvelope.Response(request, await _host.RedeemLegacyEntitlementsAsync(request.AccountContext!, request.Payload, cancellationToken)),
            AccountBridgeRequestNames.LoginLegacy =>
                request.AccountContext is not null
                    ? throw new BridgeProtocolException(BridgeErrorCodes.InvalidEnvelope, "Legacy login must not carry an SCM context.")
                    : BridgeEnvelope.Response(request, await _host.LoginLegacyAsync(request.Payload, request.SessionGeneration, cancellationToken)),
            AccountBridgeRequestNames.SendPasswordResetCode or AccountBridgeRequestNames.ConfirmPasswordReset =>
                request.AccountContext is not null
                    ? throw new BridgeProtocolException(BridgeErrorCodes.InvalidEnvelope, "Password recovery must not carry an account context.")
                    : BridgeEnvelope.Response(request, await _host.RecoverPasswordAsync(request.Name, request.Payload, cancellationToken)),
            AccountBridgeRequestNames.GetLegacyProfileMigrationStatus or
                AccountBridgeRequestNames.PreviewLegacyProfileMigration or
                AccountBridgeRequestNames.ConfirmLegacyProfileMigration =>
                await DispatchMigrationAsync(request, cancellationToken),
            AccountBridgeRequestNames.GetCurrent =>
                ToSessionResponse(request, await _host.GetCurrentAsync(cancellationToken)),
            AccountBridgeRequestNames.UpdateAvatar =>
                await UpdateAvatarAsync(request, cancellationToken),
            AccountBridgeRequestNames.Login =>
                ToSessionResponse(request, await _host.LoginAsync(cancellationToken)),
            AccountBridgeRequestNames.CancelLogin =>
                await CancelLoginAsync(request),
            AccountBridgeRequestNames.Logout =>
                await LogoutAsync(request, cancellationToken),
            AccountBridgeRequestNames.GetProfile =>
                ToProfileResponse(
                    request,
                    await _host.GetProfileAsync(
                        RequireCurrentContext(request),
                        cancellationToken)),
            AccountBridgeRequestNames.GetPersonalProfile =>
                ToPersonalProfileResponse(
                    request,
                    await _host.GetPersonalProfileAsync(
                        RequireCurrentContext(request),
                        cancellationToken)),
            "personalProfile.readVisibility" or "personalProfile.saveVisibility" =>
                BridgeEnvelope.Response(request, await _host.ProfileVisibilityAsync(
                    RequireCurrentContext(request), request.Payload,
                    request.Name == "personalProfile.saveVisibility", cancellationToken)),
            "communities.memberPersonalProfile" =>
                ToPersonalProfileResponse(request, await _host.ReadMemberPersonalProfileAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken), editable: false),
            "users.profile" =>
                ToPersonalProfileResponse(request, await _host.ReadUserProfileAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken), editable: false),
            "users.social" =>
                BridgeEnvelope.Response(request, await _host.ReadUserSocialAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.UpdatePersonalProfile =>
                ToPersonalProfileResponse(
                    request,
                    await _host.UpdatePersonalProfileAsync(
                        RequireCurrentContext(request),
                        ParsePersonalProfileUpdate(request.Payload),
                        cancellationToken)),
            AccountBridgeRequestNames.GetOfficialFleet =>
                ToOfficialFleetResponse(
                    request,
                    await _host.GetOfficialFleetAsync(
                        RequireCurrentContext(request),
                        cancellationToken)),
            AccountBridgeRequestNames.GetPartyRooms =>
                BridgeEnvelope.Response(request, await _host.GetPartyRoomsAsync(
                    RequireCurrentContext(request), cancellationToken)),
            AccountBridgeRequestNames.ExecuteFriend =>
                BridgeEnvelope.Response(request, await _host.ExecuteFriendAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.ReadDirectMessages =>
                BridgeEnvelope.Response(request, await _host.ReadDirectMessagesAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.ReadDirectMessagePrivacy =>
                BridgeEnvelope.Response(request, await _host.ReadDirectMessagePrivacyAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.SaveDirectMessagePrivacy =>
                BridgeEnvelope.Response(request, await _host.SaveDirectMessagePrivacyAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.ReadFriendRequestPrivacy =>
                BridgeEnvelope.Response(request, await _host.ReadFriendRequestPrivacyAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.SaveFriendRequestPrivacy =>
                BridgeEnvelope.Response(request, await _host.SaveFriendRequestPrivacyAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.ReadRecentlyPlayedPrivacy =>
                BridgeEnvelope.Response(request, await _host.ReadRecentlyPlayedPrivacyAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.SaveRecentlyPlayedPrivacy =>
                BridgeEnvelope.Response(request, await _host.SaveRecentlyPlayedPrivacyAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.MarkDirectMessagesRead =>
                BridgeEnvelope.Response(request, await _host.MarkDirectMessagesReadAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.SendDirectMessage =>
                BridgeEnvelope.Response(request, await _host.SendDirectMessageAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.ReadFriends =>
                BridgeEnvelope.Response(request, await _host.ReadFriendsAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.ReadAccountSafety =>
                BridgeEnvelope.Response(request, await _host.ReadAccountSafetyAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.ReadNotificationInbox =>
                BridgeEnvelope.Response(request, await _host.ReadNotificationInboxAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.MarkNotificationInboxRead =>
                BridgeEnvelope.Response(request, await _host.MarkNotificationInboxReadAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.SubmitAccountAppeal =>
                BridgeEnvelope.Response(request, await _host.SubmitAccountAppealAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.ReadCommunities =>
                BridgeEnvelope.Response(request, await _host.ReadCommunitiesAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.ExecuteCommunity =>
                BridgeEnvelope.Response(request, await _host.ExecuteCommunityAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.GetCommunityCreationOptions =>
                BridgeEnvelope.Response(request, await _host.GetCommunityCreationOptionsAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.CreateCommunity =>
                BridgeEnvelope.Response(request, await _host.CreateCommunityAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.ReadCommunityWorkspace =>
                BridgeEnvelope.Response(request, await _host.ReadCommunityWorkspaceAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.ReadCommunityLogs =>
                BridgeEnvelope.Response(request, await _host.ReadCommunityLogsAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.DeleteCommunityLog =>
                BridgeEnvelope.Response(request, await _host.DeleteCommunityLogAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.ReadCommunityDisband =>
                BridgeEnvelope.Response(request, await _host.ReadCommunityDisbandAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.ReadCommunityChat =>
                BridgeEnvelope.Response(request, await _host.ReadCommunityChatAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.ReadCommunityAnnouncements =>
                BridgeEnvelope.Response(request, await _host.ReadCommunityAnnouncementsAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.ReadCommunityShips =>
                BridgeEnvelope.Response(request, await _host.ReadCommunityShipsAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.ReadCommunityHangarSharing =>
                BridgeEnvelope.Response(request, await _host.ReadCommunityHangarSharingAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.SaveCommunityHangarSharing =>
                BridgeEnvelope.Response(request, await _host.SaveCommunityHangarSharingAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.ReadCommunityShipImage =>
                BridgeEnvelope.Response(request, await _host.ReadCommunityShipImageAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.ReportCommunityShipImage =>
                BridgeEnvelope.Response(request, await _host.ReportCommunityShipImageAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.ReadCommunityAnnouncementDetail =>
                BridgeEnvelope.Response(request, await _host.ReadCommunityAnnouncementDetailAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.ManageCommunityAnnouncements =>
                BridgeEnvelope.Response(request, await _host.ManageCommunityAnnouncementsAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.ReadCommunityChatDetail =>
                BridgeEnvelope.Response(request, await _host.ReadCommunityChatDetailAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.MarkCommunityChatRead =>
                BridgeEnvelope.Response(request, await _host.MarkCommunityChatReadAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.SendCommunityChat =>
                BridgeEnvelope.Response(request, await _host.SendCommunityChatAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.DisbandCommunity =>
                BridgeEnvelope.Response(request, await _host.DisbandCommunityAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.ReadCommunityMedia =>
                BridgeEnvelope.Response(request, await _host.ReadCommunityMediaAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.ReadCommunityProfile =>
                BridgeEnvelope.Response(request, await _host.ReadCommunityProfileAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.ReadCommunityAdmissions =>
                BridgeEnvelope.Response(request, await _host.ReadCommunityAdmissionsAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.ManageCommunityAdmissions =>
                BridgeEnvelope.Response(request, await _host.ManageCommunityAdmissionsAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.SaveCommunityProfile =>
                BridgeEnvelope.Response(request, await _host.SaveCommunityProfileAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.ReadCommunityRoles =>
                BridgeEnvelope.Response(request, await _host.ReadCommunityRolesAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.ReadCommunityMemberRole =>
                BridgeEnvelope.Response(request, await _host.ReadCommunityMemberRoleAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.SaveCommunityMemberRole =>
                BridgeEnvelope.Response(request, await _host.SaveCommunityMemberRoleAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.ReadCommunityMemberRemoval =>
                BridgeEnvelope.Response(request, await _host.ReadCommunityMemberRemovalAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.RemoveCommunityMember =>
                BridgeEnvelope.Response(request, await _host.RemoveCommunityMemberAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.ReadCommunityOwnershipTransfer =>
                BridgeEnvelope.Response(request, await _host.ReadCommunityOwnershipTransferAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.TransferCommunityOwnership =>
                BridgeEnvelope.Response(request, await _host.TransferCommunityOwnershipAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.ReadCommunityOwnershipExit =>
                BridgeEnvelope.Response(request, await _host.ReadCommunityOwnershipExitAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.LeaveCommunityWithSuccessor =>
                BridgeEnvelope.Response(request, await _host.LeaveCommunityWithSuccessorAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.SaveCommunityRoles =>
                BridgeEnvelope.Response(request, await _host.SaveCommunityRolesAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.PreviewCommunityInvite =>
                BridgeEnvelope.Response(request, await _host.PreviewCommunityInviteAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.AcceptCommunityInvite =>
                BridgeEnvelope.Response(request, await _host.AcceptCommunityInviteAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.SendCommunityInvite =>
                BridgeEnvelope.Response(request, await _host.SendCommunityInviteAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.ResumeCommunityInvite =>
                BridgeEnvelope.Response(request, await _host.ResumeCommunityInviteAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.ReadCommunityInvitationOutbox =>
                BridgeEnvelope.Response(request, await _host.ReadCommunityInvitationOutboxAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.ExecutePartyRoom =>
                BridgeEnvelope.Response(request, await _host.ExecutePartyRoomAsync(
                    RequireCurrentContext(request), request.Payload, cancellationToken)),
            AccountBridgeRequestNames.GetCompatibilityState =>
                ToCompatibilityResponse(
                    request,
                    await _host.GetCompatibilityStateAsync(
                        RequireCurrentContext(request),
                        cancellationToken)),
            AccountBridgeRequestNames.LinkLegacyAccount =>
                ToCompatibilityResponse(
                    request,
                    await _host.LinkLegacyAccountAsync(
                        RequireCurrentContext(request),
                        ParseLegacyCredential(request.Payload),
                        cancellationToken)),
            AccountBridgeRequestNames.CreateCompatibilityIdentity =>
                await CreateCompatibilityIdentityAsync(request, cancellationToken),
            AccountBridgeRequestNames.PatchPreferences =>
                ToProfileResponse(
                    request,
                    await _host.PatchPreferencesAsync(
                        RequireCurrentContext(request),
                        ParsePatch(request.Payload),
                        cancellationToken)),
            AccountBridgeRequestNames.ClearProfileCache =>
                BridgeEnvelope.Response(
                    request,
                    new
                    {
                        schemaVersion = AccountBridgeSchema.Version,
                        cleared = await _host.ClearProfileCacheAsync(
                            RequireCurrentContext(request),
                            cancellationToken)
                    }),
            AccountBridgeRequestNames.GetGameIdentityPolicy =>
                ToIdentityResponse(
                    request,
                    await _host.GetGameIdentityPolicyAsync(
                        RequireCurrentContext(request),
                        cancellationToken)),
            _ => throw new BridgeProtocolException(
                BridgeErrorCodes.InvalidEnvelope,
                "Unsupported account request.")
        };
    }

    private async Task<BridgeEnvelope> CancelLoginAsync(BridgeEnvelope request)
    {
        await _host.CancelLoginAsync();
        return BridgeEnvelope.Response(
            request,
            new { schemaVersion = AccountBridgeSchema.Version, cancelled = true },
            preserveRequestAccountContext: false);
    }

    private async Task<BridgeEnvelope> LogoutAsync(
        BridgeEnvelope request,
        CancellationToken cancellationToken)
    {
        await _host.LogoutAsync(RequireCurrentContext(request), cancellationToken);
        return BridgeEnvelope.Response(
            request,
            new { schemaVersion = AccountBridgeSchema.Version, state = "signedOut" },
            preserveRequestAccountContext: false);
    }

    private async Task<BridgeEnvelope> CreateCompatibilityIdentityAsync(
        BridgeEnvelope request,
        CancellationToken cancellationToken)
    {
        RejectUnknownProperties(request.Payload, "schemaVersion");
        return ToCompatibilityResponse(
            request,
            await _host.CreateCompatibilityIdentityAsync(
                RequireCurrentContext(request),
                cancellationToken));
    }

    private async Task<BridgeEnvelope> UpdateAvatarAsync(BridgeEnvelope request, CancellationToken token)
    {
        var result = await _host.UpdateAvatarAsync(RequireCurrentContext(request), request.Payload, token);
        PublishDomainInvalidation("account.avatarChanged", _host.Generation);
        return BridgeEnvelope.Response(request, result);
    }

    private static BridgeEnvelope ToSessionResponse(
        BridgeEnvelope request,
        AccountBridgeSessionProjection projection) =>
        BridgeEnvelope.Response(
            request,
            new
            {
                schemaVersion = AccountBridgeSchema.Version,
                state = projection.State,
                displayName = projection.DisplayName,
                avatarUrl = projection.AvatarUrl,
                avatarImageData = projection.AvatarImageData,
                maskedAccount = projection.MaskedAccount
            },
            projection.Context,
            preserveRequestAccountContext: false);

    private BridgeEnvelope ToProfileResponse(
        BridgeEnvelope request,
        AccountBridgeProfileProjection projection) =>
        BridgeEnvelope.Response(
            request,
            new
            {
                schemaVersion = AccountBridgeSchema.Version,
                profile = projection.Profile,
                source = projection.Source,
                cachedAtUtc = projection.CachedAtUtc,
                preferencesPolicy = new
                {
                    locales = projection.Locales,
                    timeZones = projection.TimeZones,
                    availableActions = _profileActions
                }
            });

    private static BridgeEnvelope ToPersonalProfileResponse(
        BridgeEnvelope request,
        StarBridge.Core.Profiles.PersonalProfileDocumentContract profile, bool editable = true) =>
        BridgeEnvelope.Response(
            request,
            new
            {
                schemaVersion = AccountBridgeSchema.Version,
                editable,
                profile = new
                {
                    isPublic = profile.IsPublic,
                    visibility = profile.Visibility,
                    revision = profile.Revision,
                    avatarStyle = profile.AvatarStyle,
                    wallpaperId = profile.WallpaperId,
                    identity = new
                    {
                        callSign = profile.Identity.Callsign,
                        gameHandle = profile.Identity.GameId,
                        avatarAssetId = profile.Identity.AvatarAssetId
                    },
                    content = profile.Content,
                    fleetAffiliation = profile.FleetAffiliation,
                    hangar = profile.Hangar is null ? null : new {
                        ships = profile.Hangar.Ships.Select(Hangar.HangarShipNames.PresentProfile).ToArray()
                    },
                    gameplayStatistics = profile.GameplayStatistics,
                    isGameplayStatisticsPublic = profile.IsGameplayStatisticsPublic
                }
            });

    private async Task<BridgeEnvelope> DispatchMigrationAsync(BridgeEnvelope request, CancellationToken token)
    {
        var action = request.Name switch
        {
            AccountBridgeRequestNames.PreviewLegacyProfileMigration => "preview",
            AccountBridgeRequestNames.ConfirmLegacyProfileMigration => "confirm",
            _ => "status"
        };
        string? previewId = null;
        var replaceExisting = false;
        StarBridge.HostRuntime.Auth.LegacyProfileCredential? credentials = null;
        if (action == "preview" && request.Payload.TryGetProperty("accountName", out _))
        {
            var accountName = ReadBoundedString(request.Payload, "accountName", 254);
            if (!request.Payload.TryGetProperty("password", out var secret) ||
                secret.ValueKind != JsonValueKind.String || secret.GetString() is not { Length: > 0 and <= 1024 } password)
                throw new BridgeProtocolException(BridgeErrorCodes.InvalidEnvelope, "Legacy credential is required.");
            credentials = new(accountName, password);
        }
        if (action == "confirm")
        {
            previewId = ReadBoundedString(request.Payload, "previewId", 64);
            if (string.IsNullOrWhiteSpace(previewId) ||
                !request.Payload.TryGetProperty("replaceExisting", out var replace) ||
                replace.ValueKind is not (JsonValueKind.True or JsonValueKind.False))
                throw new BridgeProtocolException(BridgeErrorCodes.InvalidEnvelope, "Migration consent is required.");
            replaceExisting = replace.GetBoolean();
        }
        var view = await _host.MigrateLegacyProfileAsync(
            RequireCurrentContext(request), action, previewId, replaceExisting, token, credentials);
        if (action == "confirm" && view.State == "completed")
        {
            lock (_eventGate)
                _pendingEvents.Add(BridgeEnvelope.Event("personalProfile.changed", _host.Generation,
                    ++_eventSequence, new { schemaVersion = AccountBridgeSchema.Version }));
        }
        return BridgeEnvelope.Response(request, new { schemaVersion = AccountBridgeSchema.Version, migration = view });
    }

    private static BridgeEnvelope ToOfficialFleetResponse(
        BridgeEnvelope request,
        AccountBridgeOfficialFleetProjection projection) =>
        BridgeEnvelope.Response(
            request,
            new
            {
                schemaVersion = AccountBridgeSchema.Version,
                state = projection.State,
                fleet = projection.Fleet is null
                    ? null
                    : new
                    {
                        sourceRef = projection.Fleet.SourceRef,
                        sid = projection.Fleet.Sid,
                        name = projection.Fleet.Name,
                        logoUrl = projection.Fleet.LogoUrl,
                        officialRankName = projection.Fleet.OfficialRankName,
                        officialRankValue = projection.Fleet.OfficialRankValue
                    },
                freshness = projection.Freshness,
                resourceVersion = projection.ResourceVersion,
                observedAtUtc = projection.ObservedAtUtc
            });

    private static BridgeEnvelope ToIdentityResponse(
        BridgeEnvelope request,
        AccountBridgeIdentityProjection projection) =>
        BridgeEnvelope.Response(
            request,
            new
            {
                schemaVersion = AccountBridgeSchema.Version,
                state = projection.State,
                authoritativeHandle = projection.AuthoritativeHandle,
                sensitiveWritesAllowed = projection.SensitiveWritesAllowed
            });

    private static BridgeEnvelope ToCompatibilityResponse(
        BridgeEnvelope request,
        AccountBridgeCompatibilityProjection projection) =>
        BridgeEnvelope.Response(
            request,
            new
            {
                schemaVersion = AccountBridgeSchema.Version,
                identityState = projection.IdentityState,
                relayState = projection.RelayState,
                storedLegacyCredentialAvailable = projection.StoredLegacyCredentialAvailable,
                legacyFeaturesAvailable = projection.LegacyFeaturesAvailable,
                availableActions = projection.AvailableActions
            });

    private BridgeAccountContext RequireCurrentContext(BridgeEnvelope request)
    {
        var supplied = request.AccountContext;
        var current = _host.CurrentContext;
        if (supplied is not { IsComplete: true } ||
            current is null ||
            !supplied.Environment.Equals(current.Environment, StringComparison.OrdinalIgnoreCase) ||
            !supplied.Authority.Equals(current.Authority, StringComparison.OrdinalIgnoreCase) ||
            !supplied.Subject.Equals(current.Subject, StringComparison.Ordinal))
        {
            throw new BridgeProtocolException(
                BridgeErrorCodes.AccountContextRequired,
                "Account context does not match the active account.");
        }

        return current;
    }

    private static void RequireSchemaVersion(JsonElement payload)
    {
        if (payload.ValueKind != JsonValueKind.Object ||
            !payload.TryGetProperty("schemaVersion", out var version) ||
            version.ValueKind != JsonValueKind.Number ||
            !version.TryGetInt32(out var value) ||
            value != AccountBridgeSchema.Version)
        {
            throw new BridgeProtocolException(
                BridgeErrorCodes.InvalidEnvelope,
                "Account payload schema is unsupported.");
        }
    }

    private static AccountBridgePreferencePatch ParsePatch(JsonElement payload)
    {
        if (!payload.TryGetProperty("patch", out var patch) ||
            patch.ValueKind != JsonValueKind.Object)
        {
            throw new BridgeProtocolException(
                BridgeErrorCodes.InvalidEnvelope,
                "Profile patch body is required.");
        }

        var result = new AccountBridgePreferencePatch(
            ReadPatchField(patch, "locale"),
            ReadPatchField(patch, "timeZone"));
        if (result.IsEmpty)
        {
            throw new BridgeProtocolException(
                BridgeErrorCodes.InvalidEnvelope,
                "Profile patch must contain a supported field.");
        }

        foreach (var property in patch.EnumerateObject())
        {
            if (property.Name is not ("locale" or "timeZone"))
            {
                throw new BridgeProtocolException(
                    BridgeErrorCodes.InvalidEnvelope,
                    "Profile patch contains an unsupported field.");
            }
        }

        return result;
    }

    private static PersonalProfilePresentationUpdateContract ParsePersonalProfileUpdate(
        JsonElement payload)
    {
        RejectUnknownProperties(payload, "schemaVersion", "patch");
        if (!payload.TryGetProperty("patch", out var patch) ||
            patch.ValueKind != JsonValueKind.Object)
        {
            throw new BridgeProtocolException(
                BridgeErrorCodes.InvalidEnvelope,
                "Personal profile patch body is required.");
        }

        RejectUnknownProperties(
            patch,
            "expectedRevision",
            "visibility",
            "callSign",
            "avatarStyle",
            "wallpaperId",
            "introduction",
            "modules");
        if (!patch.TryGetProperty("expectedRevision", out var revisionElement) ||
            revisionElement.ValueKind != JsonValueKind.Number ||
            !revisionElement.TryGetInt64(out var expectedRevision) ||
            expectedRevision < 0)
        {
            throw new BridgeProtocolException(
                BridgeErrorCodes.InvalidEnvelope,
                "expectedRevision must be a non-negative integer.");
        }

        var visibility = ReadRequiredBoundedString(patch, "visibility", 32);
        if (visibility is not ("public" or "friendsAndMainFleet" or "friendsOnly" or "private"))
        {
            throw new BridgeProtocolException(
                BridgeErrorCodes.InvalidEnvelope,
                "visibility is unsupported.");
        }

        if (!patch.TryGetProperty("avatarStyle", out var avatarStyleElement) ||
            avatarStyleElement.ValueKind != JsonValueKind.Number ||
            !avatarStyleElement.TryGetInt32(out var avatarStyle) ||
            avatarStyle is < 0 or > 3)
        {
            throw new BridgeProtocolException(
                BridgeErrorCodes.InvalidEnvelope,
                "avatarStyle must be between 0 and 3.");
        }

        if (!patch.TryGetProperty("modules", out var modulesElement) ||
            modulesElement.ValueKind != JsonValueKind.Array ||
            modulesElement.GetArrayLength() > PersonalProfileContractPolicy.MaximumModules)
        {
            throw new BridgeProtocolException(
                BridgeErrorCodes.InvalidEnvelope,
                "modules must be a bounded array.");
        }

        var modules = new List<PersonalProfileModuleContract>();
        foreach (var module in modulesElement.EnumerateArray())
        {
            if (module.ValueKind != JsonValueKind.Object)
            {
                throw new BridgeProtocolException(
                    BridgeErrorCodes.InvalidEnvelope,
                    "modules must contain objects.");
            }
            RejectUnknownProperties(module, "id", "span", "isVisible", "position");
            if (!module.TryGetProperty("span", out var spanElement) ||
                !spanElement.TryGetInt32(out var span) ||
                !module.TryGetProperty("position", out var positionElement) ||
                !positionElement.TryGetInt32(out var position) ||
                !module.TryGetProperty("isVisible", out var visibleElement) ||
                visibleElement.ValueKind is not (JsonValueKind.True or JsonValueKind.False))
            {
                throw new BridgeProtocolException(
                    BridgeErrorCodes.InvalidEnvelope,
                    "module layout is invalid.");
            }
            modules.Add(new PersonalProfileModuleContract(
                ReadRequiredBoundedString(module, "id", 64),
                span,
                visibleElement.GetBoolean(),
                modules.Count,
                position));
        }

        return new PersonalProfilePresentationUpdateContract(
            expectedRevision,
            visibility,
            ReadRequiredBoundedString(patch, "callSign", 32),
            avatarStyle,
            ReadRequiredBoundedString(patch, "wallpaperId", 80),
            ReadBoundedString(patch, "introduction", PersonalProfileContractPolicy.MaximumIntroductionLength),
            modules.ToArray());
    }

    private static AccountBridgeLegacyCredential? ParseLegacyCredential(JsonElement payload)
    {
        RejectUnknownProperties(payload, "schemaVersion", "credential");
        if (!payload.TryGetProperty("credential", out var credential) ||
            credential.ValueKind == JsonValueKind.Null)
        {
            return null;
        }

        if (credential.ValueKind != JsonValueKind.Object)
        {
            throw new BridgeProtocolException(
                BridgeErrorCodes.InvalidEnvelope,
                "Legacy credential must be an object or null.");
        }

        RejectUnknownProperties(credential, "accountName", "password");
        var accountName = ReadRequiredBoundedString(credential, "accountName", 320);
        var password = ReadRequiredBoundedString(credential, "password", 1024, trim: false);
        return new AccountBridgeLegacyCredential(accountName, password);
    }

    private static string ReadRequiredBoundedString(
        JsonElement source,
        string name,
        int maximumLength,
        bool trim = true)
    {
        if (!source.TryGetProperty(name, out var value) ||
            value.ValueKind != JsonValueKind.String)
        {
            throw new BridgeProtocolException(
                BridgeErrorCodes.InvalidEnvelope,
                $"{name} must be a string.");
        }

        var result = value.GetString() ?? string.Empty;
        if (trim)
        {
            result = result.Trim();
        }

        if (string.IsNullOrWhiteSpace(result) || result.Length > maximumLength)
        {
            throw new BridgeProtocolException(
                BridgeErrorCodes.InvalidEnvelope,
                $"{name} has an invalid length.");
        }

        return result;
    }

    private static string ReadBoundedString(
        JsonElement source,
        string name,
        int maximumLength)
    {
        if (!source.TryGetProperty(name, out var value) || value.ValueKind != JsonValueKind.String)
        {
            throw new BridgeProtocolException(
                BridgeErrorCodes.InvalidEnvelope,
                $"{name} must be a string.");
        }

        var result = (value.GetString() ?? string.Empty).Trim();
        if (result.Length > maximumLength)
        {
            throw new BridgeProtocolException(
                BridgeErrorCodes.InvalidEnvelope,
                $"{name} has an invalid length.");
        }
        return result;
    }

    private static void RejectUnknownProperties(
        JsonElement source,
        params string[] allowedNames)
    {
        var allowed = allowedNames.ToHashSet(StringComparer.Ordinal);
        foreach (var property in source.EnumerateObject())
        {
            if (!allowed.Contains(property.Name))
            {
                throw new BridgeProtocolException(
                    BridgeErrorCodes.InvalidEnvelope,
                    "Account payload contains an unsupported field.");
            }
        }
    }

    private static AccountBridgePatchField ReadPatchField(JsonElement patch, string name)
    {
        if (!patch.TryGetProperty(name, out var value))
        {
            return AccountBridgePatchField.Unspecified;
        }

        return value.ValueKind switch
        {
            JsonValueKind.Null => AccountBridgePatchField.Set(null),
            JsonValueKind.String => AccountBridgePatchField.Set(value.GetString()),
            _ => throw new BridgeProtocolException(
                BridgeErrorCodes.InvalidEnvelope,
                "Profile patch fields must be strings or null.")
        };
    }

    private void OnAccountChanged(long generation)
    {
        BridgeEnvelope envelope;
        Action<BridgeEnvelope>? publish = null;
        lock (_eventGate)
        {
            envelope = BridgeEnvelope.Event(
                "account.changed",
                generation,
                ++_eventSequence,
                new { schemaVersion = AccountBridgeSchema.Version });
            if (_activeDispatches > 0)
            {
                _pendingEvents.Add(envelope);
            }
            else
            {
                publish = EventReady;
            }
        }

        publish?.Invoke(envelope);
    }

    private void BeginDispatchEventCollection()
    {
        lock (_eventGate)
        {
            if (_activeDispatches++ == 0) _pendingEvents.Clear();
        }
    }

    private AccountBridgeDispatchResult Result(BridgeEnvelope response)
    {
        lock (_eventGate)
        {
            // No reader may clear another reader's buffered invalidations.
            // Flush the ordered batch with the final response, preserving the
            // existing response-before-account.changed transport contract.
            if (--_activeDispatches > 0) return new AccountBridgeDispatchResult(response, []);
            var events = _pendingEvents.ToArray();
            _pendingEvents.Clear();
            return new AccountBridgeDispatchResult(response, events);
        }
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;
        _host.AccountChanged -= OnAccountChanged;
        _dispatchGate.Dispose();
    }
}
