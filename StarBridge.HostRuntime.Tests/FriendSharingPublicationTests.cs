using StarBridge.Core.Friends;
using StarBridge.Core.Presence;
using StarBridge.HostRuntime.Privacy;
using StarBridge.HostRuntime.Presence;

internal static class FriendSharingPublicationTests
{
    internal static async Task Verify()
    {
        var input = new PrivacyPublicationInput(new("test", "legacy", "synthetic-friend"), 1,
            "Synthetic_Handle", true, "LIVE", new(new("connected", "US", "server"),
                new("confirmed", "place"), new("confirmed", "ship-id", "ship")));
        var state = new FriendSharingPublicationSnapshot(input, 1, FriendSharedFields.All, true,
            PlayerPresenceVisibilityMode.Online);
        for (var fields = 1; fields <= 63; fields++)
        {
            var source = FriendSharingPublicationSource.Build(state with { Fields = (FriendSharedFields)fields });
            Check((source.Ship is not null) == ((fields & 8) != 0), "ship bit");
            Check((source.Location is not null) == ((fields & 16) != 0), "location bit");
            Check((source.ServerRegion is not null) == ((fields & 4) != 0), "details bit");
            Check((source.ServerId is not null) == ((fields & 22) != 0), "server evidence bits");
            Check(source.ObservedAt == default && source.LastOnlineAt is null, "no client timestamps");
        }
        var stopped = FriendSharingPublicationSource.Build(state with { Input = input with { GameVersion = null } });
        Check(stopped is { Presence: "AppOnline", Ship: null, Location: null, ServerId: null }, "game exit clears stale fields");
        var away = FriendSharingPublicationSource.Build(state with { Input = input with { GameVersion = null, AppAway = true } });
        Check(away is { Presence: "Away", Ship: null, Location: null, ServerId: null }, "app inactivity stays online but publishes Away");
        Check(FriendSharingPublicationSource.Build(state with { Input = input with { AppAway = true } }).Presence == "InGame",
            "an active game overrides app inactivity");
        var unknown = FriendSharingPublicationSource.Build(state with { Input = input with { Game = GameLogSessionSnapshot.Empty } });
        Check(unknown.Ship is null && unknown.Location is null && unknown.ServerId is null, "unconfirmed evidence omitted");

        FriendSharingPublicationSnapshot? current = state with { Consent = false };
        var starts = 0; var sends = 0; var withdrawals = 0;
        var failSend = false; var failWithdraw = false;
        var queueTimeout = false;
        var sequences = new List<long>();
        var owners = new List<long>();
        var publisher = new FriendSharingPublication(() => current,
            (_, _) => { starts++; return Task.FromResult(Guid.NewGuid().ToString("N")); },
            (snapshot, _, sequence, _, _) =>
            {
                sends++; sequences.Add(sequence); owners.Add(snapshot.Input.Generation);
                if (queueTimeout) throw new OperationCanceledException();
                return failSend ? Task.FromException(new HttpRequestException()) : Task.CompletedTask;
            },
            (_, _, _) =>
            {
                withdrawals++;
                return failWithdraw ? Task.FromException(new HttpRequestException()) : Task.CompletedTask;
            });
        await publisher.TickAsync();
        Check(starts == 0 && sends == 0, "no implicit consent");
        current = state;
        await publisher.TickAsync(); await publisher.TickAsync();
        Check(starts == 1 && sequences.SequenceEqual(new long[] { 1, 2 }), "one session with increasing sequence");
        current = state with { Visibility = PlayerPresenceVisibilityMode.Invisible };
        failWithdraw = true;
        await Fails(() => publisher.TickAsync());
        await Fails(() => publisher.TickAsync());
        Check(sends == 2, "withdrawal failure never publishes old content");
        failWithdraw = false;
        await publisher.TickAsync();
        current = state;
        await publisher.TickAsync();
        Check(starts == 2 && sequences[^1] == 1, "return online starts fresh session");
        failSend = true;
        await Fails(() => publisher.TickAsync());
        failSend = false;
        await publisher.TickAsync();
        Check(starts == 2 && sequences[^1] == 3, "transport recovery builds fresh source with a newer sequence, not a replay or offline transition");
        var beforeQueueTimeout = withdrawals;
        queueTimeout = true;
        try { await publisher.TickAsync(); throw new Exception("Expected queue cancellation."); }
        catch (OperationCanceledException) { }
        queueTimeout = false;
        await publisher.TickAsync();
        Check(starts == 2 && withdrawals == beforeQueueTimeout && sequences[^1] == 5,
            "internal queue cancellation must retain the existing friend session without an Offline transition");
        using var cancelled = new CancellationTokenSource();
        cancelled.Cancel();
        Check(!FriendSharingPublication.IsTransient(new OperationCanceledException(), cancelled.Token),
            "explicit cancellation never authorizes automatic publication resumption");
        current = state with { Revision = 2, Fields = FriendSharedFields.Presence };
        await publisher.TickAsync();
        Check(starts == 3, "policy change creates fresh session");
        current = state with { Input = input with { Generation = 2 } };
        await publisher.TickAsync();
        Check(starts == 4 && owners[^1] == 2, "new account generation never inherits session");
        current = null;
        await publisher.TickAsync();
        var sent = sends;
        await publisher.TickAsync();
        Check(sends == sent, "signed out does not publish");

        var entered = new TaskCompletionSource();
        var release = new TaskCompletionSource<string>();
        current = state;
        var raced = new FriendSharingPublication(() => current,
            (_, _) => { entered.SetResult(); return release.Task; },
            (_, _, _, _, _) => throw new InvalidOperationException("stale start must not publish"),
            (_, _, _) => { withdrawals++; return Task.CompletedTask; });
        var pending = raced.TickAsync();
        await entered.Task;
        current = state with { Consent = false };
        var beforeWithdrawal = withdrawals;
        release.SetResult(Guid.NewGuid().ToString("N"));
        await pending;
        Check(withdrawals == beforeWithdrawal + 1, "consent changed during start triggers withdrawal");

        current = state;
        var sending = new TaskCompletionSource();
        var sentReply = new TaskCompletionSource();
        var inFlight = new FriendSharingPublication(() => current,
            (_, _) => Task.FromResult(Guid.NewGuid().ToString("N")),
            (_, _, _, _, _) => { sending.SetResult(); return sentReply.Task; },
            (_, _, _) => { withdrawals++; return Task.CompletedTask; });
        pending = inFlight.TickAsync();
        await sending.Task;
        current = state with { Consent = false };
        beforeWithdrawal = withdrawals;
        var stop = inFlight.StopAsync();
        Check(!stop.IsCompleted && withdrawals == beforeWithdrawal, "stop waits for in-flight publication");
        sentReply.SetResult();
        await Task.WhenAll(pending, stop);
        Check(withdrawals == beforeWithdrawal + 1, "one withdrawal follows in-flight publication");
    }

    private static async Task Fails(Func<Task> action)
    {
        try { await action(); }
        catch (HttpRequestException) { return; }
        throw new InvalidOperationException("Expected transport failure.");
    }
    private static void Check(bool condition, string message)
    { if (!condition) throw new InvalidOperationException("Friend sharing publication: " + message); }
}
