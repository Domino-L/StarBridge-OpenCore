using System.Net;
using System.Net.Http.Json;
using System.Reflection;
using System.Text.Json;
using StarBridge.Core.Profiles;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.Friends;
using StarBridge.HostRuntime.Marketplace;
using StarBridge.NativeBridge;

// CX-T38: all transports are in-memory and fail on unexpected routes.
internal static class MarketTraderProfileTests
{
    private const long Peer = 987654321123, Viewer = 876543219123;
    private const string Subject = "scm-v1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    private static int _passed;
    private static readonly BindingFlags Private = BindingFlags.Instance | BindingFlags.NonPublic;

    internal static async Task<int> Run()
    {
        var previous = HostDataRoot.CurrentRoot;
        var root = Path.Combine(Directory.GetCurrentDirectory(), ".codex-build", "cx-t38-data", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        HostDataRoot.UsePreparedRoot(root);
        _passed = 0;
        try
        {
            await Case("concurrent viewer reads share one request", ConcurrentViewer);
            await Case("viewer waiter cancellation preserves the shared request", CancelViewerWaiter);
            await Case("failed viewer reads cool down for sixty seconds", ViewerCooldown);
            await Case("viewer reads retry at the cooldown boundary", ViewerRetry);
            await Case("viewer cache and cooldown are account and generation scoped", ViewerScope);
            await Case("late viewer reads cannot replace a new scope", LateViewerScope);
            await Case("quote paths, privacy and self exclusion", Projection);
            await Case("visitor route, read-only document and decoration", Visitor);
            await Case("POST body survives HTTP authentication replay", VisitorReplay);
            await Case("renewal, expiry and replacement", Lifetime);
            await Case("bounded in-memory registry", Capacity);
            await Case("forged, cross-scope, cross-account and generation refs", Isolation);
            await Case("market cannot authorize social, avatar or friend targets", ProfileOnly);
            await Case("restricted public header", Restricted);
            await Case("masked handle opens only through an own trade", MaskedHandleOpensOnlyThroughOwnTrade);
            foreach (var (status, code, retryable) in new[] {
                (HttpStatusCode.NotFound, "profile.visitor_not_visible", false),
                (HttpStatusCode.Forbidden, "profile.visitor_not_visible", false),
                (HttpStatusCode.TooManyRequests, "profile.visitor_rate_limited", true),
                (HttpStatusCode.ServiceUnavailable, AccountBridgeStableErrors.PersonalProfileReadUnavailable, true) })
                await Case("visitor HTTP " + (int)status, () => Failure(status, code, retryable));
            foreach (var header in new[] { "missing", "numeric", "uppercase", "short", "duplicate", "combined" })
                await Case("protocol header " + header, () => BadHeader(header));
            await Case("late expiry", LateExpiry);
            await Case("late account and generation changes", LateOwnerChange);
            await Case("late viewer read preserves a newer session", LateViewerSession);
            await Case("viewer lookup failure preserves anonymous quotes", ViewerFailure);
            await Case("no disk identity/ref cache or diagnostic leakage", () => Privacy(root));
            Console.WriteLine($"RESULT market-trader-profile: {_passed} passed, 0 failed");
            return 0;
        }
        catch (Exception error)
        {
            // Do not print request, response, exception message or identities.
            Console.WriteLine($"RESULT market-trader-profile: {_passed} passed, 1 failed ({error.GetType().Name})");
            return 1;
        }
        finally { HostDataRoot.UsePreparedRoot(previous); }
    }

    private static async Task Case(string label, Func<Task> run)
    {
        try { await run(); }
        catch { Console.WriteLine("FAIL " + label); throw; }
        _passed++;
        Console.WriteLine("PASS " + label);
    }
    private static void Check(bool value) { if (!value) throw new InvalidOperationException("Market trader assertion failed."); }
    private static object Target(string reference, string? context = null) =>
        new { schemaVersion = 1, source = "market", reference, contextRef = context };
    private static JsonElement Quote(object? creator = null, string order = "ORDER", long owner = Viewer) =>
        BridgePayload.From(new { orderNumber = order, creatorId = creator, orderOwnerId = owner,
            nickname = "FixturePilot", displayType = 2, unitPrice = 12, remainingQuantity = 3 });
    private static FieldInfo Field(object target, string name) => target.GetType().GetField(name, Private)!;
    private static void Error(BridgeEnvelope response, string code, bool? retryable = null) =>
        Check(response.Status == "error" && response.Error?.Code == code &&
            (retryable is null || response.Error.Retryable == retryable));

    private static async Task Projection()
    {
        using var f = new Fixture();
        foreach (var operation in new[] { "offers", "latest", "marketOrders" })
        {
            var page = await f.Quotes(operation);
            Check(page.Status == "ok");
            var rows = page.Payload.GetProperty("data").GetProperty("rows");
            var reference = rows[0].GetProperty("traderRef").GetString()!;
            Check(Guid.TryParseExact(reference, "N", out _) && rows[0].GetProperty("seller").GetString() == "F*****t");
            for (var i = 1; i < rows.GetArrayLength(); i++) Check(!rows[i].TryGetProperty("traderRef", out _));
            var wire = page.Payload.GetRawText();
            Check(!wire.Contains(Peer.ToString()) && !wire.Contains(Viewer.ToString()) && !wire.Contains("scm-v1") &&
                !wire.Contains("creatorId") && !wire.Contains("orderOwnerId"));
            // orderOwnerId deliberately points to the viewer; creatorId must win.
            Check((await f.Profile(reference)).Status == "ok" && f.Http.ProfilePath == FakeHttp.ProfileRoute);
        }
        Check(f.Http.ViewerReads == 1);
        // A property missing altogether is different from creatorId:null.
        var project = (await f.Projector())!;
        Check(project(BridgePayload.From(new { orderNumber = "MISSING", orderOwnerId = Peer })) is null);
    }

    private static async Task Visitor()
    {
        using var f = new Fixture();
        var reference = await f.Reference();
        var result = await f.Profile(reference);
        Check(result.Status == "ok" && !result.Payload.GetProperty("editable").GetBoolean());
        var profile = result.Payload.GetProperty("profile");
        Check(profile.GetProperty("identity").GetProperty("callSign").GetString() == "Visitor" &&
            profile.GetProperty("fleetAffiliation").GetProperty("logoUrl").GetString() == FakeHttp.Logo);
        Check(f.Http.ProfilePath == FakeHttp.ProfileRoute &&
            f.Http.Accept == PersonalProfilePublicHeader.AcceptValues && f.Http.Writes == 0);
        Check(!result.Payload.GetRawText().Contains("scm-v1") && !profile.TryGetProperty("publicId", out _) &&
            !profile.TryGetProperty("businessSubjectId", out _) && !result.Payload.GetRawText().Contains(Peer.ToString()));
    }

    private static object TradeRow(long owner, long trader, string ownerName, string traderName) => new
    { transactionNumber = "T1", orderOwnerId = owner, tradingerId = trader, orderOwnerName = ownerName, tradingerName = traderName };

    private static async Task<JsonElement> MaskedRead(Fixture f, string reference)
    {
        var result = await f.Profile(reference);
        Check(result.Status == "ok");
        return result.Payload.GetProperty("publicHeader");
    }

    private static async Task MaskedHandleOpensOnlyThroughOwnTrade()
    {
        using (var f = new Fixture())
        {
            // Never traded: stays masked, with the facts and the resolved offset, and never the zone id or member id.
            f.Http.Masked = true;
            f.Http.TradeRows = _ => [TradeRow(Viewer, 5, "Me", "Someone")];
            var reference = await f.Reference();
            var header = await MaskedRead(f, reference);
            Check(header.GetProperty("callSign").GetString() == "F*****t" && header.GetProperty("nameMasked").GetBoolean() &&
                header.GetProperty("defaulted").GetBoolean() && f.Http.TradeReads == 1);
            var facts = header.GetProperty("facts");
            Check(facts.GetProperty("completedTrades").GetInt32() == 31 && facts.GetProperty("utcOffsetMinutes").GetInt32() == 480 &&
                !facts.TryGetProperty("timezoneId", out _));
            Check(!header.GetRawText().Contains(Peer.ToString()));
            // A confirmed miss is not rescanned on every open.
            await MaskedRead(f, reference);
            Check(f.Http.TradeReads == 1 && f.Http.Writes == 0);
            // A new order shows within a minute, for one newest page and not another scan.
            f.Http.TradeRows = page => { Check(page == 1); return [TradeRow(Peer, Viewer, "Full_Handle", "Me")]; };
            f.Now = f.Now.AddSeconds(61);
            header = await MaskedRead(f, reference);
            Check(header.GetProperty("callSign").GetString() == "Full_Handle" && f.Http.TradeReads == 2);
            // Known now: no more reads.
            f.Now = f.Now.AddSeconds(61);
            await MaskedRead(f, reference);
            Check(f.Http.TradeReads == 2);
        }
        foreach (var (owner, trader, ownerName, traderName) in new[] { (Peer, Viewer, "Full_Handle", "Me"), (Viewer, Peer, "Me", "Full_Handle") })
        {
            using var f = new Fixture();
            f.Http.Masked = true;
            f.Http.TradeRows = page => page == 2 ? [TradeRow(owner, trader, ownerName, traderName)] : Enumerable.Repeat(TradeRow(Viewer, 5, "Me", "Other"), 100).ToArray();
            var header = await MaskedRead(f, await f.Reference());
            Check(header.GetProperty("callSign").GetString() == "Full_Handle" && !header.TryGetProperty("nameMasked", out _) && f.Http.TradeReads == 2);
        }
        {
            // An email nickname stays masked even with a trade.
            using var f = new Fixture();
            f.Http.Masked = true;
            f.Http.TradeRows = _ => [TradeRow(Peer, Viewer, "pilot@example.invalid", "Me")];
            var header = await MaskedRead(f, await f.Reference());
            Check(header.GetProperty("callSign").GetString() == "F*****t" && header.GetProperty("nameMasked").GetBoolean());
        }
        foreach (var status in new[] { HttpStatusCode.ServiceUnavailable, HttpStatusCode.Forbidden, HttpStatusCode.TooManyRequests })
        {
            // A failed trade read still shows the page, masked.
            using var f = new Fixture();
            f.Http.Masked = true;
            f.Http.TradeStatus = status;
            var header = await MaskedRead(f, await f.Reference());
            Check(header.GetProperty("callSign").GetString() == "F*****t" && header.GetProperty("facts").GetProperty("reputation").GetInt32() == 128);
        }
        {
            // A token refreshed halfway through a scan continues from that page instead of starting over.
            using var f = new Fixture();
            f.Http.Masked = true;
            f.Http.TradeRows = page => page == 3 ? [TradeRow(Peer, Viewer, "Full_Handle", "Me")]
                : Enumerable.Repeat(TradeRow(Viewer, 5, "Me", "Other"), 100).ToArray();
            f.Http.TradeCodeOnPage = 2;
            f.Http.OnTradeCode = () => {
                var original = (ScmOAuthSession)Field(f.Host, "_session").GetValue(f.Host)!;
                Field(f.OAuth, "_currentSession").SetValue(f.OAuth, original with { CredentialVersion = Guid.NewGuid(), ExpiresAt = original.ExpiresAt.AddHours(1) });
            };
            var header = await MaskedRead(f, await f.Reference());
            // Page 1, page 2 refused, page 2 again, page 3.
            Check(header.GetProperty("callSign").GetString() == "Full_Handle" && f.Http.TradeReads == 4);
        }
        {
            // An expired sign-in is not swallowed like other failures: it goes through the sign-in recovery.
            using var f = new Fixture();
            f.Http.Masked = true;
            f.Http.TradeCode = 401;
            f.Http.TradeRows = _ => [TradeRow(Peer, Viewer, "Full_Handle", "Me")];
            f.Http.OnTradeCode = () => {
                var original = (ScmOAuthSession)Field(f.Host, "_session").GetValue(f.Host)!;
                Field(f.OAuth, "_currentSession").SetValue(f.OAuth, original with { CredentialVersion = Guid.NewGuid(), ExpiresAt = original.ExpiresAt.AddHours(1) });
            };
            var header = await MaskedRead(f, await f.Reference());
            Check(f.Http.TradeReads == 2 && header.GetProperty("callSign").GetString() == "Full_Handle");
        }
        {
            // A trade read that times out by itself still shows the page, masked.
            using var f = new Fixture();
            f.Http.Masked = true;
            f.Http.TradeTimesOut = true;
            var header = await MaskedRead(f, await f.Reference());
            Check(header.GetProperty("callSign").GetString() == "F*****t");
        }
        {
            // The scan is bounded, runs once per sign-in, and serves everyone it found.
            using var f = new Fixture();
            f.Http.Masked = true;
            f.Http.TradeRows = _ => Enumerable.Repeat(TradeRow(Viewer, 5, "Me", "Other"), 100).ToArray();
            var reference = await f.Reference();
            await MaskedRead(f, reference);
            Check(f.Http.TradeReads == 20);
            await MaskedRead(f, reference);
            Check(f.Http.TradeReads == 20);
            f.Now = f.Now.AddSeconds(61);
            await MaskedRead(f, reference);
            Check(f.Http.TradeReads == 21);
        }
        {
            // Opening many people at once still reads once.
            using var f = new Fixture();
            f.Http.Masked = true;
            f.Http.TradeRows = _ => [TradeRow(Peer, Viewer, "Full_Handle", "Me")];
            var reference = await f.Reference();
            var opened = await Task.WhenAll(Enumerable.Range(0, 6).Select(_ => MaskedRead(f, reference)));
            Check(f.Http.TradeReads == 1 && opened.All(h => h.GetProperty("callSign").GetString() == "Full_Handle"));
        }
        {
            // A profile read holds the account lane, so a slow scan cannot hold the page: it opens masked,
            // the scan finishes beside it, and the next open has the name without another read.
            using var f = new Fixture();
            f.Http.Masked = true;
            f.Http.TradeHolds = true;
            f.Http.TradeRows = _ => [TradeRow(Peer, Viewer, "Full_Handle", "Me")];
            var reference = await f.Reference();
            var started = System.Diagnostics.Stopwatch.StartNew();
            var first = await MaskedRead(f, reference);
            Check(started.Elapsed < TimeSpan.FromSeconds(5) && first.GetProperty("callSign").GetString() == "F*****t" && f.Http.TradeReads == 1);
            f.Http.TradeRelease.TrySetResult();
            var opened = "";
            for (var i = 0; i < 50 && opened != "Full_Handle"; i++)
            {
                await Task.Delay(50);
                opened = (await MaskedRead(f, reference)).GetProperty("callSign").GetString()!;
            }
            Check(opened == "Full_Handle" && f.Http.TradeReads == 1);
        }
        {
            // Cancelling the page cannot be used to scan again straight away.
            using var f = new Fixture();
            f.Http.Masked = true;
            f.Http.TradeHolds = true;
            f.Http.TradeRows = _ => [TradeRow(Peer, Viewer, "Full_Handle", "Me")];
            var reference = await f.Reference();
            using var cancel = new CancellationTokenSource();
            var read = f.Host.ReadUserProfileAsync(f.Host.CurrentContext!, BridgePayload.From(Target(reference)), cancel.Token);
            await f.Http.TradeStarted.Task.WaitAsync(TimeSpan.FromSeconds(5));
            cancel.Cancel();
            try { await read; } catch (OperationCanceledException) { }
            var after = await MaskedRead(f, reference);
            Check(f.Http.TradeReads == 1 && after.GetProperty("callSign").GetString() == "F*****t");
            f.Http.TradeRelease.TrySetResult();
        }
        {
            // A failed read does not retry on every open, and the scan starts over when it does.
            using var f = new Fixture();
            f.Http.Masked = true;
            f.Http.TradeStatus = HttpStatusCode.ServiceUnavailable;
            var reference = await f.Reference();
            await MaskedRead(f, reference);
            var failed = f.Http.TradeReads;
            await MaskedRead(f, reference);
            Check(f.Http.TradeReads == failed);
            // Repeated failures wait longer: the second retry is not due at two minutes.
            f.Now = f.Now.AddSeconds(121);
            await MaskedRead(f, reference);
            failed = f.Http.TradeReads;
            f.Now = f.Now.AddSeconds(121);
            await MaskedRead(f, reference);
            Check(f.Http.TradeReads == failed);
            f.Http.TradeStatus = HttpStatusCode.OK;
            f.Http.TradeRows = _ => [TradeRow(Peer, Viewer, "Full_Handle", "Me")];
            f.Now = f.Now.AddSeconds(121);
            var header = await MaskedRead(f, reference);
            Check(header.GetProperty("callSign").GetString() == "Full_Handle");
        }
    }

    private static async Task VisitorReplay()
    {
        using var f = new Fixture();
        var reference = await f.Reference();
        f.Http.BeforeUnauthorized = () => {
            var original = (ScmOAuthSession)Field(f.Host, "_session").GetValue(f.Host)!;
            var refreshed = original with { CredentialVersion = Guid.NewGuid(), ExpiresAt = original.ExpiresAt.AddHours(1) };
            Field(f.OAuth, "_currentSession").SetValue(f.OAuth, refreshed);
        };
        Check((await f.Profile(reference)).Status == "ok");
        Check(f.Http.ProfileReads == 2 && f.Http.ProfileRequests.Count == 2 &&
            !ReferenceEquals(f.Http.ProfileRequests[0], f.Http.ProfileRequests[1]) &&
            !ReferenceEquals(f.Http.ProfileRequests[0].Content, f.Http.ProfileRequests[1].Content));
    }

    private static async Task ConcurrentViewer()
    {
        foreach (var failure in new[] { "", "forbidden" })
        {
            using var f = new Fixture();
            f.Http.DelayViewer = true;
            f.Http.ViewerFailure = failure;
            var pending = Enumerable.Range(0, 12).Select(_ => f.Quotes("latest")).ToArray();
            await f.Http.Started.Task.WaitAsync(TimeSpan.FromSeconds(5));
            var reads = f.Http.ViewerReads;
            f.Http.Release.TrySetResult();
            var pages = await Task.WhenAll(pending).WaitAsync(TimeSpan.FromSeconds(5));
            Check(reads == 1 && f.Http.ViewerReads == 1 && pages.All(page => page.Status == "ok" &&
                page.Payload.GetRawText().Contains("traderRef") == (failure == "")));
        }
    }

    private static async Task ViewerCooldown()
    {
        using var f = new Fixture();
        f.Http.DelayViewer = true;
        f.Http.ViewerFailure = "forbidden";
        var pending = f.Quotes("latest");
        await f.Http.Started.Task.WaitAsync(TimeSpan.FromSeconds(5));
        f.Now = f.Now.AddMinutes(2); // cooldown starts at failure, not request start
        f.Http.Release.TrySetResult();
        Check((await pending).Status == "ok");
        f.Http.ViewerFailure = "";
        f.Now = f.Now.AddSeconds(59);
        foreach (var operation in new[] { "latest", "offers", "marketOrders" })
        {
            var page = await f.Quotes(operation);
            Check(page.Status == "ok" && !page.Payload.GetRawText().Contains("traderRef"));
        }
        Check(f.Http.ViewerReads == 1);
    }

    private static async Task CancelViewerWaiter()
    {
        using var f = new Fixture();
        using var cancelled = new CancellationTokenSource();
        f.Http.DelayViewer = true;
        var first = f.Projector(cancelled.Token);
        await f.Http.Started.Task.WaitAsync(TimeSpan.FromSeconds(5));
        var second = f.Projector();
        cancelled.Cancel();
        var wasCancelled = false;
        try { await first; }
        catch (OperationCanceledException) { wasCancelled = true; }
        f.Http.Release.TrySetResult();
        Check(wasCancelled && await second.WaitAsync(TimeSpan.FromSeconds(5)) is not null &&
            await f.Projector() is not null && f.Http.ViewerReads == 1);
    }

    private static async Task ViewerRetry()
    {
        using var f = new Fixture();
        f.Http.ViewerFailure = "missing";
        Check((await f.Quotes("latest")).Status == "ok");
        f.Now = f.Now.AddSeconds(60);
        f.Http.ViewerFailure = "";
        var page = await f.Quotes("latest");
        Check(page.Status == "ok" && page.Payload.GetRawText().Contains("traderRef") && f.Http.ViewerReads == 2);
        Check((await f.Quotes("offers")).Status == "ok" && f.Http.ViewerReads == 2);
    }

    private static async Task ViewerScope()
    {
        foreach (var account in new[] { false, true })
        foreach (var failed in new[] { false, true })
        {
            using var f = new Fixture();
            f.Http.ViewerFailure = failed ? "zero" : "";
            await f.Quotes("latest");
            f.ChangeOwner(account);
            f.Http.ViewerFailure = "";
            f.Http.ViewerId = Peer; // the new viewer must now exclude this quote
            var page = await f.Quotes("latest");
            var rows = page.Payload.GetProperty("data").GetProperty("rows");
            Check(page.Status == "ok" && f.Http.ViewerReads == 2 &&
                !rows[0].TryGetProperty("traderRef", out _) && rows[1].TryGetProperty("traderRef", out _));
        }
    }

    private static async Task LateViewerScope()
    {
        foreach (var account in new[] { false, true })
        {
            using var f = new Fixture();
            f.Http.DelayViewer = true;
            var pending = f.Projector();
            await f.Http.Started.Task.WaitAsync(TimeSpan.FromSeconds(5));
            f.ChangeOwner(account);
            f.Http.DelayViewer = false;
            f.Http.ViewerId = Peer;
            var current = (await f.Projector())!;
            f.Http.Release.TrySetResult();
            Check(await pending is null && (await f.Projector()) is not null && f.Http.ViewerReads == 2 &&
                current(Quote(Peer)) is null && current(Quote(Viewer)) is not null);
        }
    }

    private static async Task Lifetime()
    {
        using var f = new Fixture();
        var reference = await f.Reference();
        f.Now = f.Now.AddMinutes(29);
        Check(await f.Reference() == reference);
        f.Now = f.Now.AddMinutes(2);
        Check((await f.Profile(reference)).Status == "ok");
        f.Now = f.Now.AddMinutes(28); // exactly thirty minutes after the last quote read
        Error(await f.Profile(reference), "users.targetChanged");
        var replacement = await f.Reference();
        Check(replacement != reference && (await f.Profile(replacement)).Status == "ok");
        Error(await f.Profile(reference), "users.targetChanged");
    }

    private static async Task Capacity()
    {
        using var f = new Fixture();
        var project = (await f.Projector())!;
        var first = project(Quote(Peer, "FIRST"))!;
        for (var i = 0; i < 4096; i++)
        {
            f.Now = f.Now.AddMilliseconds(1);
            Check(project(Quote(Peer, "ROW" + i)) is not null);
        }
        foreach (var field in new[] { "_marketTraderTargets", "_marketTraderReferences" })
            Check(((System.Collections.IDictionary)Field(f.Host, field).GetValue(f.Host)!).Count == 4096);
        Error(await f.Profile(first), "users.targetChanged");
    }

    private static async Task Isolation()
    {
        using var f = new Fixture();
        var reference = await f.Reference();
        Error(await f.Profile(Guid.NewGuid().ToString("N")), "users.targetChanged");
        Error(await f.Profile("not-a-reference"), "users.invalid_request");
        using var other = new Fixture();
        Error(await other.Profile(reference), "users.targetChanged");
        var oldSession = (ScmOAuthSession)Field(f.Host, "_session").GetValue(f.Host)!;
        Field(f.Host, "_session").SetValue(f.Host, oldSession with { Subject = "another-synthetic-owner" });
        Error(await f.Profile(reference), "users.targetChanged");
        Field(f.Host, "_session").SetValue(f.Host, oldSession);
        Field(f.Host, "_generation").SetValue(f.Host, f.Host.Generation + 1);
        Error(await f.Profile(reference), "users.targetChanged");
        Check(f.Http.ProfileReads == 0);
    }

    private static async Task ProfileOnly()
    {
        using var f = new Fixture();
        var reference = await f.Reference();
        Error(await f.Profile(reference, "nonempty"), "users.invalid_request");
        Error((await f.Dispatcher.DispatchAsync(BridgeEnvelope.Request("users.social", "social", f.Host.Generation,
            Target(reference), f.Host.CurrentContext))).Response, "users.social_unavailable");
        // Exercise the common avatar resolver itself with profileRead:false.
        var parsed = typeof(ScmAccountBridgeHost).GetMethod("ParseAvatarTarget", BindingFlags.Static | BindingFlags.NonPublic)!
            .Invoke(null, [BridgePayload.From(Target(reference))]);
        var session = typeof(ScmAccountBridgeHost).GetMethod("RequireRelaySession", Private)!
            .Invoke(f.Host, [f.Host.CurrentContext]);
        try
        {
            await (Task<string>)typeof(ScmAccountBridgeHost).GetMethod("ResolveAvatarAsync", Private)!
                .Invoke(f.Host, [parsed, session, "untrusted-scope", f.Host.CurrentContext, f.Host.Generation, CancellationToken.None, false])!;
            Check(false);
        }
        catch (AccountBridgeHostException error) { Check(error.Code == "users.invalid_request"); }
        using var friends = new FriendsReader(new Uri("https://fixture.invalid/"), new FakeHttp());
        foreach (var source in new[] { "market", "friend", "conversation" })
        {
            try { friends.ResolveAvatarTarget(source, reference, "synthetic", "scope"); Check(false); }
            catch (AccountBridgeHostException error) { Check(error.Code == "users.targetChanged"); }
        }
        Check(f.Http.ProfileReads == 0 && f.Http.Writes == 0);
    }

    private static async Task Restricted()
    {
        using var f = new Fixture();
        f.Http.Restricted = true;
        var response = await f.Profile(await f.Reference());
        Check(response.Status == "ok" && response.Payload.GetProperty("restricted").GetBoolean() &&
            !response.Payload.GetProperty("editable").GetBoolean() && !response.Payload.TryGetProperty("profile", out _));
        var header = response.Payload.GetProperty("publicHeader");
        Check(header.GetProperty("callSign").GetString() == "Visitor" &&
            header.GetProperty("tradeWindow").GetProperty("ownerOffsetMinutes").GetInt32() == 480);
        Check(!response.Payload.GetRawText().Contains("scm-v1"));
        f.Http.Header = "missing";
        Error(await f.Profile(await f.Reference()), AccountBridgeStableErrors.PersonalProfileReadUnavailable, true);
    }

    private static async Task Failure(HttpStatusCode status, string code, bool retryable)
    {
        using var f = new Fixture();
        f.Http.Status = status;
        Error(await f.Profile(await f.Reference()), code, retryable);
        Check(f.Http.ProfileReads == 1 && f.Http.Writes == 0);
    }
    private static async Task BadHeader(string header)
    {
        using var f = new Fixture();
        f.Http.Header = header;
        Error(await f.Profile(await f.Reference()), AccountBridgeStableErrors.PersonalProfileReadUnavailable, true);
        Check(f.Http.ProfileReads == 1);
    }

    private static async Task LateExpiry()
    {
        using var f = new Fixture();
        var reference = await f.Reference();
        f.Http.Delay = true;
        var pending = f.Profile(reference);
        await f.Http.Started.Task.WaitAsync(TimeSpan.FromSeconds(5));
        f.Now = f.Now.AddMinutes(30);
        f.Http.Release.SetResult();
        Error(await pending, "users.targetChanged");
    }
    private static async Task LateOwnerChange()
    {
        foreach (var account in new[] { false, true })
        {
            using var f = new Fixture();
            var reference = await f.Reference();
            f.Http.Delay = true;
            var pending = f.Profile(reference);
            await f.Http.Started.Task.WaitAsync(TimeSpan.FromSeconds(5));
            if (account)
            {
                var original = (ScmOAuthSession)Field(f.Host, "_session").GetValue(f.Host)!;
                Field(f.Host, "_session").SetValue(f.Host, original with { Subject = "another-synthetic-owner" });
            }
            else Field(f.Host, "_generation").SetValue(f.Host, f.Host.Generation + 1);
            f.Http.Release.SetResult();
            Check((await pending).Status != "ok");
        }
    }

    private static async Task ViewerFailure()
    {
        foreach (var failure in new[] { "forbidden", "missing", "zero", "no-scope" })
        {
            using var f = new Fixture(failure == "no-scope");
            f.Http.ViewerFailure = failure;
            var response = await f.Quotes("latest");
            Check(response.Status == "ok" && !response.Payload.GetRawText().Contains("traderRef"));
            Check(f.Http.Writes == 0 && f.Http.ProfileReads == 0);
            if (failure == "no-scope") Check(f.Http.ViewerReads == 0);
        }
    }

    private static async Task LateViewerSession()
    {
        using var f = new Fixture();
        f.Http.DelayViewer = true;
        var pending = f.Projector();
        await f.Http.Started.Task.WaitAsync(TimeSpan.FromSeconds(5));
        var original = (ScmOAuthSession)Field(f.Host, "_session").GetValue(f.Host)!;
        var newer = original with { ExpiresAt = original.ExpiresAt.AddHours(1) };
        Field(f.Host, "_session").SetValue(f.Host, newer);
        f.Http.Release.SetResult();
        Check(await pending is not null && ReferenceEquals(Field(f.Host, "_session").GetValue(f.Host), newer));
    }

    private static async Task Privacy(string root)
    {
        using var f = new Fixture();
        var reference = await f.Reference();
        f.Http.Status = HttpStatusCode.TooManyRequests;
        Error(await f.Profile(reference), "profile.visitor_rate_limited", true);
        try
        {
            await f.Host.ReadUserProfileAsync(f.Host.CurrentContext!, BridgePayload.From(Target(reference)), default);
            Check(false);
        }
        catch (AccountBridgeHostException error)
        {
            var text = error.ToString();
            Check(error.Code == "profile.visitor_rate_limited" && !text.Contains(Peer.ToString()) &&
                !text.Contains("scmUserId") && !text.Contains("private-server-marker"));
        }
        Check(VisitorReadDiagnostics.Format(1, VisitorReadDiagnostics.Route.MarketTrader, VisitorReadDiagnostics.Phase.Failed,
            429, "profile.visitor_rate_limited").EndsWith("code=visitor_rate_limited"));
        foreach (var path in Directory.GetFiles(root, "*", SearchOption.AllDirectories))
        {
            Check(Path.GetExtension(path) == ".log");
            var text = File.ReadAllText(path);
            Check(!text.Contains(Peer.ToString()) && !text.Contains(Viewer.ToString()) && !text.Contains(Subject) &&
                !text.Contains(reference) && !text.Contains("scm-v1") && !text.Contains("private-server-marker") &&
                !text.Contains("scmUserId"));
        }
    }

    private sealed class Fixture : IDisposable
    {
        internal DateTimeOffset Now = DateTimeOffset.Parse("2026-10-30T00:00:00Z");
        internal readonly FakeHttp Http = new();
        internal readonly ScmAccountBridgeHost Host;
        internal readonly OAuthPkceClient OAuth;
        internal readonly AccountBridgeDispatcher Dispatcher;
        private readonly AccountBridgeRuntime _runtime;
        internal Fixture(bool noTradeScope = false)
        {
            var uri = new Uri("https://fixture.invalid/");
            var oauth = OAuth = new OAuthPkceClient(new ScmHttpClient(Http), new NoVault(),
                new ScmOAuthOptions("fixture", uri, uri, uri, "fixture", "fixture", "profile.read trade.read", "/callback"));
            Host = new(oauth, new ScmProfileCacheStore(HostDataRoot.CurrentRoot), "fixture", () => null,
                initialSession: new("fixture", "opaque-viewer-subject", "Synthetic", "synthetic",
                    DateTimeOffset.UtcNow.AddHours(1), noTradeScope ? ["profile.read"] : ["profile.read", "trade.read"]),
                initialGeneration: 1, publicOrganizationLogos: new PublicOrganizationLogoReader((sid, _) =>
                    Task.FromResult(JsonDocument.Parse(JsonSerializer.Serialize(new { id = 7, sid, image = FakeHttp.Logo })))))
                { MarketTraderClock = () => Now };
            Dispatcher = new(Host);
            _runtime = new(Host);
            Field(_runtime, "_marketplace").SetValue(_runtime, new ScmMarketplaceReader(uri, new FakeHttp()));
        }
        internal async Task<BridgeEnvelope> Quotes(string operation) => (await _runtime.DispatchAsync(BridgeEnvelope.Request(
            "marketplace.read", Guid.NewGuid().ToString("N"), Host.Generation,
            new { schemaVersion = 1, operation, id = 17 }, Host.CurrentContext))).Response;
        internal Task<Func<JsonElement, string?>?> Projector(CancellationToken token = default) =>
            Host.PrepareMarketTraderReferencesAsync(Host.CurrentContext!, Host.Generation, token);
        internal void ChangeOwner(bool account)
        {
            if (account)
            {
                var session = (ScmOAuthSession)Field(Host, "_session").GetValue(Host)!;
                var replacement = session with { Subject = "another-synthetic-owner", CredentialVersion = Guid.NewGuid() };
                Field(Host, "_session").SetValue(Host, replacement);
                Field(OAuth, "_currentSession").SetValue(OAuth, replacement);
            }
            else Field(Host, "_generation").SetValue(Host, Host.Generation + 1);
        }
        internal async Task<string> Reference() => (await Projector())!(Quote(Peer))!;
        internal async Task<BridgeEnvelope> Profile(string reference, string? context = null) =>
            (await Dispatcher.DispatchAsync(BridgeEnvelope.Request("users.profile", Guid.NewGuid().ToString("N"), Host.Generation,
                Target(reference, context), Host.CurrentContext))).Response;
        public void Dispose() { _runtime.Dispose(); Dispatcher.Dispose(); Host.Dispose(); }
    }

    private sealed class NoVault : ITokenVault
    {
        public void SaveRefreshToken(string a, string b) => throw new InvalidOperationException("No vault IO");
        public string? LoadRefreshToken(string a) => throw new InvalidOperationException("No vault IO");
        public string? LoadActiveAccountKey() => throw new InvalidOperationException("No vault IO");
        public void DeleteRefreshToken(string a) => throw new InvalidOperationException("No vault IO");
    }

    private sealed class FakeHttp : HttpMessageHandler
    {
        internal const string Logo = "https://fixture.invalid/organization.png";
        internal const string ProfileRoute = "/app-api/starbridge/v1/personal-profile/visitor/scm-member";
        internal HttpStatusCode Status = HttpStatusCode.OK;
        internal string Header = "valid", ViewerFailure = "";
        internal bool Restricted, Masked, Delay, DelayViewer;
        internal int TradeReads;
        internal HttpStatusCode TradeStatus = HttpStatusCode.OK;
        internal bool TradeTimesOut, TradeHolds;
        internal readonly TaskCompletionSource TradeStarted = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal readonly TaskCompletionSource TradeRelease = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal int TradeCode, TradeCodeOnPage;
        internal Action? OnTradeCode;
        internal Func<int, object[]> TradeRows = _ => [];
        internal int ViewerReads, ProfileReads, Writes;
        internal long ViewerId = Viewer;
        internal Action? BeforeUnauthorized;
        internal readonly List<HttpRequestMessage> ProfileRequests = new();
        internal string? ProfilePath, Accept;
        internal readonly TaskCompletionSource Started = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal readonly TaskCompletionSource Release = new(TaskCreationOptions.RunContinuationsAsynchronously);
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            var path = request.RequestUri!.AbsolutePath;
            if (path == ProfileRoute)
            {
                Check(request.Method == HttpMethod.Post && request.RequestUri.Query == "" &&
                    request.Content?.Headers.ContentType?.MediaType == "application/json");
                using var body = JsonDocument.Parse(await request.Content!.ReadAsStringAsync(token));
                Check(body.RootElement.EnumerateObject().Count() == 2 &&
                    body.RootElement.GetProperty("schemaVersion").GetInt32() == 1 &&
                    body.RootElement.GetProperty("scmUserId").GetInt64() == Peer);
                ProfileRequests.Add(request);
            }
            else if (request.Method != HttpMethod.Get) { Writes++; throw new InvalidOperationException("Unexpected write"); }
            if (path == "/app-api/member/user/get")
            {
                Interlocked.Increment(ref ViewerReads);
                var viewer = ViewerId;
                if (DelayViewer) { Started.TrySetResult(); await Release.Task.WaitAsync(token); }
                return Json(ViewerFailure == "forbidden" ? HttpStatusCode.Forbidden : HttpStatusCode.OK,
                    new { code = 0, data = new { id = ViewerFailure == "missing" ? (long?)null : ViewerFailure == "zero" ? 0 : viewer } });
            }
            if (path == "/app-api/sc/order-transactions/page")
            {
                TradeReads++;
                if (TradeCodeOnPage > 0 && System.Web.HttpUtility.ParseQueryString(request.RequestUri.Query)["pageNo"] == TradeCodeOnPage.ToString())
                {
                    TradeCodeOnPage = 0;
                    OnTradeCode?.Invoke();
                    return Json(HttpStatusCode.OK, new { code = 401, data = (object?)null });
                }
                if (TradeHolds) { TradeStarted.TrySetResult(); await TradeRelease.Task.WaitAsync(token); }
                if (TradeCode != 0)
                {
                    var rejected = TradeCode;
                    TradeCode = 0;
                    OnTradeCode?.Invoke();
                    return Json(HttpStatusCode.OK, new { code = rejected, data = (object?)null });
                }
                if (TradeTimesOut) throw new TaskCanceledException("fixture timeout");
                var query = System.Web.HttpUtility.ParseQueryString(request.RequestUri.Query);
                Check(query["pageSize"] == "100");
                return TradeStatus != HttpStatusCode.OK ? Json(TradeStatus, new { error = "fixture" })
                    : Json(HttpStatusCode.OK, new { code = 0, data = new { total = 1, list = TradeRows(int.Parse(query["pageNo"]!)) } });
            }
            if (path == "/app-api/sc/orders/page")
                return Json(HttpStatusCode.OK, new { code = 0, data = new { total = 7, list = new[] {
                    Quote(Peer), Quote(Viewer, "SELF", Peer), Quote(null, "NULL"), Quote(0, "ZERO"), Quote(-1, "NEGATIVE"),
                    Quote("987654321123", "STRING"), Quote(1.5, "FRACTION") } } });
            if (path == "/app-api/member/timezone/list")
                return Json(HttpStatusCode.OK, new { code = 0, data = new[] { new { id = 77, value = "Asia/Shanghai", label = "Fixture", offset = "+08:00", offsetMinutes = 480 } } });
            if (path != ProfileRoute)
                throw new InvalidOperationException("Unexpected route");
            ProfileReads++; ProfilePath = path;
            Accept = request.Headers.GetValues(PersonalProfilePublicHeader.AcceptHeader).Single();
            Check(Accept == PersonalProfilePublicHeader.AcceptValues);
            if (BeforeUnauthorized is { } refresh)
            {
                BeforeUnauthorized = null;
                refresh();
                return Json(HttpStatusCode.Unauthorized, new { error = "synthetic-resource-expired" });
            }
            if (Delay) { Started.TrySetResult(); await Release.Task.WaitAsync(token); }
            var result = Status != HttpStatusCode.OK
                ? Json(Status, new { error = Status == HttpStatusCode.TooManyRequests ? "PERSONAL_PROFILE_LOOKUP_LIMITED" : "PERSONAL_PROFILE_NOT_AVAILABLE",
                    message = "private-server-marker " + Subject })
                : Masked ? Json(Status, new { schemaVersion = 2, restricted = true, visibility = "private",
                    publicHeader = new { callsign = "F*****t", avatarAssetId = (string?)null, callSignOrigin = (string?)null, avatarOrigin = (string?)null,
                        tradeWindow = (object?)null, defaulted = true, nameMasked = true,
                        facts = new { reputation = 128, completedTrades = 31, sellOrders = 5, buyOrders = 3, lastOnlineDay = "2026-10-29",
                            siteRegisteredDay = (string?)null, gameRegisteredDay = (string?)null, language = "zh", timezoneId = 77, banned = false, banCount = 0 } } })
                : Restricted ? Json(Status, new { schemaVersion = 1, restricted = true, visibility = "friendsOnly",
                    publicHeader = new { callsign = "Visitor", tradeWindow = new { days = new[] { 1, 1, 1, 1, 1, 0, 0 }, start = "19:00", end = "23:00", timezoneId = 77 } } })
                : Json(Status, new PersonalProfileDocumentContract(3, Subject, true, 1, DateTimeOffset.UtcNow,
                    new("Visitor", ""), PersonalProfileContentContract.Empty,
                    new("Fleet", "FIXTURE", null, "Member", "blue"), Visibility: "public"));
            if (Header != "missing")
                result.Headers.TryAddWithoutValidation("X-StarBridge-Profile-Subject", Header switch {
                    "numeric" => Peer.ToString(), "uppercase" => Subject.ToUpperInvariant(), "short" => "scm-v1:a",
                    "combined" => Subject + "," + Subject, _ => Subject });
            if (Header == "duplicate") result.Headers.TryAddWithoutValidation("X-StarBridge-Profile-Subject", Subject);
            return result;
        }
        private static HttpResponseMessage Json(HttpStatusCode status, object body) => new(status) { Content = JsonContent.Create(body) };
    }
}
