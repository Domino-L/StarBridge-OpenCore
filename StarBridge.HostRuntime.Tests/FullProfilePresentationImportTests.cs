using StarBridge.Core.Profiles;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.Profiles;
using StarBridge.NativeBridge;

internal static class FullProfilePresentationImportTests
{
    internal static async Task Run()
    {
        var root = Path.Combine(Path.GetTempPath(), "starbridge-full-display-" + Guid.NewGuid().ToString("N"));
        try
        {
            var owner = new BridgeAccountContext("test", "https://authority.invalid", "synthetic-full-owner");
            var store = new LocalPersonalProfileStore(root);
            var before = new LocalProfileContent("New", "Edited", 3, "none", [], []);
            store.Save(owner, 0, Guid.NewGuid().ToString("N"), before, () => true);
            var content = PersonalProfileContentContract.Empty with {
                Introduction = "Old", SkilledRoles = ["historic role"],
                Modules = [new("hangar-summary", 2, false, 0, -1)],
                ActivityRhythm = "周末为主", AvailabilityTimeZoneId = "America/Regina",
                ShowOnlineTime = true, AvailabilityWindows = [new([6], "18:00", "23:00")]
            };
            var view = new LegacyProfileMigrationView("previewed", "full-ticket",
                ExpiresAt: DateTimeOffset.UtcNow.AddMinutes(15), Conflict: true,
                Choices: new(2, ["hangar-summary"], ["hangar-summary"], true, []),
                Presentation: new("Old", 1, "stanton-orbit", content));
            await Wire(view);
            var selection = new LegacyProfileImportSelection([], [], false, ReplaceAllDisplayContent: true);
            await new SelectedProfileImportCoordinator(store).RunAsync(owner, () => true, local => {
                Check(local.Stage(view, selection) == view, "Full preview acknowledged");
                Check(System.Text.Json.JsonSerializer.Serialize(store.Read(owner).Content) ==
                    System.Text.Json.JsonSerializer.Serialize(before), "Preview preserves current display");
                local.BeforeConfirm(view.PreviewId!);
                return Task.FromResult(0);
            });
            var completed = view with { State = "completed", ExpiresAt = null, CompletedRevision = 8 };
            await new SelectedProfileImportCoordinator(store).RunAsync(owner, () => true, local => {
                Check(local.Status(completed).State == "localApplyRequired", "Restart requires explicit recovery");
                local.BeforeConfirm(view.PreviewId!);
                local.Apply(completed);
                return Task.FromResult(0);
            });
            var saved = store.Read(owner);
            Check(saved.Revision == 2 && saved.Content!.CallSign == "Old" && saved.Content.Introduction == "Old" &&
                saved.Content.AvatarStyle == 1 && saved.Content.WallpaperId == "stanton-orbit" &&
                saved.Content.Modules.Single().IsVisible == false && saved.Content.Schedule!.Windows.Count == 1 &&
                saved.Content.PlayStyle!.Roles!.Single() == "historic role" && saved.Content.PreserveEmptyFields,
                "All presentation fields are inherited without default recovery");
            var journal = Directory.GetFiles(store.ImportJournalDirectory, "*.dat").Single();
            Check(!System.Text.Encoding.UTF8.GetString(File.ReadAllBytes(journal)).Contains("Edited"), "Backup is encrypted");
            store.Save(owner, 2, Guid.NewGuid().ToString("N"), saved.Content! with { Introduction = "Later" }, () => true);
            await new SelectedProfileImportCoordinator(store).RunAsync(owner, () => true, local => {
                local.Apply(completed);
                Check(store.Read(owner).Content!.Introduction == "Later", "Receipt replay never overwrites later display");
                Check(local.Stage(view with { PreviewId = "next" }, selection).State == "previewed", "New explicit round staged");
                return Task.FromResult(0);
            });
            store.Save(owner, 3, Guid.NewGuid().ToString("N"), saved.Content! with { Introduction = "Concurrent" }, () => true);
            await Expect("profile_local.conflict", () => new SelectedProfileImportCoordinator(store).RunAsync(owner, () => true,
                local => { local.BeforeConfirm("next"); return Task.FromResult(0); }));
            await Expect("profile_local.import_reselection_required", () => new SelectedProfileImportCoordinator(store)
                .RunAsync(owner, () => true, local => Task.FromResult(local.Stage(view with {
                    Presentation = view.Presentation! with { Content = content with { FavoriteShipCodes = ["foreign-instance"] } }
                }, selection))));
            Check(store.Read(owner).Content!.Introduction == "Concurrent", "Unresolved favorite does not write display");
            await Expect("profile_local.import_reselection_required", () => new SelectedProfileImportCoordinator(store)
                .RunAsync(owner, () => true, local => Task.FromResult(local.Stage(view with {
                    Presentation = view.Presentation! with { Content = content with { ShowOnlineTime = false } }
                }, selection))));
            Check(store.Read(owner).Content!.Introduction == "Concurrent", "Hidden schedule is rejected without data loss");
            await new SelectedProfileImportCoordinator(store).RunAsync(owner with { Subject = "other" }, () => true, local => {
                Check(local.Status(completed).State == "localPreviewRequired", "Other owner cannot borrow full intent");
                return Task.FromResult(0);
            });
            Console.WriteLine("PASS full display preview, encrypted backup, restart, replay, conflict and owner isolation");
        }
        finally { if (Directory.Exists(root)) Directory.Delete(root, true); }
    }
    private static void Check(bool value, string message) { if (!value) throw new InvalidOperationException(message); }
    private static async Task Wire(LegacyProfileMigrationView view)
    {
        var summary = new LegacyProfileMigrationSummary("Synthetic", "", 1, 0, null);
        using var handler = new WireHandler(view with { Source = summary, Target = summary });
        var endpoint = new Uri("http://127.0.0.1:9/");
        var oauth = new OAuthPkceClient(new ScmHttpClient(handler), new Vault(),
            new ScmOAuthOptions("test", endpoint, endpoint, endpoint, "test", "test", "openid profile.read", "/callback"));
        var read = new ScmOAuthSession("test", "owner", "Synthetic", "read-fixture", DateTimeOffset.UtcNow.AddHours(1), ["profile.read"]);
        var selection = new LegacyProfileImportSelection([], [], false, ReplaceAllDisplayContent: true);
        var preview = await oauth.ExecuteLegacyProfileMigrationAsync(read, "preview", null, false, default, selection: selection);
        Check(System.Text.Json.JsonSerializer.Serialize(preview.View.Presentation) ==
            System.Text.Json.JsonSerializer.Serialize(handler.View.Presentation), "Full presentation crosses real transport");
        var write = read with { AccessToken = "write-fixture", Capabilities = ["profile.read", "profile.write"] };
        try { await oauth.ExecuteLegacyProfileMigrationAsync(write, "confirm", view.PreviewId, false, default, presentationConfirm: true);
            throw new InvalidOperationException("Missing full consent accepted"); }
        catch (ArgumentException) { }
        Check(handler.Requests == 1, "Missing full consent never sends a request");
        await oauth.ExecuteLegacyProfileMigrationAsync(write, "confirm", view.PreviewId, true, default, presentationConfirm: true);
        Check(handler.Requests == 2, "Full confirmation is a single explicit request");
    }
    private sealed class WireHandler(LegacyProfileMigrationView view) : HttpMessageHandler
    {
        internal LegacyProfileMigrationView View => view;
        internal int Requests;
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Requests++;
            using var body = System.Text.Json.JsonDocument.Parse(await request.Content!.ReadAsStringAsync(token));
            var preview = request.RequestUri!.AbsolutePath.EndsWith("/presentation-preview");
            Check(request.Method == HttpMethod.Post && (preview || request.RequestUri.AbsolutePath.EndsWith("/presentation-confirm")),
                "Full mode never uses retired or selected endpoints");
            Check(request.Headers.Authorization?.Parameter == (preview ? "read-fixture" : "write-fixture"), "Scoped full import grant");
            if (preview)
                Check(body.RootElement.GetProperty("replaceAllDisplayContent").GetBoolean() &&
                    !body.RootElement.TryGetProperty("selection", out _), "Full preview has explicit independent mode");
            else
                Check(body.RootElement.EnumerateObject().Count() == 2 && body.RootElement.GetProperty("replaceExisting").GetBoolean() &&
                    body.RootElement.GetProperty("previewId").GetString() == view.PreviewId, "Exact ticket and full overwrite consent");
            return new(System.Net.HttpStatusCode.OK) { Content = System.Net.Http.Json.JsonContent.Create(preview ? view :
                view with { State = "completed", Conflict = false, ExpiresAt = null, CompletedRevision = 8 }) };
        }
    }
    private sealed class Vault : ITokenVault
    {
        public void SaveRefreshToken(string key, string value) => throw new InvalidOperationException("No token persistence in fixture");
        public string? LoadRefreshToken(string key) => null;
        public string? LoadActiveAccountKey() => null;
        public void DeleteRefreshToken(string key) { }
    }
    private static async Task Expect(string code, Func<Task> action)
    {
        try { await action(); throw new InvalidOperationException("Expected " + code); }
        catch (LocalProfileException error) when (error.Code == code) { }
    }
}
