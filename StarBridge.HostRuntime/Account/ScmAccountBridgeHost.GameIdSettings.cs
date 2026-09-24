using StarBridge.HostRuntime.Privacy;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Account;

internal interface IGameIdSettingsRemote
{
    Task<GameIdSettingsSnapshot> ReadGameIdAsync(BridgeAccountContext owner, long generation, CancellationToken token);
    Task<GameIdSettingsSnapshot> SaveGameIdAsync(BridgeAccountContext owner, long generation, long revision, string stamp, int locations, CancellationToken token);
}
internal sealed partial class ScmAccountBridgeHost : IGameIdSettingsRemote
{
    public Task<GameIdSettingsSnapshot> ReadGameIdAsync(BridgeAccountContext owner, long generation, CancellationToken token) =>
        WithEventSessionAsync(owner, generation, false, (writer, bearer, _, ct) => writer.ReadGameIdAsync(bearer, ct), token);
    public Task<GameIdSettingsSnapshot> SaveGameIdAsync(BridgeAccountContext owner, long generation, long revision, string stamp, int locations, CancellationToken token) =>
        WithEventSessionAsync(owner, generation, false, (writer, bearer, current, ct) => writer.SaveGameIdAsync(bearer, revision, stamp, locations, current, ct), token);
}
