using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Nodes;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Communities;

internal static class CommunityProfileClientTests
{
    internal static async Task Verify()
    {
        await ReadAndSave();
        await LateReadCannotRestoreDraft();
        await ConcurrentSaveIsNotDuplicated();
        ValidateChanges();
    }

    private static async Task ReadAndSave()
    {
        var calls = 0;
        var writes = 0;
        var mode = "ok";
        var stale = false;
        JsonElement outgoing = default;
        using var handler = new Handler(async request =>
        {
            calls++;
            Check(request.Headers.Authorization?.Parameter == "test-bearer", "only supplied bearer is forwarded");
            if (request.RequestUri!.AbsolutePath == "/api/fleets/directory") return Reply(Directory());
            if (request.Method == HttpMethod.Get)
            {
                Check(request.RequestUri.PathAndQuery == "/api/fleets/profile?code=A", "editor reads only resolved organization");
                if (mode == "forbidden") return new(HttpStatusCode.Forbidden);
                var profile = Profile();
                if (mode == "wrong-code") profile["code"] = "B";
                if (mode == "no-permission") profile["access"] = JsonSerializer.SerializeToNode(new { canEditProfile = false, canEditLogo = false, canEditBanner = false });
                if (mode == "logo-only") profile["access"]!["canEditProfile"] = false;
                return Reply(profile);
            }
            writes++;
            Check(request.Method == HttpMethod.Post && request.RequestUri.PathAndQuery == "/api/fleets/info?projection=profile", "save reuses existing WPF endpoint");
            outgoing = await request.Content!.ReadFromJsonAsync<JsonElement>();
            if (mode == "drop") throw new HttpRequestException("fixture lost reply");
            if (mode == "stale") stale = true;
            if (mode == "conflict") return new(HttpStatusCode.Conflict);
            if (mode == "forbidden") return new(HttpStatusCode.Forbidden);
            if (mode == "unauthorized") return new(HttpStatusCode.Unauthorized);
            if (mode == "missing") return new(HttpStatusCode.NotFound);
            if (mode == "invalid") return new(HttpStatusCode.BadRequest);
            if (mode == "error") return new(HttpStatusCode.InternalServerError);
            if (mode == "oversize") return new(HttpStatusCode.OK) { Content = new StringContent(new string('x', 100000)) };
            if (mode == "bad-json") return new(HttpStatusCode.OK) { Content = new StringContent("{") };
            var result = Profile(mode == "same-revision" ? 7 : 8);
            if (outgoing.TryGetProperty("name", out var changedName)) result["name"] = changedName.GetString();
            if (mode == "wrong-code") result["code"] = "B";
            return Reply(result);
        });
        using var client = new CommunityClient(new Uri("https://community.invalid"), handler);
        var directory = await client.ReadAsync("test-bearer", new("mine", "", null, null), "A:1", default);
        var target = directory.Items.Single().TargetRef;
        var read = JsonSerializer.SerializeToElement(new { schemaVersion = 1, targetRef = target });
        var snapshot = JsonSerializer.SerializeToElement(await client.ReadProfileAsync("test-bearer", read, "A:1", default));
        var edit = snapshot.GetProperty("editRef").GetString()!;
        Check(edit.Length == 32 && snapshot.GetProperty("profileRevision").GetInt64() == 7, "Host issues opaque edit reference bound to authoritative revision");
        Check(!snapshot.GetRawText().Contains("do-not-forward") && !snapshot.TryGetProperty("members", out _), "editor whitelist excludes unrelated server payloads");
        var before = calls;
        await Error(() => client.ReadProfileAsync("test-bearer", read, "B:1", default), "communities.refreshRequired");
        await Error(() => client.ReadProfileAsync("test-bearer", EditRead(edit), "B:1", default), "communities.refreshRequired");
        Check(calls == before, "cross-account references cannot reach transport");
        var otherAccount = await client.SaveProfileAsync("test-bearer", Command(edit, new { description = "Wrong account" }), "B:1", () => { }, default);
        Check(otherAccount.Status == "rejected" && calls == before, "cross-account editing command never reaches transport");

        void Current() { if (stale) throw new AccountBridgeHostException("account.stale_generation"); }
        var command = Command(edit, new { description = "Changed", name = "星海 Équipe 探索" });
        var saved = await client.SaveProfileAsync("test-bearer", command, "A:1", Current, default);
        Check(saved.Status == "accepted" && saved.ProfileRevision == 8 && writes == 1, "successful save returns revision receipt");
        Check(outgoing.GetProperty("fleetCode").GetString() == "A" && outgoing.GetProperty("expectedProfileRevision").GetInt64() == 7 &&
            outgoing.GetProperty("updatedSections").EnumerateArray().Select(x => x.GetString()).Order().SequenceEqual(new[] { "description", "name" }), "Host chooses scope, revision and targeted sections");
        Check(outgoing.GetProperty("name").GetString() == "星海 Équipe 探索", "Unicode name reaches the existing endpoint unchanged");
        Check(outgoing.GetProperty("description").GetString() == "Changed" && outgoing.GetProperty("language").GetString() == "English" &&
            outgoing.GetProperty("externalContacts")[0].GetProperty("value").GetString() == "private-contact" &&
            outgoing.GetProperty("activityWindows")[0].GetProperty("endsNextDay").GetBoolean(), "unchanged WPF fields retained in scoped save");
        Check(!outgoing.TryGetProperty("editRef", out _) && !outgoing.TryGetProperty("requestId", out _) && !outgoing.TryGetProperty("roleGroups", out _), "client metadata and roles never forwarded");
        Check(!JsonSerializer.Serialize(saved).Contains("private-contact"), "save receipts cannot re-expose editing profile");
        var repeated = await client.SaveProfileAsync("test-bearer", command, "A:1", Current, default);
        Check(repeated == saved && writes == 1, "accepted intent never posts twice");
        var changed = JsonNode.Parse(command.GetRawText())!;
        changed["changes"]!["description"] = "Other";
        var rejected = await client.SaveProfileAsync("test-bearer", JsonSerializer.SerializeToElement(changed), "A:1", Current, default);
        Check(rejected.Error == "requestChanged" && writes == 1, "same request ID cannot change payload");

        foreach (var failure in new[] { "drop", "conflict", "forbidden", "unauthorized", "missing", "invalid", "error", "oversize", "bad-json", "same-revision", "wrong-code", "stale" })
        {
            mode = failure;
            stale = false;
            var intent = Command(edit, new { description = "Try " + failure });
            var result = await client.SaveProfileAsync("test-bearer", intent, "A:1", Current, default);
            var definitive = failure is "conflict" or "forbidden" or "unauthorized" or "missing" or "invalid";
            Check(result.Status == (definitive ? "rejected" : "unknown"), "accurate outcome for " + failure);
            var written = writes;
            stale = false;
            await client.SaveProfileAsync("test-bearer", intent, "A:1", Current, default);
            Check(writes == written, "uncertain and rejected commands never replay: " + failure);
        }
        foreach (var failure in new[] { "wrong-code", "no-permission", "forbidden" })
        {
            mode = failure;
            await Error(() => client.ReadProfileAsync("test-bearer", EditRead(edit), "A:1", default),
                failure == "forbidden" ? "communities.notAllowed" : "communities.dataInvalid");
        }
        mode = "logo-only";
        var logoSnapshot = JsonSerializer.SerializeToElement(await client.ReadProfileAsync("test-bearer", EditRead(edit), "A:1", default));
        var logoEdit = logoSnapshot.GetProperty("editRef").GetString()!;
        before = writes;
        rejected = await client.SaveProfileAsync("test-bearer", Command(logoEdit, new { description = "Denied" }), "A:1", Current, default);
        Check(rejected.Error == "notAllowed" && writes == before, "known insufficient permission blocks before transport");
        mode = "ok";
        saved = await client.SaveProfileAsync("test-bearer", Command(logoEdit, new { clearLogoImage = true }), "A:1", Current, default);
        Check(saved.Status == "accepted" && outgoing.GetProperty("updatedSections")[0].GetString() == "logo", "avatar-only edits select only logo section");
        before = calls;
        client.InvalidateProfileEdits();
        await Error(() => client.ReadProfileAsync("test-bearer", EditRead(edit), "A:1", default), "communities.refreshRequired");
        rejected = await client.SaveProfileAsync("test-bearer", Command(edit, new { description = "Expired" }), "A:1", Current, default);
        Check(rejected.Status == "rejected" && calls == before, "account invalidation clears all editing drafts");
    }

    private static async Task LateReadCannotRestoreDraft()
    {
        using var handler = new Handler(async request =>
        {
            if (request.RequestUri!.AbsolutePath == "/api/fleets/directory") return Reply(Directory());
            await Task.Yield();
            return Reply(Profile());
        });
        using var client = new CommunityClient(new Uri("https://community.invalid"), handler);
        var directory = await client.ReadAsync("test-bearer", new("mine", "", null, null), "A:1", default);
        var ready = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var release = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        handler.Respond = async request =>
        {
            ready.SetResult();
            await release.Task;
            return Reply(Profile());
        };
        var pending = client.ReadProfileAsync("test-bearer", JsonSerializer.SerializeToElement(new { schemaVersion = 1, targetRef = directory.Items[0].TargetRef }), "A:1", default);
        await ready.Task.WaitAsync(TimeSpan.FromSeconds(5));
        client.InvalidateProfileEdits();
        release.SetResult();
        await Error(() => pending, "communities.identityUnavailable");
    }

    private static async Task ConcurrentSaveIsNotDuplicated()
    {
        var ready = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var release = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var writes = 0;
        using var handler = new Handler(async request =>
        {
            if (request.RequestUri!.AbsolutePath == "/api/fleets/directory") return Reply(Directory());
            if (request.Method == HttpMethod.Get) return Reply(Profile());
            writes++;
            ready.SetResult();
            await release.Task;
            return Reply(Profile(8));
        });
        using var client = new CommunityClient(new Uri("https://community.invalid"), handler);
        var directory = await client.ReadAsync("test-bearer", new("mine", "", null, null), "A:1", default);
        var snapshot = JsonSerializer.SerializeToElement(await client.ReadProfileAsync("test-bearer",
            JsonSerializer.SerializeToElement(new { schemaVersion = 1, targetRef = directory.Items[0].TargetRef }), "A:1", default));
        var edit = snapshot.GetProperty("editRef").GetString()!;
        var current = true;
        void CheckCurrent() { if (!current) throw new AccountBridgeHostException("account.stale_generation"); }
        var first = client.SaveProfileAsync("test-bearer", Command(edit, new { description = "First" }), "A:1", CheckCurrent, default);
        await ready.Task.WaitAsync(TimeSpan.FromSeconds(5));
        try
        {
            var second = await client.SaveProfileAsync("test-bearer", Command(edit, new { description = "Second" }), "A:1", CheckCurrent, default);
            Check(second.Status == "rejected" && second.Error == "busy" && writes == 1, "only one editing write can be in flight");
            current = false;
            client.InvalidateProfileEdits();
        }
        finally { release.SetResult(); }
        var late = await first;
        Check(late.Status == "unknown" && late.ProfileRevision is null, "account change during POST does not claim a current-account success");
    }

    private static void ValidateChanges()
    {
        foreach (var changes in new object[]
        {
            new { description = "" }, new { websiteUrl = "", externalContacts = Array.Empty<object>() },
            new { activityWindows = new[] { new { days = new[] { "fri" }, startTime = "22:00", endTime = "02:00", endsNextDay = true } } },
            new { activeSystemIds = new[] { "pyro" }, joinPolicy = "Invite", publicListingEnabled = false },
            new { logoImageData = "data:image/png;base64,AQ==" }
            , new { type = "战斗 / 工业 / 探索 / PVE / PVP / FPS / 狗斗 / 空战 / 休闲 / 教学" }
        }) CommunityClient.ValidateProfileSave(Command(new string('a', 32), changes));
        foreach (var changes in new object[]
        {
            new { }, new { name = " " }, new { name = new string('船', 33) }, new { name = "A\nB" }, new { fleetCode = "B" }, new { roleGroups = Array.Empty<object>() }, new { expectedProfileRevision = 100 },
            new { bannerImageData = "data:image/png;base64,AQ==" }, new { description = (string?)null },
            new { joinPolicy = "Public" }, new { timeZoneId = "invalid-zone" }, new { activeSystemIds = new[] { "unknown" } },
            new { activityWindows = new[] { new { days = new[] { "fri" }, startTime = "25:00", endTime = "02:00", endsNextDay = true } } },
            new { logoImageData = "data:image/png;base64,AQ==", clearLogoImage = true }
            , new { description = new string('中', 201) }, new { recruitingNote = new string('a', 401) },
            new { logoText = new string('中', 9) }, new { websiteUrl = new string('a', 257) },
            new { type = "PVE / 休闲" }, new { type = "战斗 / PVE / PVP / FPS / 狗斗 / 空战 / 护航" }
        })
        {
            try { CommunityClient.ValidateProfileSave(Command(new string('a', 32), changes)); throw new InvalidOperationException("invalid changes accepted"); }
            catch (AccountBridgeHostException e) when (e.Code == "communities.dataInvalid") { }
        }
    }

    private static JsonElement EditRead(string editRef) => JsonSerializer.SerializeToElement(new { schemaVersion = 1, editRef });
    private static JsonElement Command(string editRef, object changes) => JsonSerializer.SerializeToElement(new { schemaVersion = 1, requestId = Guid.NewGuid().ToString("N"), editRef, changes });
    private static HttpResponseMessage Reply(object body) => new(HttpStatusCode.OK) { Content = JsonContent.Create(body) };
    private static object Directory() => new
    {
        schemaVersion = 1, membershipModelVersion = 2, view = "mine", query = "", next = (string?)null,
        items = new[] { new { code = "A", name = "Organization A", description = "", language = "", activeTime = "", memberCount = 1, relationship = "owner", joinMode = "direct", actions = Array.Empty<string>() } }
    };
    private static JsonNode Profile(long revision = 7) => JsonSerializer.SerializeToNode(new
    {
        schemaVersion = 1, membershipModelVersion = 2, code = "A", name = "Organization A", profileRevision = revision, hasLogo = true, hasBanner = true,
        access = new { canEditProfile = true, canEditLogo = true, canEditBanner = false }, members = "do-not-forward",
        profile = new
        {
            description = "Original", type = "探索", activeTime = "22:00–02:00", joinPolicy = "Open", logoText = "ORG",
            activeDaysDescription = "Friday", activityCadence = "Weekly", timeZoneId = "UTC", recruitingTarget = "Anyone", recruitingNote = "",
            inviteCodeCreationPolicy = "commander", fleetInvitationCardPolicy = "management", publicMemberScaleMode = "Exact", publicShipScaleMode = "TypeSummary", language = "English", websiteUrl = (string?)null,
            emailNotificationsEnabled = false, recruitingEnabled = true, publicListingEnabled = false,
            publicShowDescription = true, publicShowTags = true, publicShowActiveSystems = true, publicShowActivityTime = false, publicShowExternalContacts = false,
            activityWindows = new[] { new { days = new[] { "fri" }, startTime = "22:00", endTime = "02:00", endsNextDay = true } },
            activeSystemIds = new[] { "pyro" }, externalContacts = new[] { new { platform = "Discord", value = "private-contact" } }, internalOnly = "do-not-forward"
        }
    })!;
    private static async Task Error(Func<Task<object>> action, string code)
    {
        try { await action(); throw new InvalidOperationException("Expected " + code); }
        catch (AccountBridgeHostException e) when (e.Code == code) { }
    }
    private static void Check(bool value, string message) { if (!value) throw new InvalidOperationException(message); }
    private sealed class Handler(Func<HttpRequestMessage, Task<HttpResponseMessage>> send) : HttpMessageHandler
    {
        internal Func<HttpRequestMessage, Task<HttpResponseMessage>> Respond { get; set; } = send;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) => Respond(request);
    }
}
