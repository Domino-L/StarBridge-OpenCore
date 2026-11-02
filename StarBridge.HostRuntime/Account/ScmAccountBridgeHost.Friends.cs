namespace StarBridge.HostRuntime.Account;

using System.Text.Json;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.Friends;
using StarBridge.NativeBridge;

internal sealed partial class ScmAccountBridgeHost
{
    public async Task<object> WaitSocialActivityAsync(BridgeAccountContext context, JsonElement payload, CancellationToken token)
        => await WaitActivityAsync(context, payload, token, false);

    public async Task<object> WaitCommunityActivityAsync(BridgeAccountContext context, JsonElement payload, CancellationToken token)
        => await WaitActivityAsync(context, payload, token, true);

    private async Task<object> WaitActivityAsync(BridgeAccountContext context, JsonElement payload, CancellationToken token, bool community)
    {
        FriendsReader.ParseActivity(payload);
        var session = await ReadDirectRelaySessionAsync(context, token).ConfigureAwait(false);
        var generation = Generation;
        if (_reauthorizationRequired || _credentialTemporarilyUnavailable)
            throw new AccountBridgeHostException(AccountBridgeStableErrors.ReauthorizationRequired);
        var reader = _friends ?? throw new AccountBridgeHostException("friends.read_unavailable");
        // The snapshot can recover a previously committed refresh. The wait
        // itself runs outside the write barrier without delaying send/logout.
        var result = await reader.WaitActivityAsync(session.AccessToken, payload, token, community);
        if (_disposed || generation != Generation) throw new BridgeStaleGenerationException(generation, Generation);
        RequireSameRelaySession(RequireRelaySession(context), session);
        if (!community) QueueBackgroundFriendActivity(context, generation, session.AccessToken);
        return result;
    }

    public async Task<FriendsView> ReadFriendsAsync(BridgeAccountContext context, JsonElement payload, CancellationToken token)
    {
        var query = FriendsReader.ParseQuery(payload);
        var session = RequireRelaySession(context);
        var generation = Generation;
        if (_reauthorizationRequired || _credentialTemporarilyUnavailable)
            throw new AccountBridgeHostException(AccountBridgeStableErrors.ReauthorizationRequired);
        var reader = _friends ?? throw new AccountBridgeHostException("friends.read_unavailable");
        var observe = query is null && ObservePlayerActivity();
        var sequence = Interlocked.Increment(ref _playerActivitySequence);
        var displayLease = query is null
            ? await (FriendsReadStarting?.Invoke(context, generation, FriendsReader.WantsCachedDisplay(payload), token) ?? Task.FromResult<OfflineFriendsReadLease?>(null)) : null;
        var displayOutcome = OfflineFriendsReadOutcome.Abandoned;
        FriendsView? displayResult = null;
        void CurrentSearch() {
            if (_disposed || generation != Generation) throw new BridgeStaleGenerationException(generation, Generation);
            RequireSameRelaySession(RequireRelaySession(context), session);
        }
        try
        {
            var result = await SendRelayRequestAsync(session,
                (active, ct) => query is not null && active.Scm is { } scm
                    ? reader.ReadScmSearchAsync(active.AccessToken, query, (q, cancellation) => _oauth.SearchParticipantsAsync(scm, q, cancellation),
                        ct, FriendScope(context, generation), CurrentSearch)
                    : query is null && active.Scm is { } directoryScm
                        ? reader.ReadScmDirectoryAsync(active.AccessToken, (id, cancellation) => _oauth.ReadFriendIdentityAsync(directoryScm, id, cancellation),
                            ct, FriendScope(context, generation), observe, CurrentSearch)
                        : reader.ReadAsync(active.AccessToken, query, ct, FriendScope(context, generation), observe, sharing: true), token);
            if (_disposed || generation != Generation) throw new BridgeStaleGenerationException(generation, Generation);
            RequireSameRelaySession(RequireRelaySession(context), result.ActiveSession);
            CommitSharingSession(session, result.ActiveSession);
            if (observe) PublishPlayerActivity(context, generation, sequence, Notifications.PlayerActivitySources.Friends(result.Result));
            displayResult = result.Result;
            displayOutcome = OfflineFriendsReadOutcome.Success;
            return result.Result;
        }
        catch (ScmApiAuthenticationException)
        { displayOutcome = OfflineFriendsReadOutcome.Rejected; throw new AccountBridgeHostException(AccountBridgeStableErrors.ReauthorizationRequired); }
        catch (AccountBridgeHostException error)
        {
            displayOutcome = error.Code == "friends.read_transient" && error.Retryable
                ? OfflineFriendsReadOutcome.Transient : OfflineFriendsReadOutcome.Rejected;
            throw;
        }
        finally
        {
            FinishFriendsDisplay(displayLease, generation, displayOutcome, displayResult);
        }
    }

    private static string FriendScope(BridgeAccountContext context, long generation) => JsonSerializer.Serialize(context) + ":" + generation;

    public async Task<object> ReadDirectMessagesAsync(BridgeAccountContext context, JsonElement payload, CancellationToken token)
    {
        FriendsReader.ParseChatRead(payload);
        var session = RequireRelaySession(context); var generation = Generation;
        if (_reauthorizationRequired || _credentialTemporarilyUnavailable)
            throw new AccountBridgeHostException(AccountBridgeStableErrors.ReauthorizationRequired);
        var reader = _friends ?? throw new AccountBridgeHostException("directMessages.unavailable");
        try {
            var result = await SendRelayRequestAsync(session,
                (active, ct) => reader.ReadChatAsync(active.AccessToken, payload, ct, FriendScope(context, generation), JsonSerializer.Serialize(context)), token);
            if (_disposed || generation != Generation) throw new BridgeStaleGenerationException(generation, Generation);
            RequireSameRelaySession(RequireRelaySession(context), result.ActiveSession);
            _session = result.ActiveSession.Scm;
            return result.Result;
        } catch (ScmApiAuthenticationException) { throw new AccountBridgeHostException(AccountBridgeStableErrors.ReauthorizationRequired); }
    }

    public async Task<object> MarkDirectMessagesReadAsync(BridgeAccountContext context, JsonElement payload, CancellationToken token)
    {
        FriendsReader.ParseChatMarkRead(payload);
        var session = RequireRelaySession(context); var generation = Generation;
        if (_reauthorizationRequired || _credentialTemporarilyUnavailable)
            throw new AccountBridgeHostException(AccountBridgeStableErrors.ReauthorizationRequired);
        var reader = _friends ?? throw new AccountBridgeHostException("directMessages.unavailable");
        void Current() {
            if (_disposed || generation != Generation) throw new BridgeStaleGenerationException(generation, Generation);
            RequireSameRelaySession(RequireRelaySession(context), session);
        }
        try {
            var result = await SendRelayRequestAsync(session,
                (active, ct) => reader.MarkChatReadAsync(active.AccessToken, payload, ct, FriendScope(context, generation), Current), token);
            Current();
            _session = result.ActiveSession.Scm;
            return result.Result;
        } catch (ScmApiAuthenticationException) { throw new AccountBridgeHostException(AccountBridgeStableErrors.ReauthorizationRequired); }
    }

    public async Task<object> SendDirectMessageAsync(BridgeAccountContext context, JsonElement payload, CancellationToken token)
    {
        FriendsReader.ParseChatSend(payload);
        var session = RequireRelaySession(context); var generation = Generation;
        if (_reauthorizationRequired || _credentialTemporarilyUnavailable)
            throw new AccountBridgeHostException(AccountBridgeStableErrors.ReauthorizationRequired);
        var reader = _friends ?? throw new AccountBridgeHostException("directMessages.unavailable");
        void Current() {
            if (_disposed || generation != Generation) throw new BridgeStaleGenerationException(generation, Generation);
            RequireSameRelaySession(RequireRelaySession(context), session);
        }
        try {
            var result = await SendRelayRequestAsync(session,
                (active, ct) => reader.SendChatAsync(active.AccessToken, payload, ct, FriendScope(context, generation), Current), token);
            Current();
            _session = result.ActiveSession.Scm;
            return result.Result;
        } catch (ScmApiAuthenticationException) { throw new AccountBridgeHostException(AccountBridgeStableErrors.ReauthorizationRequired); }
    }

    public async Task<FriendCommandView> ExecuteFriendAsync(BridgeAccountContext context, JsonElement payload, CancellationToken token)
    {
        FriendsReader.ParseCommand(payload);
        var session = RequireRelaySession(context);
        var generation = Generation;
        if (_reauthorizationRequired || _credentialTemporarilyUnavailable)
            throw new AccountBridgeHostException(AccountBridgeStableErrors.ReauthorizationRequired);
        var reader = _friends ?? throw new AccountBridgeHostException("friends.read_unavailable");
        OfflineFriendsReadLease? displayLease;
        try { displayLease = await (FriendsReadStarting?.Invoke(context, generation, false, token) ?? Task.FromResult<OfflineFriendsReadLease?>(null)); }
        catch (AccountBridgeHostException error) when (error.Code == "friends.read_transient" && error.Retryable)
        { return new("rejected", "refreshRequired"); } // Guard failed before any preflight or POST.
        var displayOutcome = OfflineFriendsReadOutcome.Abandoned;
        FriendsView? displayResult = null;
        void Current() {
            if (_disposed || generation != Generation) throw new BridgeStaleGenerationException(generation, Generation);
            RequireSameRelaySession(RequireRelaySession(context), session);
        }
        try {
            var result = await SendRelayRequestAsync(session,
                (active, ct) => reader.ExecuteAsync(active.AccessToken, payload, ct, FriendScope(context, generation), Current,
                    active.Scm is { } scm ? (q, cancellation) => _oauth.SearchParticipantsAsync(scm, q, cancellation) : null), token);
            Current();
            _session = result.ActiveSession.Scm;
            displayResult = result.Result.Directory;
            displayOutcome = result.Result.Status switch {
                "accepted" when displayResult is not null => OfflineFriendsReadOutcome.ConfirmedWrite,
                "rejected" when result.Result.Error is "busy" or "rateLimited" or "cooldown" or "tooManyPending" or "rejected"
                    => OfflineFriendsReadOutcome.Unchanged,
                "rejected" when result.Result.Error is "identityUnavailable" or "forbidden" => OfflineFriendsReadOutcome.Rejected,
                _ => OfflineFriendsReadOutcome.Abandoned
            };
            return result.Result;
        } catch (ScmApiAuthenticationException) {
            displayOutcome = OfflineFriendsReadOutcome.Rejected;
            throw new AccountBridgeHostException(AccountBridgeStableErrors.ReauthorizationRequired);
        } finally { FinishFriendsDisplay(displayLease, generation, displayOutcome, displayResult); }
    }
}
