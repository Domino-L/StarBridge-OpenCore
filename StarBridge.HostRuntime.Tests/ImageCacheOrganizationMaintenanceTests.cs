using System.Security.Cryptography;
using System.Net;
using System.Net.Http.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Communities;
using StarBridge.HostRuntime.Support;
using StarBridge.NativeBridge;

internal static class ImageCacheOrganizationMaintenanceTests
{
    private const string Image = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=";

    internal static async Task ProtectedImagesAreClearedWithoutRemovingDirectory()
    {
        using var f = new Fixture();
        f.Seed(Image);
        f.Write("Images/fleet-SYNTH-logo-012345abcdef.png", "synthetic managed image");
        f.Write("Images/avatar.png", "synthetic excluded avatar");
        f.Write("UserAssets/source.png", "synthetic user original");
        f.Write("Images/HangarImports/source.image", "synthetic import");
        var before = f.Store.ReadSelectedOrganizations(f.Owner, () => true)!;
        var accountHash = f.AccountHash;
        var count = await f.Clear();
        var current = new OfflineAccountStore(f.Root).ReadSelectedOrganizations(f.Owner, () => true);
        Require(current is not null && current.Items.Count == 1, "clear retains the protected organization directory");
        Require(current!.Items[0].LogoImageData is null && current.Items[0].LogoCachedAtUtc is null,
            "actual maintenance clears the embedded protected logo, not only legacy Images files");
        Require(current.Items[0].Id == before.Items[0].Id && current.Items[0].Name == before.Items[0].Name &&
            current.CachedAtUtc == before.CachedAtUtc && current.Complete == before.Complete,
            "image maintenance preserves directory identity, name, age and completeness");
        Require(f.AccountHash == accountHash, "account snapshot is byte-for-byte unchanged");
        Require(count == 2, "one protected image plus one known legacy copy");
        f.Kept("Images/avatar.png", "synthetic excluded avatar");
        f.Kept("UserAssets/source.png", "synthetic user original");
        f.Kept("Images/HangarImports/source.image", "synthetic import");
        Require(await f.Clear() == 0, "repeated maintenance has no remaining image copy");
        Require(new OfflineAccountStore(f.Root).ReadSelectedOrganizations(f.Owner with { Subject = "different-owner" }, () => true) is null,
            "maintenance cannot select another account");
    }

    internal static async Task OldDirectoryCannotRepersistImage()
    {
        using var f = new Fixture(); f.Seed(Image);
        using var lease = f.Store.BeginOrganizationRead(f.Owner, () => true)!;
        await f.Clear();
        f.Store.ObserveOrganizations(f.Owner, 1, null, null,
            [new("SYNTH", "Updated metadata", Image, false)], () => true, lease);
        f.Store.CompleteOrganizationRead(lease, false, () => true);
        var result = new OfflineAccountStore(f.Root).ReadSelectedOrganizations(f.Owner, () => true);
        Require(result?.Items.Single().Name == "Updated metadata", "an admitted directory can still finish its metadata");
        Require(result!.Items.Single().LogoImageData is null, "pre-maintenance directory result cannot refill protected image bytes");
        using var fresh = f.Store.BeginOrganizationRead(f.Owner, () => true)!;
        f.Store.ObserveOrganizations(f.Owner, 1, null, null,
            [new("SYNTH", "Updated metadata", Image, false)], () => true, fresh);
        f.Store.CompleteOrganizationRead(fresh, false, () => true);
        Require(f.Store.ReadSelectedOrganizations(f.Owner, () => true)!.Items.Single().LogoImageData == Image,
            "fresh authorized work after maintenance can cache a new image");
    }

    internal static async Task ZeroCountStillFencesPendingImages()
    {
        using var f = new Fixture();
        using var lease = f.Store.BeginOrganizationRead(f.Owner, () => true)!;
        Require(await f.Clear() == 0, "no image has been received yet");
        f.Store.ObserveOrganizations(f.Owner, 1, null, null,
            [new("SYNTH", "First directory", Image, false)], () => true, lease);
        f.Store.CompleteOrganizationRead(lease, false, () => true);
        var result = f.Store.ReadSelectedOrganizations(f.Owner, () => true);
        Require(result?.Items.Single().Name == "First directory", "first metadata can finish after an empty cleanup");
        Require(result!.Items.Single().LogoImageData is null, "zero-count maintenance still retires already admitted image publication");
    }

    internal static async Task RefusalAndOfflineSelectionRemainAuthoritative()
    {
        using var f = new Fixture(); f.Seed(Image);
        using var late = f.Store.BeginOrganizationRead(f.Owner, () => true)!;
        using var refused = f.Store.BeginOrganizationRead(f.Owner, () => true)!;
        await f.Clear();
        f.Store.CompleteOrganizationRead(refused, true, () => true);
        f.Store.ObserveOrganizations(f.Owner, 1, null, null,
            [new("SYNTH", "Late denied result", Image, false)], () => true, late);
        f.Store.CompleteOrganizationRead(late, false, () => true);
        Require(f.Store.ReadSelectedOrganizations(f.Owner, () => true) is null, "cleanup cannot undo a hard read refusal");
        f.Seed(Image); f.Store.Pin(f.Owner, 7, () => true);
        var accountHash = f.AccountHash;
        await f.Clear();
        var offline = new OfflineAccountStore(f.Root).ReadOfflineOrganizations(7, () => true);
        Require(offline?.Items.Count == 1 && offline.Items.Single().LogoImageData is null,
            "offline metadata remains selected but its included logo is cleared");
        Require(f.AccountHash == accountHash && f.Store.ReadOfflineOrganizations(8, () => true) is null,
            "cleanup neither rewrites the offline selection nor promotes another revision");
    }

    internal static async Task OldMediaObservationCannotRepersistImage()
    {
        using var f = new Fixture(); f.Seed(Image);
        var old = f.Store.CaptureOrganizationImageRead(f.Owner, () => true)!;
        await f.Clear();
        f.Store.ObserveOrganizationLogo(f.Owner, "SYNTH", Image, () => true, old);
        Require(f.Store.ReadSelectedOrganizations(f.Owner, () => true)!.Items.Single().LogoImageData is null,
            "media admitted before cleanup cannot repersist its completed logo");
        var fresh = f.Store.CaptureOrganizationImageRead(f.Owner, () => true)!;
        f.Store.ObserveOrganizationLogo(f.Owner, "SYNTH", Image, () => true, fresh);
        Require(f.Store.ReadSelectedOrganizations(f.Owner, () => true)!.Items.Single().LogoImageData == Image,
            "a new media observation remains writable after cleanup");
    }

    internal static async Task SlowNativeDirectoryCannotRefillMemory()
    {
        using var f = new Fixture(); f.Seed(Image);
        using var handler = new DirectoryHttp();
        using var client = new CommunityClient(new("https://community.example.test/"), handler);
        const string scope = "synthetic-image-maintenance-scope";
        var first = await client.ReadAsync("synthetic-access", new("mine", "", null, null), scope, default);
        Require(client.CachedSharingLogo(scope, "SYNTH") == Image, "real Native directory caches its included logo");
        handler.Gate = new(TaskCreationOptions.RunContinuationsAsynchronously);
        handler.Entered = new(TaskCreationOptions.RunContinuationsAsynchronously);
        var pending = client.ReadAsync("synthetic-access", new("mine", "", null, null), scope, default);
        await handler.Entered.Task.WaitAsync(TimeSpan.FromSeconds(5));
        var calls = handler.Calls;
        await f.Clear(client.ClearDownloadableImageReadCaches);
        Require(handler.Calls == calls, "maintenance itself starts no HTTP");
        Require(client.CachedSharingLogo(scope, "SYNTH") is null, "actual maintenance callback clears Native retained logo bytes");
        Require(client.ObserveDirectoryDisplay(first, scope).Single().Code == "SYNTH", "image reset does not erase scoped directory targets");
        handler.Gate.SetResult(true);
        var late = await pending;
        Require(late.Items.Single().Name == "Synthetic Organization", "a held directory still finishes its valid metadata");
        Require(client.CachedSharingLogo(scope, "SYNTH") is null, "pre-clear Native directory response cannot refill its logo cache");
        handler.Gate = null;
        await client.ReadAsync("synthetic-access", new("mine", "", null, null), scope, default);
        Require(client.CachedSharingLogo(scope, "SYNTH") == Image && handler.Calls == calls + 1,
            "fresh Native read can retain a logo without a forced HTTP-client shutdown");
    }

    internal static async Task ContinuationSurvivesImageOnlyChange()
    {
        using var f = new Fixture();
        f.Store.ObserveOrganizations(f.Owner, 1, null, "page-two", [new("ONE", "One", Image, false)], () => true);
        var before = f.Store.ReadSelectedOrganizations(f.Owner, () => true)!;
        await f.Clear();
        f.Store.ObserveOrganizations(f.Owner, 1, "page-two", null, [new("TWO", "Two", null, false)], () => true);
        var after = f.Store.ReadSelectedOrganizations(f.Owner, () => true);
        Require(after is { Complete: true, Items.Count: 2 } && after.Items[0].Id == before.Items[0].Id,
            "cross-instance image-only version change preserves the existing pagination cursor");
        Require(after!.Items.All(row => row.LogoImageData is null), "metadata continuation does not revive the cleared first-page image");
    }

    internal static async Task CorruptPolicyDoesNotReportSuccessOrDeleteLegacyFiles()
    {
        using var f = new Fixture(); f.Seed(Image);
        f.Write("Images/fleet-SYNTH-logo-012345abcdef.png", "synthetic managed image");
        var directoryHash = Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(Path.Combine(f.Root, "offline-account-v1", "organizations.bin"))));
        f.Write("offline-account-v1/organizations-policy.bin", "synthetic corrupt policy");
        using var support = new ApplicationSupportBridgeDispatcher(f.Root, null);
        var result = await support.DispatchAsync(BridgeEnvelope.Request("diagnostics.clearImageCache",
            Guid.NewGuid().ToString("N"), 0, new { schemaVersion = 1 }));
        Require(result.Response.Status != "ok", "unreadable protected policy cannot confirm cleanup");
        f.Kept("Images/fleet-SYNTH-logo-012345abcdef.png", "synthetic managed image");
        Require(Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(Path.Combine(f.Root, "offline-account-v1", "organizations.bin")))) == directoryHash,
            "failed policy validation does not rewrite protected metadata");
    }

    internal static async Task MediaAdmittedBeforeFirstDirectoryIsFenced()
    {
        using var f = new Fixture();
        var old = f.Store.CaptureOrganizationImageRead(f.Owner, () => true)!;
        Require(await f.Clear() == 0, "no organization directory or image existed at cleanup");
        f.Seed(null);
        f.Store.ObserveOrganizationLogo(f.Owner, "SYNTH", Image, () => true, old);
        Require(f.Store.ReadSelectedOrganizations(f.Owner, () => true)!.Items.Single().LogoImageData is null,
            "media admitted before the first directory cannot publish across an empty cleanup");
        var fresh = f.Store.CaptureOrganizationImageRead(f.Owner, () => true)!;
        f.Store.ObserveOrganizationLogo(f.Owner, "SYNTH", Image, () => true, fresh);
        Require(f.Store.ReadSelectedOrganizations(f.Owner, () => true)!.Items.Single().LogoImageData == Image,
            "new media can publish after that first directory is available");
    }

    internal static async Task WriterContentionCannotConfirmCleanup()
    {
        using var f = new Fixture(); f.Seed(Image);
        f.Write("Images/fleet-SYNTH-logo-012345abcdef.png", "synthetic managed image");
        var before = f.AccountHash;
        using var writer = new FileStream(Path.Combine(f.Root, "offline-account-v1", "snapshot.bin.lock"), FileMode.OpenOrCreate,
            FileAccess.ReadWrite, FileShare.None);
        using var support = new ApplicationSupportBridgeDispatcher(f.Root, null);
        var result = await support.DispatchAsync(BridgeEnvelope.Request("diagnostics.clearImageCache",
            Guid.NewGuid().ToString("N"), 0, new { schemaVersion = 1 }));
        Require(result.Response.Status != "ok", "writer contention cannot report a completed cleanup");
        Require(f.AccountHash == before, "contended cleanup preserves the original account snapshot");
        f.Kept("Images/fleet-SYNTH-logo-012345abcdef.png", "synthetic managed image");
    }

    internal static async Task ProtectedDirectoryJunctionIsRejectedBeforeDeletion()
    {
        using var f = new Fixture(initialize: false);
        using var outside = new Fixture();
        outside.Write("organizations.bin", "synthetic external protected source");
        f.Write("Images/fleet-SYNTH-logo-012345abcdef.png", "synthetic managed image");
        var link = Path.Combine(f.Root, "offline-account-v1");
        CacheFixtureJunction.Create(f.Root, link, outside.Root);
        try
        {
            using var support = new ApplicationSupportBridgeDispatcher(f.Root, null);
            var result = await support.DispatchAsync(BridgeEnvelope.Request("diagnostics.clearImageCache",
                Guid.NewGuid().ToString("N"), 0, new { schemaVersion = 1 }));
            Require(result.Response.Status != "ok", "protected cache junction cannot confirm maintenance");
            f.Kept("Images/fleet-SYNTH-logo-012345abcdef.png", "synthetic managed image");
            outside.Kept("organizations.bin", "synthetic external protected source");
        }
        finally { CacheFixtureJunction.Remove(f.Root, link); }
    }

    private sealed class DirectoryHttp : HttpMessageHandler
    {
        internal int Calls;
        internal TaskCompletionSource<bool>? Gate;
        internal TaskCompletionSource<bool> Entered = new(TaskCreationOptions.RunContinuationsAsynchronously);
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Require(request.Method == HttpMethod.Get && request.RequestUri!.AbsolutePath == "/api/fleets/directory" &&
                request.Headers.Authorization?.Parameter == "synthetic-access", "fixed synthetic GET-only fixture");
            Calls++; Entered.TrySetResult(true);
            var gate = Gate; if (gate is not null) await gate.Task.WaitAsync(token);
            return new(HttpStatusCode.OK) { Content = JsonContent.Create(new { schemaVersion = 1, membershipModelVersion = 2,
                view = "mine", query = "", next = (string?)null, items = new[] { new { code = "SYNTH", name = "Synthetic Organization",
                    description = "", language = "", activeTime = "", memberCount = 1, relationship = "member", joinMode = "direct",
                    actions = new[] { "leave" }, logoImageData = Image } } }) };
        }
    }

    private static void Require(bool condition, string message)
    { if (!condition) throw new InvalidOperationException(message); }

    private sealed class Fixture : IDisposable
    {
        internal string Root { get; } = Path.GetFullPath(Path.Combine(Path.GetTempPath(),
            "StarBridge-organization-image-maintenance-" + Guid.NewGuid().ToString("N")));
        internal BridgeAccountContext Owner { get; } = new("synthetic", "https://issuer.example.test", "synthetic-owner");
        internal OfflineAccountStore Store { get; }
        internal string AccountHash => Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(Path.Combine(Root, "offline-account-v1", "snapshot.bin"))));
        internal Fixture(bool initialize = true)
        {
            Directory.CreateDirectory(Root); Store = new(Root);
            if (initialize) Store.Observe(Owner, "Synthetic Pilot", () => true);
        }
        internal void Seed(string? image) => Store.ObserveOrganizations(Owner, 1, null, null,
            [new("SYNTH", "Synthetic Organization", image, image is null)], () => true);
        internal async Task<int> Clear(Action? clearReadCaches = null)
        {
            using var support = new ApplicationSupportBridgeDispatcher(Root, null, clearImageReadCaches: clearReadCaches);
            var result = await support.DispatchAsync(BridgeEnvelope.Request("diagnostics.clearImageCache",
                Guid.NewGuid().ToString("N"), 0, new { schemaVersion = 1 }));
            Require(result.Response.Status == "ok", "original diagnostics route confirms successful maintenance");
            return result.Response.Payload.GetProperty("count").GetInt32();
        }
        internal void Write(string relative, string value)
        {
            var path = Path.GetFullPath(Path.Combine(Root, relative));
            if (!path.StartsWith(Root + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase)) throw new InvalidOperationException();
            Directory.CreateDirectory(Path.GetDirectoryName(path)!); File.WriteAllText(path, value);
        }
        internal void Kept(string relative, string value) => Require(File.ReadAllText(Path.Combine(Root, relative)) == value, "excluded source stays unchanged");
        public void Dispose()
        {
            var parent = Path.TrimEndingDirectorySeparator(Path.GetFullPath(Path.GetTempPath()));
            const string prefix = "StarBridge-organization-image-maintenance-";
            var name = Path.GetFileName(Root);
            if (!string.Equals(Path.GetDirectoryName(Root), parent, StringComparison.OrdinalIgnoreCase) ||
                !name.StartsWith(prefix, StringComparison.Ordinal) || !Guid.TryParseExact(name[prefix.Length..], "N", out _)) throw new InvalidOperationException();
            Directory.Delete(Root, true);
        }
    }
}
