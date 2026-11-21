using System.Reflection;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;

internal static partial class LegacyPasswordLoginTests
{
    private static async Task VerifyParticipantPollingReduction()
    {
        using var transport = new EnrollmentTransport();
        var uri = new Uri("http://127.0.0.1:9/");
        var oauth = new OAuthPkceClient(new ScmHttpClient(transport), new ScmVisitorVault(),
            new ScmOAuthOptions("synthetic", uri, uri, uri, "synthetic", "synthetic", "openid profile.read", "/callback"));
        var clock = new ParticipantTestClock();
        using var host = new ScmAccountBridgeHost(oauth, new ScmProfileCacheStore(), "integration", () => null,
            initialSession: new ScmOAuthSession("synthetic", "owner", "Pilot", "read-token",
                DateTimeOffset.UtcNow.AddHours(1), ["profile.read"])) { ParticipantClock = clock };
        for (var minute = 0; minute < 60; minute++) {
            if (minute > 0) clock.Now = clock.Now.AddMinutes(1);
            await host.GetCurrentAsync(default);
        }
        Check(transport.IdentityReads == 1 && transport.Registrations == 1 && transport.Refreshes == 59,
            "one session hour reads its verified business key once but retains every minute's authenticated refresh");

        // Exercise the real session publication boundary, including loop/cache
        // retirement, without a browser, real account or network transport.
        const BindingFlags flags = BindingFlags.Instance | BindingFlags.NonPublic;
        var session = (ScmOAuthSession)typeof(ScmAccountBridgeHost).GetField("_session", flags)!.GetValue(host)!;
        typeof(ScmAccountBridgeHost).GetMethod("PublishSession", flags)!.Invoke(host,
            [session, false, null, false, null, null, null, null]);
        Check(typeof(ScmAccountBridgeHost).GetField("_participantIdentity", flags)!.GetValue(host) is null,
            "session publication immediately retires the reusable business key");
        await host.GetCurrentAsync(default);
        Check(transport.IdentityReads == 2 && transport.Registrations == 2,
            "a new generation immediately verifies its key and registers itself");

        transport.Mode = "wrong-owner";
        clock.Now = clock.Now.AddMinutes(1);
        await host.GetCurrentAsync(default);
        Check(transport.IdentityReads == 2 && transport.Refreshes == 60 &&
            typeof(ScmAccountBridgeHost).GetField("_participantIdentity", flags)!.GetValue(host) is null,
            "every reused-key refresh still validates its receipt and clears reuse on mismatch");
        transport.Mode = "ok";
        clock.Now = clock.Now.AddMinutes(1);
        await host.GetCurrentAsync(default);
        Check(transport.IdentityReads == 3 && transport.Refreshes == 61 && transport.Registrations == 2,
            "a rejected receipt forces a new identity read without replaying registration");

        // An ended account cannot lend its key even before another account's
        // first request. PublishSession is also the logout/owner-change seam.
        typeof(ScmAccountBridgeHost).GetMethod("PublishSession", flags)!.Invoke(host,
            [null, false, null, false, null, null, null, null]);
        Check(typeof(ScmAccountBridgeHost).GetField("_participantIdentity", flags)!.GetValue(host) is null,
            "logout immediately drops the session's business key");
        Check(transport.IdentityReads == 3 && transport.Registrations == 2,
            "session retirement itself cannot issue a discovery or registration request");
    }
}
