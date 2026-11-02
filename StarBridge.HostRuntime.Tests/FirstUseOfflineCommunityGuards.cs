using System.Net;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text.Json;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Communities;
using StarBridge.NativeBridge;

internal static partial class FirstUseModeTests
{
    internal static Task OfflineCommunityGuards()
    {
        using var f = new LocalAccountStopTests.Fixture(sampling: true);
        var store = new OfflineAccountStore(f.Root);
        var otherReader = new OfflineAccountStore(f.Root);
        var owner = f.Host.CurrentContext!;
        store.Observe(owner, "Synthetic Pilot", () => true);
        OfflineOrganizationObservation Row(string code, string? logo = OfflineAvatar) => new(code, "Organization " + code, logo, logo is null);
        var other = owner with { Subject = owner.Subject.ToUpperInvariant() };
        store.ObserveOrganizations(owner, 1, null, "next", [Row("one")], () => true);
        var original = store.ReadSelectedOrganizations(owner, () => true)!;
        Require(!original.Complete && original.Items.Single().LogoImageData == OfflineAvatar, "First page retains actual bytes and partial status");
        Require(store.ReadSelectedOrganizations(other, () => true) is null && store.ReadSelectedOrganizations(owner, () => false) is null,
            "Opaque owner identity and current fence control presentation reads");
        store.ObserveOrganizations(other, 1, null, null, [Row("wrong")], () => true);
        store.ObserveOrganizations(owner, 1, null, null, [Row("retired")], () => false);
        store.ObserveOrganizations(owner, 2, "next", null, [Row("wrong-generation")], () => true);
        Require(store.ReadSelectedOrganizations(owner, () => true)!.Version == original.Version, "Wrong owner, retired writes and stale continuation cannot alter display");
        store.ObserveOrganizations(owner, 1, "next", null, [Row("two")], () => true);
        Require(otherReader.ReadSelectedOrganizations(owner, () => true) is { Complete: true, Items.Count: 2 }, "A second store sees completed continuation");
        store.ClearOrganizations(other, () => true);
        store.ClearOrganizations(owner, () => false);
        Require(otherReader.ReadSelectedOrganizations(owner, () => true)!.Items.Count == 2, "A different owner or retired clear cannot erase display");
        store.ClearOrganizations(owner, () => true);
        Require(otherReader.ReadSelectedOrganizations(owner, () => true) is null, "External same-owner clear invalidates parsed display memory");
        var large = new byte[300 * 1024];
        Convert.FromBase64String(OfflineAvatar[22..]).CopyTo(large, 0);
        var image = "data:image/png;base64," + Convert.ToBase64String(large);
        store.ObserveOrganizations(owner, 3, null, null, Enumerable.Range(0, 300).Select(i => Row("bounded-" + i, image)).ToArray(), () => true);
        var bounded = store.ReadSelectedOrganizations(owner, () => true)!;
        Require(bounded.Items.Count == 256 && !bounded.Complete && bounded.Items.All(row => row.Name.Length > 0) &&
            bounded.Items.Sum(row => row.LogoImageData?.Length ?? 0) <= 3 * 1024 * 1024 && bounded.Items.Any(row => row.LogoImageData is null),
            "Bound rows and aggregate media independently without erasing names or claiming complete coverage");
        var first = JsonSerializer.SerializeToElement(OfflineOrganizationProjection.Read(bounded, JsonSerializer.SerializeToElement(new { offset = 0 }), false), BridgeProtocol.JsonOptions);
        Require(first.GetProperty("items").GetArrayLength() == 20 && first.GetProperty("nextOffset").GetInt32() == 20,
            "Metadata frames are bounded independently of logo bytes");
        try { OfflineOrganizationProjection.Read(bounded, JsonSerializer.SerializeToElement(new { offset = 20 }), false); throw new Exception("Unversioned continuation accepted"); }
        catch (AccountBridgeHostException error) when (error.Code == "offlineAccount.invalid_request") { }
        store.ObserveOrganizations(owner, 3, null, null, new PrefixOnlyOrganizationObservations(), () => true);
        Require(store.ReadSelectedOrganizations(owner, () => true) is { Complete: false, Items.Count: 256 },
            "A large admitted directory normalizes only the retained prefix and keeps its partial marker");
        store.ObserveOrganizations(owner, 3, null, "last", Enumerable.Range(0, 257).Select(i => Row("truncated-" + i, null)).ToArray(), () => true);
        store.ObserveOrganizations(owner, 3, "last", null, [], () => true);
        Require(store.ReadSelectedOrganizations(owner, () => true) is { Complete: false, Items.Count: 256 },
            "An empty final page cannot erase an earlier truncation or claim a complete directory");
        var path = Path.Combine(f.Root, "offline-account-v1", "organizations.bin");
        var protectedName = store.ReadSelectedOrganizations(owner, () => true)!.Items[0].Name;
        Require(new FileInfo(path).Length <= 4 * 1024 * 1024 && !System.Text.Encoding.UTF8.GetString(File.ReadAllBytes(path)).Contains(protectedName, StringComparison.Ordinal),
            "Disk file is bounded and protected, never plain organization names");
        File.WriteAllBytes(path, [1, 2, 3]);
        try { otherReader.ReadSelectedOrganizations(owner, () => true); throw new Exception("Corrupt ciphertext accepted"); }
        catch (CryptographicException) { }
        store.ObserveOrganizations(owner, 4, null, null, [Row("healed")], () => true);
        Require(otherReader.ReadSelectedOrganizations(owner, () => true)!.Items.Single().Name == "Organization healed", "Fresh authenticated first page heals a corrupt display file");
        store.Pin(owner, 22, () => true);
        store.ObserveOrganizations(owner, 4, null, null, [Row("late-online")], () => true);
        Require(store.ReadOfflineOrganizations(22, () => true)!.Items.Single().Name == "Organization healed" &&
            store.ReadOfflineOrganizations(21, () => true) is null, "Offline pin defeats late online observations and wrong revisions");
        store.Observe(other, "Other Pilot", () => true);
        Require(store.ReadSelectedOrganizations(other, () => true) is null, "Account change never inherits another owner's organization display");
        return Task.CompletedTask;
    }

    internal static async Task OfflineCommunityDeferredLogo()
    {
        using var handler = new DeferredOrganizationHttp();
        using var client = new CommunityClient(new Uri("https://communities.invalid/"), handler);
        using var f = new LocalAccountStopTests.Fixture(sampling: true, communities: client);
        await RootMode(f);
        await using var native = new NativeAccountRuntimeBinding(f.Runtime);
        var owner = f.Host.CurrentContext!;
        await native.DispatchAsync(BridgeEnvelope.Request("account.getCurrent", Op(), f.Host.Generation, new { schemaVersion = 1 }));
        var directory = await native.DispatchAsync(BridgeEnvelope.Request("communities.read", Op(), f.Host.Generation,
            new { schemaVersion = 1, view = "mine", query = "" }, owner));
        Require(directory.Response.Status == "ok", "Actual deferred-logo directory read");
        var reference = directory.Response.Payload.GetProperty("items")[0].GetProperty("targetRef").GetString();
        var store = new OfflineAccountStore(f.Root);
        var first = store.ReadSelectedOrganizations(owner, () => true)!;
        Require(first.Items.Single().LogoImageData is null, "Names persist before optional media completes");
        async Task Read(int offset) {
            var response = await native.DispatchAsync(BridgeEnvelope.Request("communities.media", Op(), f.Host.Generation,
                new { schemaVersion = 1, targetRef = reference, kind = "logo", offset, version = offset == 0 ? null : handler.Version }, owner));
            Require(response.Response.Status == "ok", "Actual validated media chunk");
        }
        await Read(0);
        Require(store.ReadSelectedOrganizations(owner, () => true)!.Version == first.Version, "Partial image cannot update cache version or timestamp");
        await Read(192 * 1024);
        var completed = store.ReadSelectedOrganizations(owner, () => true)!;
        Require(completed.Items.Single().LogoImageData == handler.Image && completed.Items.Single().LogoCachedAtUtc is not null,
            "Complete, matching content persists original multi-chunk bytes");
        // Retain the old sharing image while a new version is incomplete or untrusted.
        store.ObserveOrganizationLogo(owner, "SYNTHETIC-ORG", null, () => true);
        handler.ChangeImage();
        var cleared = store.ReadSelectedOrganizations(owner, () => true)!;
        await Read(0);
        Require(store.ReadSelectedOrganizations(owner, () => true)!.Version == cleared.Version, "Partial new transfer cannot republish the previous sharing image");
        handler.WrongHash = true;
        await Read(192 * 1024);
        Require(store.ReadSelectedOrganizations(owner, () => true)!.Items.Single().LogoImageData is null, "Wrong content hash cannot enter protected display even if media transport accepts it");
    }

    private sealed class DeferredOrganizationHttp : HttpMessageHandler
    {
        private readonly byte[] _bytes = new byte[300 * 1024];
        internal bool WrongHash;
        internal string Version => Convert.ToHexString(SHA256.HashData(_bytes)).ToLowerInvariant();
        internal string Image => "data:image/png;base64," + Convert.ToBase64String(_bytes);
        internal DeferredOrganizationHttp() => Convert.FromBase64String(OfflineAvatar[22..]).CopyTo(_bytes, 0);
        internal void ChangeImage() => _bytes[^1]++;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            token.ThrowIfCancellationRequested();
            object body;
            if (request.RequestUri!.AbsolutePath == "/api/fleets/directory")
                body = new { schemaVersion = 1, membershipModelVersion = 2, view = "mine", query = "", next = (string?)null,
                    items = new[] { new { code = "SYNTHETIC-ORG", name = "Deferred organization", description = "", language = "", activeTime = "",
                        memberCount = 1, relationship = "member", joinMode = "direct", actions = Array.Empty<string>(), logoImageData = (string?)null } } };
            else {
                var offset = int.Parse(request.RequestUri.Query.TrimStart('?').Split('&').Single(pair => pair.StartsWith("offset="))[7..]);
                var count = Math.Min(192 * 1024, _bytes.Length - offset);
                body = new { schemaVersion = 1, kind = "logo", memberId = (string?)null, version = Version,
                    mimeType = "image/png", totalBytes = _bytes.Length, offset, next = offset + count < _bytes.Length ? (int?)(offset + count) : null,
                    data = Convert.ToBase64String(WrongHash ? new byte[count] : _bytes.AsSpan(offset, count).ToArray()) };
            }
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = JsonContent.Create(body) });
        }
    }

    private sealed class PrefixOnlyOrganizationObservations : IReadOnlyList<OfflineOrganizationObservation>
    {
        public int Count => 10000;
        public OfflineOrganizationObservation this[int index] => index < 256
            ? new("bounded-prefix-" + index, "Bounded prefix", null, false)
            : throw new InvalidOperationException("Display persistence enumerated beyond its retained row budget.");
        public IEnumerator<OfflineOrganizationObservation> GetEnumerator()
        { for (var i = 0; i < Count; i++) yield return this[i]; }
        System.Collections.IEnumerator System.Collections.IEnumerable.GetEnumerator() => GetEnumerator();
    }
}
