using StarBridge.Core.Friends;
using StarBridge.Core.Presence;

namespace StarBridge.HostRuntime.Privacy;

internal sealed record FriendSharingPublicationSnapshot(PrivacyPublicationInput Input,
    long Revision, FriendSharedFields Fields, bool Consent, PlayerPresenceVisibilityMode Visibility)
{
    internal bool Enabled => Consent && Input.IdentityConfirmed && Revision > 0 &&
        Fields != FriendSharedFields.None &&
        Visibility is PlayerPresenceVisibilityMode.Online or PlayerPresenceVisibilityMode.InGame;
}

/// <summary>Uses the existing Game.log snapshot; never creates a second listener.</summary>
internal static class FriendSharingPublicationSource
{
    internal static FriendSharingSource Build(FriendSharingPublicationSnapshot state)
    {
        new FriendSharingPreferences(state.Fields).Validate();
        if (!state.Enabled) throw new InvalidOperationException("Friend publication is not authorized.");
        var game = state.Input.Game;
        var playing = state.Input.GameVersion is not null;
        var connected = playing && game.Server.State == "connected";
        bool Has(FriendSharedFields fields) => (state.Fields & fields) != 0;
        var needsServer = Has(FriendSharedFields.ServerRelation | FriendSharedFields.ServerDetails | FriendSharedFields.Location);
        var ship = playing && Has(FriendSharedFields.Ship) && game.Ship.State == "confirmed";
        var location = connected && Has(FriendSharedFields.Location) && game.Location.CanSynchronize && game.Location.State == "confirmed";
        // Neither timestamp is client-authored. Transport must omit both; Relay
        // stamps receipt time and maintains last-online evidence independently.
        return new(default, playing ? "InGame" : "AppOnline",
            connected && needsServer ? game.Server.Shard : null,
            connected && Has(FriendSharedFields.ServerDetails) ? game.Server.Region : null,
            ship ? game.Ship.EnglishName : null, location ? game.Location.EnglishName : null,
            connected && needsServer, ship, location, null);
    }
}

/// <summary>
/// Serialized session lifecycle, driven by the owning runtime's existing tick.
/// Delegates must authenticate the captured Input owner/generation, not a later
/// login. No persisted source queue and no replay of uncertain publications.
/// </summary>
internal sealed class FriendSharingPublication(
    Func<FriendSharingPublicationSnapshot?> current,
    Func<FriendSharingPublicationSnapshot, CancellationToken, Task<string>> start,
    Func<FriendSharingPublicationSnapshot, string, long, FriendSharingSource, CancellationToken, Task> publish,
    Func<FriendSharingPublicationSnapshot, string, CancellationToken, Task> withdraw)
{
    private readonly SemaphoreSlim _gate = new(1, 1);
    private FriendSharingPublicationSnapshot? _active;
    private string? _session;
    private long _sequence;
    private bool _withdrawOnly;

    internal async Task TickAsync(CancellationToken cancellation = default)
    {
        if (!await _gate.WaitAsync(0, cancellation).ConfigureAwait(false)) return;
        try
        {
            var next = current();
            if (_session is not null && (_withdrawOnly || !Same(_active!, next)))
            {
                await WithdrawAsync(cancellation).ConfigureAwait(false);
                next = current();
            }
            if (next is null || !next.Enabled) return;
            new FriendSharingPreferences(next.Fields).Validate();
            if (_session is null)
            {
                var session = await start(next, cancellation).ConfigureAwait(false);
                if (!Guid.TryParseExact(session, "N", out _)) throw new InvalidOperationException("Invalid friend session.");
                _active = next; _session = session; _sequence = 0;
            }
            // Settings, visibility or account may have changed during start.
            next = current();
            if (!Same(_active!, next))
            {
                await WithdrawAsync(cancellation).ConfigureAwait(false);
                return;
            }
            var sequence = checked(++_sequence);
            await publish(next!, _session!, sequence, FriendSharingPublicationSource.Build(next!), cancellation).ConfigureAwait(false);
            if (!Same(next!, current())) await WithdrawAsync(cancellation).ConfigureAwait(false);
        }
        catch
        {
            // A failed send may already have arrived. Retire the session before
            // any positive retry; never replay its source or sequence.
            _withdrawOnly = _session is not null;
            throw;
        }
        finally { _gate.Release(); }
    }

    // The owner must revoke/disable the current snapshot before calling this;
    // this class owns sessions, not the account's durable consent choice.
    internal async Task StopAsync(CancellationToken cancellation = default)
    {
        await _gate.WaitAsync(cancellation).ConfigureAwait(false);
        try
        {
            _withdrawOnly = _session is not null;
            await WithdrawAsync(cancellation).ConfigureAwait(false);
        }
        finally { _gate.Release(); }
    }

    private async Task WithdrawAsync(CancellationToken cancellation)
    {
        if (_session is null) return;
        _withdrawOnly = true;
        await withdraw(_active!, _session, cancellation).ConfigureAwait(false);
        _session = null; _active = null; _sequence = 0; _withdrawOnly = false;
    }

    private static bool Same(FriendSharingPublicationSnapshot previous, FriendSharingPublicationSnapshot? next) =>
        next is not null && next.Enabled && previous.Input.Owner == next.Input.Owner &&
        previous.Input.Generation == next.Input.Generation && previous.Input.Handle == next.Input.Handle &&
        previous.Revision == next.Revision && previous.Fields == next.Fields;
}
