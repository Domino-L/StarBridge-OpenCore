using StarBridge.Core.Friends;
using StarBridge.HostRuntime.Privacy;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Account;

internal interface IFriendSharingRemote
{
    Task<FriendSharingRemoteSnapshot> ReadFriendSharingAsync(BridgeAccountContext owner, long generation, CancellationToken token);
    Task<FriendSharingRemoteSnapshot> SaveFriendSharingAsync(BridgeAccountContext owner, long generation, long revision, string operation,
        FriendSharedFields fields, CancellationToken token);
    Task<string> WriteFriendLiveAsync(PrivacyPublicationInput input, string action, long revision, string? session,
        long sequence, FriendSharingSource? source, CancellationToken token);
}

internal sealed partial class ScmAccountBridgeHost : IFriendSharingRemote
{
    public Task<FriendSharingRemoteSnapshot> ReadFriendSharingAsync(BridgeAccountContext owner, long generation, CancellationToken token) =>
        WithEventSessionAsync(owner, generation, false, (writer, bearer, _, ct) => writer.ReadFriendsAsync(bearer, ct), token);
    public Task<FriendSharingRemoteSnapshot> SaveFriendSharingAsync(BridgeAccountContext owner, long generation, long revision,
        string operation, FriendSharedFields fields, CancellationToken token) =>
        WithEventSessionAsync(owner, generation, false, (writer, bearer, current, ct) => writer.SaveFriendsAsync(bearer, revision, operation, fields, current, ct), token);
    public Task<string> WriteFriendLiveAsync(PrivacyPublicationInput input, string action, long revision, string? session,
        long sequence, FriendSharingSource? source, CancellationToken token) =>
        WithEventSessionAsync(input.Owner, input.Generation, action is not ("stop" or "offline"),
            (writer, bearer, current, ct) => writer.WriteFriendsLiveAsync(bearer, action, revision, session, sequence, source, current, ct), token);
}
