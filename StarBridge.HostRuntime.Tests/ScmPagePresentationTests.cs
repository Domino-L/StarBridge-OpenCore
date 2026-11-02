using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.Core.Profiles;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.NativeBridge;

internal static partial class LegacyPasswordLoginTests
{
    internal static async Task ScmPagePresentationWrite()
    {
        foreach (var mode in new[] { "saved", "denied", "wrong-subject", "missing-scope", "stale", "source-changed", "conflict", "read-failed", "read-forbidden", "read-invalid", "read-unauthorized", "wrong-read", "server-unconfirmed", "later-revision", "disposed" })
        {
            using var transport = new PageTransport { Mode = mode };
            var uri = new Uri("http://127.0.0.1:9/");
            var oauth = new OAuthPkceClient(new ScmHttpClient(transport), new ScmBackgroundVault(),
                new("synthetic", uri, uri, uri, "synthetic", "synthetic", "openid profile.read", "/callback"));
            var authorization = new ScmBackgroundAuthorization { Mode = mode };
            using var host = new ScmAccountBridgeHost(oauth, new ScmProfileCacheStore(), "integration", () => null,
                initialSession: new("synthetic", "owner", "Synthetic", "synthetic-read-token", DateTimeOffset.MaxValue, ["profile.read"]),
                profileAuthorization: authorization);
            var owner = host.CurrentContext!;
            transport.AfterWrite = mode == "disposed" ? () => { host.Dispose(); return Task.CompletedTask; } : null;
            var edit = new PersonalProfilePageEditContract(mode == "stale" ? 6 : 7,
                new string(mode == "source-changed" ? 'b' : 'a', 64), ["introduction"], 0, "none",
                PersonalProfileContentContract.Empty with { Introduction = "Edited" });
            using var dispatcher = new AccountBridgeDispatcher(host);
            var invalid = await dispatcher.DispatchAsync(BridgeEnvelope.Request("personalProfile.updatePresentation", "invalid-page", host.Generation,
                new { schemaVersion = 1, subject = "other-owner" }, owner));
            Check(invalid.Response.Error?.Code == "personalProfile.write_invalid" && authorization.Calls == 0 && transport.Writes == 0,
                "invalid bridge input crossed authorization boundary");
            try
            {
                PersonalProfileDocumentContract result;
                if (mode == "saved")
                {
                    var content = JsonSerializer.SerializeToNode(edit.Content, new JsonSerializerOptions(JsonSerializerDefaults.Web))!.AsObject();
                    content.Remove("presenceIntent");
                    var response = await dispatcher.DispatchAsync(BridgeEnvelope.Request("personalProfile.updatePresentation", "page-save", host.Generation,
                        new { schemaVersion = 1, expectedRevision = edit.ExpectedRevision, sourceVersion = edit.SourceVersion,
                            editedGroups = edit.EditedGroups, avatarStyle = edit.AvatarStyle, wallpaperId = edit.WallpaperId, content }, owner));
                    Check(response.Response.Error is null && response.Response.Payload.GetProperty("profile").GetProperty("presentation")
                        .GetProperty("origins").GetProperty("introduction").GetString() == "custom", "bridge dropped confirmation metadata");
                    result = await host.GetPersonalProfileAsync(owner, default);
                }
                else result = await host.UpdatePagePresentationAsync(owner, edit, default);
                Check(mode == "saved" && result.Content.Introduction == "Edited" && result.Revision == 8, "unexpected page success: " + mode);
            }
            catch (AccountBridgeHostException error)
            {
                Check(mode != "saved", "page save failed: " + error.Code);
                if (mode is "read-failed" or "read-forbidden" or "read-invalid" or "read-unauthorized" or "wrong-read" or "server-unconfirmed" or "later-revision") Check(error.Code == "personalProfile.write_unconfirmed", "missing unconfirmed state: " + mode);
                if (mode is "stale" or "source-changed" or "conflict") Check(error.Code == AccountBridgeStableErrors.PersonalProfileWriteConflict, "missing conflict state");
            }
            var shouldWrite = mode is "saved" or "conflict" or "read-failed" or "read-forbidden" or "read-invalid" or "read-unauthorized" or "wrong-read" or "server-unconfirmed" or "later-revision" or "disposed";
            Check(transport.Writes == (shouldWrite ? 1 : 0), "page write replay or authority bypass: " + mode);
            if (mode is "server-unconfirmed" or "later-revision")
            {
                // The write may have committed before its acknowledgement failed.
                // Normal read authority can inspect it without requesting another grant.
                var recovered = await host.GetPersonalProfileAsync(owner, default);
                Check(recovered.Revision == 8 && recovered.Content.Introduction == "Edited",
                    "uncertain write could not be inspected with the normal session");
                Check(transport.Writes == 1 && authorization.Calls == 1,
                    "readback replayed an uncertain page mutation");
            }
            if (mode is "stale" or "source-changed") Check(authorization.Calls == 0, "stale edit requested authorization");
            if (mode == "saved")
            {
                await host.LogoutAsync(owner, default);
                try
                {
                    await host.UpdatePagePresentationAsync(owner, edit with { ExpectedRevision = 8 }, default);
                    throw new InvalidOperationException("Signed out account edited a page");
                }
                catch (AccountBridgeHostException) { }
                Check(transport.Writes == 1, "old account wrote after logout");
            }
        }
    }

    private sealed class PageTransport : HttpMessageHandler
    {
        internal string Mode = "saved";
        internal int Writes;
        internal Func<Task>? AfterWrite;
        private PersonalProfileDocumentContract Profile(bool saved)
        {
            var origins = new[] { "introduction", "layout", "favorites", "schedule", "playStyle", "wishlist", "avatarStyle", "wallpaper" }
                .ToDictionary(group => group, _ => "default");
            origins["introduction"] = saved ? "custom" : "linkedLegacy";
            return new(3, "fixture-public", false, saved ? 8 : 7, DateTimeOffset.UnixEpoch, new("Synthetic", ""),
                PersonalProfileContentContract.Empty with { Introduction = saved ? "Edited" : "Inherited" }, null,
                Presentation: new(1, origins, new string('a', 64)));
        }
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            if (request.Method == HttpMethod.Post && request.RequestUri!.AbsolutePath.EndsWith("/revoke"))
                return new(HttpStatusCode.OK) { Content = JsonContent.Create(new { }) };
            if (request.Method == HttpMethod.Patch)
            {
                Writes++;
                Check(request.Headers.Authorization?.Parameter == "synthetic-write-token", "page mutation grant");
                Check(request.RequestUri!.AbsolutePath.EndsWith("/presentation"), "page mutation route");
                if (AfterWrite is not null) await AfterWrite();
                if (Mode == "server-unconfirmed") return new(HttpStatusCode.ServiceUnavailable)
                { Content = JsonContent.Create(new { error = "PERSONAL_PROFILE_SOURCE_UNAVAILABLE" }) };
                if (Mode == "later-revision") return new(HttpStatusCode.OK)
                { Content = JsonContent.Create(Profile(true) with { Revision = 9 }) };
                return new(Mode == "conflict" ? HttpStatusCode.Conflict : HttpStatusCode.OK) { Content = JsonContent.Create(Profile(true)) };
            }
            Check(request.Method == HttpMethod.Get && request.Headers.Authorization?.Parameter == "synthetic-read-token", "normal session replaced by write grant");
            if (Mode == "read-failed" && Writes > 0) return new(HttpStatusCode.ServiceUnavailable);
            if (Writes > 0 && Mode == "read-forbidden") return new(HttpStatusCode.Forbidden);
            if (Writes > 0 && Mode == "read-unauthorized") return new(HttpStatusCode.Unauthorized);
            if (Writes > 0 && Mode == "read-invalid") return new(HttpStatusCode.OK) { Content = new StringContent("{invalid") };
            var profile = Profile(Writes > 0);
            if (Mode == "wrong-read" && Writes > 0) profile = profile with { Content = profile.Content with { Introduction = "Other device" } };
            return new(HttpStatusCode.OK) { Content = JsonContent.Create(profile) };
        }
    }
}
