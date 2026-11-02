using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.HostRuntime.Auth;

internal static class SelectedProfileImportTests
{
    internal static async Task Run()
    {
        var uri = new Uri("http://127.0.0.1:9/");
        using var handler = new Handler();
        var oauth = new OAuthPkceClient(new ScmHttpClient(handler), new Vault(),
            new ScmOAuthOptions("synthetic", uri, uri, uri, "synthetic", "synthetic", "openid profile.read", "/callback"));
        var session = new ScmOAuthSession("synthetic", "owner", "Pilot", "synthetic-token",
            DateTimeOffset.UtcNow.AddHours(1), ["profile.read"]);
        var selection = new LegacyProfileImportSelection(["hangar-summary"], [], false);
        var result = await oauth.ExecuteLegacyProfileMigrationAsync(session, "preview", null, false, default,
            new("synthetic-old", " synthetic-secret "), selection);
        Check(result.View.Choices?.Modules.Single() == "hangar-summary", "server selection is acknowledged");
        Check(result.View.SelectedContent?.Modules.Single() == new LegacyProfileSelectedModule("hangar-summary", 2),
            "selected layout content crosses the real transport");
        handler.Avatar = true;
        var avatarSelection = selection with { UseLegacyAvatar = true };
        var avatarResult = await oauth.ExecuteLegacyProfileMigrationAsync(session, "preview", null, false, default,
            selection: avatarSelection);
        Check(avatarResult.View.Choices?.UseLegacyAvatar == true, "avatar selection acknowledged independently");
        handler.HideAvatarPreview = true;
        try { await oauth.ExecuteLegacyProfileMigrationAsync(session, "preview", null, false, default, selection: avatarSelection);
            throw new Exception("missing avatar preview accepted"); }
        catch (ScmApiProtocolException) { }
        handler.HideAvatarPreview = false;
        handler.Avatar = false;
        try { await oauth.ExecuteLegacyProfileMigrationAsync(session, "preview", null, false, default, selection: avatarSelection);
            throw new Exception("missing avatar acknowledgement accepted"); }
        catch (ScmApiProtocolException) { }
        handler.Mismatch = true;
        try { await oauth.ExecuteLegacyProfileMigrationAsync(session, "preview", null, false, default, selection: selection);
            throw new Exception("mismatched selection accepted"); }
        catch (ScmApiProtocolException) { }
        int requests = handler.Requests;
        foreach (var invalid in new[] {
            new LegacyProfileImportSelection(["inventory"], [], false),
            new LegacyProfileImportSelection([], [], false),
            new LegacyProfileImportSelection(["hangar-summary"], ["skilled-roles"], false),
            new LegacyProfileImportSelection(["hangar-summary", "hangar-summary"], [], false) })
        {
            try { await oauth.ExecuteLegacyProfileMigrationAsync(session, "preview", null, false, default, selection: invalid);
                throw new Exception("invalid selection accepted"); }
            catch (ArgumentException) { }
        }
        Check(requests == handler.Requests, "invalid selections never reach transport");
        handler.Mismatch = false;
        handler.HideContent = true;
        try { await oauth.ExecuteLegacyProfileMigrationAsync(session, "preview", null, false, default, selection: selection);
            throw new Exception("missing selected content accepted"); }
        catch (ScmApiProtocolException) { }
        var valid = new LegacyProfileSelectedContent(null, [new("hangar-summary", 2)], null, null, null);
        handler.HideContent = false;
        handler.ExpectedPrevious = "completed-ticket";
        await oauth.ExecuteLegacyProfileMigrationAsync(session, "preview", null, false, default,
            selection: selection with { PreviousCompletedPreviewId = handler.ExpectedPrevious });
        var choices = new LegacyProfileImportChoices(1, ["hangar-summary"], [], false, []);
        Check(valid.Matches(choices), "selected content agrees with consent");
        Check(!(valid with { CallSign = "unselected name" }).Matches(choices), "unselected name rejected");
        Check(!(valid with { SkilledRoles = [] }).Matches(choices), "unselected roles rejected");
        Check(!(valid with { Modules = [new("hangar-summary", 4)] }).Matches(choices), "invalid module size rejected");
        Console.WriteLine("PASS selected profile import wire, acknowledgement and rejected selections");
    }
    private static void Check(bool value, string message) { if (!value) throw new Exception(message); }
    private sealed class Handler : HttpMessageHandler
    {
        internal int Requests;
        internal bool Mismatch;
        internal bool Avatar;
        internal bool HideAvatarPreview;
        internal bool HideContent;
        internal string? ExpectedPrevious;
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Requests++;
            Check(request.Method == HttpMethod.Post && request.RequestUri!.AbsolutePath.EndsWith("/selected-preview"), "selected route only");
            Check(request.Headers.Authorization?.Parameter == "synthetic-token", "current SCM bearer");
            using var json = JsonDocument.Parse(await request.Content!.ReadAsStringAsync(token));
            Check(json.RootElement.GetProperty("previousCompletedPreviewId").GetString() == ExpectedPrevious,
                "follow-up acknowledgement crosses transport separately from selected profile fields");
            Check(json.RootElement.GetProperty("selection").GetProperty("modules")[0].GetString() == "hangar-summary", "exact selected module");
            Check(!json.RootElement.GetProperty("useLegacyCallSign").GetBoolean(), "callsign remains unselected");
            Check(json.RootElement.GetProperty("useLegacyAvatar").GetBoolean() == (Requests is 2 or 3 or 4), "avatar consent travels separately");
            if (Requests == 1) Check(json.RootElement.GetProperty("credentials").GetProperty("password").GetString() == " synthetic-secret ", "password unchanged");
            var summary = new LegacyProfileMigrationSummary("Current", "", 1, 0, null);
            return new(HttpStatusCode.OK) { Content = JsonContent.Create(new LegacyProfileMigrationView("previewed", "ticket",
                ExpiresAt: DateTimeOffset.UtcNow.AddMinutes(15), Source: summary, Target: summary,
                Choices: new(1, [Mismatch ? "favorite-ships" : "hangar-summary"], [], false, [], Avatar),
                AvatarPreview: Avatar && !HideAvatarPreview
                    ? "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aX1cAAAAASUVORK5CYII=" : null,
                SelectedContent: HideContent ? null : new(null, [new("hangar-summary", 2)], null, null, null))) };
        }
    }
    private sealed class Vault : ITokenVault
    {
        public void SaveRefreshToken(string key, string value) => throw new InvalidOperationException("No credential writes");
        public string? LoadRefreshToken(string key) => null;
        public string? LoadActiveAccountKey() => null;
        public void DeleteRefreshToken(string key) { }
    }
}
