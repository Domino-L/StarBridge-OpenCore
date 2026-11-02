using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.Core.Profiles;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.NativeBridge;

internal static class VisitorDecorationRaceTests
{
    internal static async Task Run()
    {
        var failures = new List<string>();
        var passed = 0;
        foreach (var restricted in new[] { true, false })
        foreach (var source in new[] { "applicant", "historical", "officialFleet" })
        foreach (var change in new[] { "none", "revoke" })
            await RunCase(source, restricted, change);
        foreach (var restricted in new[] { true, false })
        foreach (var change in new[] { "cancel", "logout" })
            await RunCase("applicant", restricted, change);
        foreach (var change in new[] { "none", "revoke" })
            await RunCase("legacyApplicant", false, change);
        Console.WriteLine($"Visitor decoration races: {passed} passed, {failures.Count} failed");
        if (failures.Count != 0) throw new Exception(string.Join("; ", failures));

        async Task RunCase(string source, bool restricted, string change)
        {
            var boundary = source == "historical" && change == "revoke" ? "scope-retired" : change;
            var wait = source == "legacyApplicant" ? "profile" : restricted ? "timezone" : "logo";
            var name = $"{source}/{wait}/{boundary}";
            try
            {
                if (source == "legacyApplicant") await LegacyPasswordLoginTests.LegacyApplicantDecorationRace(change);
                else if (source == "officialFleet") await OfficialFleetIdentityTests.DecorationRace(restricted, change);
                else await LegacyPasswordLoginTests.VisitorDecorationRace(source, restricted, change);
                passed++;
                Console.WriteLine("PASS visitor decoration " + name);
            }
            catch (Exception error)
            {
                failures.Add(name + ": " + error.Message);
                Console.WriteLine("FAIL visitor decoration " + name + ": " + error.Message);
            }
        }
    }

    internal static void AssertResponse(BridgeEnvelope response, bool restricted, string change)
    {
        if (change == "none")
        {
            if (response.Error is not null) throw new Exception("Authorized read failed: " + response.Error.Code);
            if (restricted)
            {
                if (!response.Payload.GetProperty("restricted").GetBoolean() ||
                    response.Payload.GetProperty("publicHeader").GetProperty("tradeWindow")
                        .GetProperty("ownerOffsetMinutes").GetInt32() != 0)
                    throw new Exception("Authorized restricted header lost its timezone offset");
            }
            else if (response.Payload.GetProperty("profile").GetProperty("fleetAffiliation")
                .GetProperty("logoUrl").GetString() != "https://example.invalid/logo.png")
                throw new Exception("Authorized profile lost its logo");
            return;
        }
        if (response.Error is null || response.Payload.GetRawText().Contains("Visitor", StringComparison.Ordinal) ||
            response.Payload.TryGetProperty("publicHeader", out _) || response.Payload.TryGetProperty("profile", out _))
            throw new Exception("Authority changed during decoration but page/header escaped");
    }
}

// In-memory HTTP only: every visitor/timezone read is intercepted, and the inner
// handlers are existing synthetic directory fixtures. No sockets or credentials.
internal sealed class VisitorDecorationTransport(HttpMessageHandler inner, bool restricted) : DelegatingHandler(inner)
{
    internal readonly TaskCompletionSource Started = new(TaskCreationOptions.RunContinuationsAsynchronously);
    internal readonly TaskCompletionSource Release = new(TaskCreationOptions.RunContinuationsAsynchronously);
    internal int DecorationReads;
    internal PublicOrganizationLogoReader Logos => new(async (sid, token) => {
        await Pause(token);
        return JsonDocument.Parse(JsonSerializer.Serialize(new { id = 17, sid, image = "https://example.invalid/logo.png" }));
    });

    private async Task Pause(CancellationToken token)
    {
        Interlocked.Increment(ref DecorationReads);
        Started.TrySetResult();
        await Release.Task.WaitAsync(TimeSpan.FromSeconds(10), token);
    }

    protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
    {
        var path = Uri.UnescapeDataString(request.RequestUri!.AbsolutePath);
        if (path.StartsWith("/api/profiles/", StringComparison.Ordinal))
        {
            await Pause(token);
            return await base.SendAsync(request, token);
        }
        if (path.Contains("/personal-profile/visitor", StringComparison.Ordinal))
        {
            var historical = path.EndsWith("/visitor-legacy", StringComparison.Ordinal);
            var document = new PersonalProfileDocumentContract(3, "synthetic-public-profile", false, 1,
                DateTimeOffset.UtcNow, new("Visitor", ""), PersonalProfileContentContract.Empty,
                new("Fleet", "FIXTURE", null, "Member", "blue", Kind: "officialFleet"), Visibility: "friendsOnly");
            var header = new { callsign = "Visitor", tradeWindow = new {
                days = new[] { 1, 0, 0, 0, 0, 0, 0 }, start = "19:00", end = "21:00", timezoneId = 77 } };
            object body = restricted
                ? historical
                    ? new { schemaVersion = 1, legacyAccountId = "historical-member", restricted = true, visibility = "private", publicHeader = header }
                    : new { schemaVersion = 1, restricted = true, visibility = "private", publicHeader = header }
                : historical ? new { schemaVersion = 1, legacyAccountId = "historical-member", profile = document } : document;
            var response = new HttpResponseMessage(HttpStatusCode.OK) { Content = JsonContent.Create(body) };
            if (!historical) response.Headers.Add("X-StarBridge-Profile-Subject", path.Split('/').Last());
            return response;
        }
        if (path == "/app-api/member/timezone/list")
        {
            await Pause(token);
            return new(HttpStatusCode.OK) { Content = JsonContent.Create(new {
                code = 0, data = new[] { new { id = 77, name = "UTC", value = "Etc/UTC", offsetMinutes = 0 } } }) };
        }
        return await base.SendAsync(request, token);
    }
}

internal static partial class LegacyPasswordLoginTests
{
    internal static async Task LegacyApplicantDecorationRace(string change)
    {
        using var transport = new Transport();
        using var wire = new VisitorDecorationTransport(transport, false);
        using var legacy = new LegacyPasswordLoginClient(new("https://example.invalid/"), new Store(), wire);
        using var directory = new LegacyDecorationDirectory();
        using var communities = new StarBridge.HostRuntime.Communities.CommunityClient(new("https://example.invalid/"), directory);
        var uri = new Uri("https://example.invalid/");
        var oauth = new OAuthPkceClient(new ScmHttpClient(new ScmVisitorTransport()), new ScmBackgroundVault(),
            new ScmOAuthOptions("synthetic", uri, uri, uri, "synthetic", "synthetic", "profile.read", "/callback"));
        using var host = new ScmAccountBridgeHost(oauth, new ScmProfileCacheStore(), "integration", () => null,
            legacyPasswordLogin: legacy, communities: communities, publicOrganizationLogos: wire.Logos);
        await host.LoginLegacyAsync(BridgePayload.From(new { schemaVersion = 1, email = "old@example.invalid", password = "synthetic" }), 0, default);
        var owner = host.CurrentContext!;
        var mine = (StarBridge.HostRuntime.Communities.CommunityPage)await host.ReadCommunitiesAsync(owner,
            BridgePayload.From(new { schemaVersion = 1, view = "mine", query = "" }), default);
        var contextRef = mine.Items.Single().TargetRef;
        var admissions = BridgePayload.From(await host.ReadCommunityAdmissionsAsync(owner,
            BridgePayload.From(new { schemaVersion = 1, targetRef = contextRef, section = "applications", offset = 0 }), default));
        var reference = admissions.GetProperty("items")[0].GetProperty("entryRef").GetString()!;
        transport.Body = JsonSerializer.Serialize(new PersonalProfileDocumentContract(3, "visitor-peer", false, 1,
            DateTimeOffset.UtcNow, new("Visitor", ""), PersonalProfileContentContract.Empty,
            new("Fleet", "FIXTURE", null, "Member", "blue", Kind: "officialFleet"), Visibility: "friendsOnly"),
            new JsonSerializerOptions(JsonSerializerDefaults.Web));
        using var dispatcher = new AccountBridgeDispatcher(host);
        var pending = dispatcher.DispatchAsync(BridgeEnvelope.Request("users.profile", Guid.NewGuid().ToString("N"), host.Generation,
            new { schemaVersion = 1, source = "communityApplicant", reference, contextRef }, owner), default);
        try
        {
            await wire.Started.Task.WaitAsync(TimeSpan.FromSeconds(3));
            if (change == "revoke") directory.Revoked = true;
        }
        finally { wire.Release.TrySetResult(); }
        var response = (await pending).Response;
        if (change == "none")
        {
            if (response.Error is not null || response.Payload.GetProperty("profile").GetProperty("identity").GetProperty("callSign").GetString() != "Visitor")
                throw new Exception("Authorized legacy applicant profile failed");
        }
        else VisitorDecorationRaceTests.AssertResponse(response, false, change);
        if (directory.IdentityReads != 2 || wire.DecorationReads != 1)
            throw new Exception("Legacy applicant must be resolved twice around the profile wait");
    }

    private sealed class LegacyDecorationDirectory : HttpMessageHandler
    {
        internal bool Revoked;
        internal int IdentityReads;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            object body;
            switch (request.RequestUri!.AbsolutePath)
            {
                case "/api/fleets/membership": body = new { fleetCode = "A" }; break;
                case "/api/auth/session": body = new { accountId = "legacy-synthetic", userName = "owner", gameName = "Owner" }; break;
                case "/api/fleets":
                    body = new[] { new {
                        code = "A", name = "Fixture", ownerAccount = "legacy-synthetic", description = "", type = "", language = "any",
                        activeTime = "", totalMembers = 1, roleGroups = Array.Empty<object>(), memberPermissions = Array.Empty<object>(),
                        members = new[] { new { accountId = "legacy-synthetic", gameName = "Owner", callsign = "Owner", roleTitle = "Owner",
                            online = false, liveStatus = "Offline", lastUpdated = DateTimeOffset.UtcNow } },
                        applications = new[] { new { id = "fixture-application", applicantGameName = "Visitor", applicantCallsign = "Visitor",
                            applicantAccount = "visitor-peer", message = "", status = "Pending", createdAt = DateTimeOffset.UtcNow } },
                        invites = Array.Empty<object>()
                    } }; break;
                case "/api/fleets/admissions/applicant":
                    IdentityReads++;
                    if (Revoked) return Task.FromResult(new HttpResponseMessage(HttpStatusCode.NotFound));
                    body = new { schemaVersion = 1, code = "A", applicationId = "fixture-application", accountId = "visitor-peer" }; break;
                default: throw new Exception("Unexpected synthetic legacy directory route");
            }
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = JsonContent.Create(body) });
        }
    }

    internal static async Task VisitorDecorationRace(string source, bool restricted, string change)
    {
        using var wire = new VisitorDecorationTransport(new ScmVisitorTransport(), restricted);
        using var directory = new ScmVisitorCommunityTransport { Historical = source == "historical" };
        using var communities = new StarBridge.HostRuntime.Communities.CommunityClient(new("https://example.invalid/"), directory);
        var uri = new Uri("https://example.invalid/");
        var oauth = new OAuthPkceClient(new ScmHttpClient(wire), new ScmBackgroundVault(),
            new ScmOAuthOptions("synthetic", uri, uri, uri, "synthetic", "synthetic", "openid profile.read", "/callback"));
        using var host = new ScmAccountBridgeHost(oauth, new ScmProfileCacheStore(), "integration", () => null,
            initialSession: new ScmOAuthSession("synthetic", "viewer", "Pilot", "synthetic-read-token",
                DateTimeOffset.UtcNow.AddHours(1), ["profile.read"]), communities: communities, publicOrganizationLogos: wire.Logos);
        using var dispatcher = new AccountBridgeDispatcher(host);
        using var cancellation = new CancellationTokenSource();
        var owner = host.CurrentContext!;
        var page = (StarBridge.HostRuntime.Communities.CommunityPage)await host.ReadCommunitiesAsync(owner,
            BridgePayload.From(new { schemaVersion = 1, view = "mine", query = "" }), default);
        var contextRef = page.Items.Single().TargetRef;
        async Task<JsonElement> Workspace() => BridgePayload.From(await host.ReadCommunityWorkspaceAsync(owner,
            BridgePayload.From(new { schemaVersion = 1, targetRef = contextRef, query = "", offset = 0 }), default));
        string reference;
        if (source == "historical") reference = (await Workspace()).GetProperty("members")[0].GetProperty("memberRef").GetString()!;
        else
        {
            var admissions = BridgePayload.From(await host.ReadCommunityAdmissionsAsync(owner,
                BridgePayload.From(new { schemaVersion = 1, targetRef = contextRef, section = "applications", offset = 0 }), default));
            reference = admissions.GetProperty("items")[0].GetProperty("entryRef").GetString()!;
        }
        var pending = dispatcher.DispatchAsync(BridgeEnvelope.Request("users.profile", Guid.NewGuid().ToString("N"), host.Generation,
            new { schemaVersion = 1, source = source == "historical" ? "community" : "communityApplicant", reference, contextRef }, owner), cancellation.Token);
        try
        {
            await wire.Started.Task.WaitAsync(TimeSpan.FromSeconds(3));
            if (change == "revoke")
            {
                // Historical identities resolve from the scoped reference lease;
                // retire that owner to prove the second resolution runs after the wait.
                if (source == "historical") communities.Dispose();
                else directory.ApplicantStatus = HttpStatusCode.NotFound;
            }
            if (change == "cancel") cancellation.Cancel();
            if (change == "logout") await host.LogoutAsync(owner, default);
        }
        finally { wire.Release.TrySetResult(); }
        try { VisitorDecorationRaceTests.AssertResponse((await pending).Response, restricted, change); }
        catch (OperationCanceledException) when (change == "cancel" && cancellation.IsCancellationRequested) { }
        if (wire.DecorationReads != 1) throw new Exception("Expected exactly one decoration wait");
    }
}

internal static partial class OfficialFleetIdentityTests
{
    internal static async Task DecorationRace(bool restricted, string change)
    {
        using var directory = new Handler();
        using var wire = new VisitorDecorationTransport(directory, restricted);
        using var host = Host(wire, wire.Logos);
        using var dispatcher = new AccountBridgeDispatcher(host);
        var owner = host.CurrentContext!;
        var members = (await dispatcher.DispatchAsync(BridgeEnvelope.Request("officialFleet.getMembers",
            Guid.NewGuid().ToString("N"), host.Generation, Query, owner), default)).Response;
        var reference = members.Payload.GetProperty("members")[0].GetProperty("profileTargetRef").GetString()!;
        var pending = dispatcher.DispatchAsync(BridgeEnvelope.Request("users.profile", Guid.NewGuid().ToString("N"), host.Generation,
            new { schemaVersion = 1, source = "officialFleet", reference, contextRef = "officialFleet:7" }, owner), default);
        try
        {
            await wire.Started.Task.WaitAsync(TimeSpan.FromSeconds(3));
            if (change == "revoke") directory.State = "unlinked";
        }
        finally { wire.Release.TrySetResult(); }
        VisitorDecorationRaceTests.AssertResponse((await pending).Response, restricted, change);
        if (wire.DecorationReads != 1) throw new Exception("Expected exactly one decoration wait");
    }
}
