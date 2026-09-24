namespace StarBridge.HostRuntime.Account;

using System.Text.Json;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.Friends;
using StarBridge.NativeBridge;

internal sealed partial class ScmAccountBridgeHost
{
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
        try
        {
            var result = await SendRelayRequestAsync(session,
                (active, ct) => reader.ReadAsync(active.AccessToken, query, ct, FriendScope(context, generation), observe, sharing: true), token);
            if (_disposed || generation != Generation) throw new BridgeStaleGenerationException(generation, Generation);
            RequireSameRelaySession(RequireRelaySession(context), result.ActiveSession);
            _session = result.ActiveSession.Scm;
            if (observe) PublishPlayerActivity(context, generation, sequence, Notifications.PlayerActivitySources.Friends(result.Result));
            return result.Result;
        }
        catch (ScmApiAuthenticationException)
        { throw new AccountBridgeHostException(AccountBridgeStableErrors.ReauthorizationRequired); }
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
        void Current() {
            if (_disposed || generation != Generation) throw new BridgeStaleGenerationException(generation, Generation);
            RequireSameRelaySession(RequireRelaySession(context), session);
        }
        try {
            var result = await SendRelayRequestAsync(session,
                (active, ct) => reader.ExecuteAsync(active.AccessToken, payload, ct, FriendScope(context, generation), Current), token);
            Current();
            _session = result.ActiveSession.Scm;
            return result.Result;
        } catch (ScmApiAuthenticationException) { throw new AccountBridgeHostException(AccountBridgeStableErrors.ReauthorizationRequired); }
    }
}
