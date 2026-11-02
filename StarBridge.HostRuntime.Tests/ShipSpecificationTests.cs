using System.Net;
using System.Text.Json;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Hangar;
using StarBridge.HostRuntime.Ships;
using StarBridge.NativeBridge;
using StarBridge.Core.Profiles;

internal static class ShipSpecificationTests
{
    internal static async Task Run()
    {
        var clock = new Clock();
        var transport = new Handler();
        using var reader = new ScmShipSpecificationReader(new("https://catalog.invalid/"), transport, clock);
        var results = await Task.WhenAll(reader.ReadAsync("Anvil Carrack", false, default),
            reader.ReadAsync("ANVL_Carrack", false, default));
        Check(results.All(r => r.State == "ready" && r.DataVersion == "test-version"), "runtime identifier selects base edition");
        Check(transport.Requests == 3, "aliases and repeated instances share bounded model cache");
        Check(results[0].Groups!.Single(g => g.Key == "overview").Fields.Any(f => f.Key == "cargo" && f.Value == "0"), "zero remains real data");
        Check(results[0].Groups!.SelectMany(g => g.Fields).All(f => f.Key != "crew"), "missing is not zero");
        Check(results[0].Components!.Any(c => c.Name == "Fixture cannon" && c.Group == "weapons"), "nested turret weapons preserved");
        var wire = BridgePayload.From(results[0]).GetRawText();
        Check(!wire.Contains("thumbnail") && !wire.Contains("https://"), "no SCM media or account material in projection");
        clock.Now += TimeSpan.FromHours(7);
        transport.Fail = true;
        var stale = await reader.ReadAsync("Carrack", false, default);
        Check(stale.Stale && stale.FetchedAt == results[0].FetchedAt, "bounded stale data explicitly labelled on failure");
        using var cancelled = new CancellationTokenSource(); cancelled.Cancel();
        await Expect<OperationCanceledException>(() => reader.ReadAsync("Carrack", false, cancelled.Token));
        clock.Now += TimeSpan.FromDays(2);
        await Expect<HttpRequestException>(() => reader.ReadAsync("Carrack", false, default));
        transport.Fail = false;
        Check((await reader.ReadAsync("Carrack unknown edition", false, default)).State == "notFound", "unknown variants do no fuzzy lookup");

        using var ambiguous = new ScmShipSpecificationReader(new("https://catalog.invalid/"), new Handler { DuplicateBase = true });
        Check((await ambiguous.ReadAsync("Carrack", false, default)).State == "ambiguous", "duplicate exact runtime identities fail closed");
        using var punctuation = new ScmShipSpecificationReader(new("https://catalog.invalid/"), new IdrisHandler());
        var idris = await punctuation.ReadAsync("伊德里斯-P", false, default);
        Check(idris.State == "ready" && idris.Groups!.SelectMany(g => g.Fields).Any(f => f.Key == "cargo" && f.Value == "995"),
            "Idris P must resolve despite server substring punctuation and a same-name TSG variant");
        await CatalogueBoundaries();
        await ShipSpecificationApprovedMappingTests.Run();
        const string clientCatalog = "英文飞船名\t中文飞船名\t制造商\nF7C Hornet Mk II\t铁砧 F7C 大黄蜂 Mk II\tAnvil Aerospace";
        using var pack = typeof(StarBridge.Core.Ships.ShipNameIndex).Assembly.GetManifestResourceStream("StarBridge.ShipNamePack.json")!;
        using var packReader = new StreamReader(pack);
        using var displayNames = new ScmShipSpecificationReader(new("https://catalog.invalid/"),
            new CatalogueHandler { ModelKeyword = "ANVL_Hornet_F7C_Mk2" }, names:
            StarBridge.Core.Ships.ShipNameIndex.Parse(packReader.ReadToEnd(), clientCatalog));
        Check((await displayNames.ReadAsync("F7C Hornet Mk II", false, default)).State == "ready",
            "actual client catalogue English title reuses its exact Chinese/runtime join");
        using var replicaPack = typeof(StarBridge.Core.Ships.ShipNameIndex).Assembly.GetManifestResourceStream("StarBridge.ShipNamePack.json")!;
        using var replicaPackReader = new StreamReader(replicaPack);
        using var replica = new ScmShipSpecificationReader(new("https://catalog.invalid/"),
            new CatalogueHandler { ModelKeyword = "VNCL_Stinger", ModelName = "Vanduul Stinger" }, names:
            StarBridge.Core.Ships.ShipNameIndex.Parse(replicaPackReader.ReadToEnd(),
                "英文飞船名\t中文飞船名\t制造商\nStinger\t埃斯佩里亚 毒刺\tEsperia"));
        await Expect<HttpRequestException>(() => replica.ReadAsync("Stinger", false, default));
        using var malformed = new ScmShipSpecificationReader(new("https://catalog.invalid/"), new Handler { Malformed = true });
        await Expect<HttpRequestException>(() => malformed.ReadAsync("Carrack", false, default));
        await BridgeBoundary();
        Console.WriteLine("PASS SCM specifications: exact edition, cache/coalescing, missing/zero, nested components, stale/cancel, account boundary");
    }

    internal static async Task Live()
    {
        using var reader = new ScmShipSpecificationReader(new("https://scmk.flowcld.com/"));
        foreach (var model in new[] { "ANVL_Carrack", "ANVL_Arrow", "伊德里斯-P", "AEGS_Idris_M",
            "RSI_Constellation_Taurus", "ANVL_Hornet_F7C_Mk2", "CRUS_C1_Spirit", "ORIG_600i",
            "CRUS_A1_Spirit", "ANVL_C8R_Pisces_Rescue", "ARGO_MPUV_Tractor", "ORIG_600i_2951_BIS", "ARGO_ATLS_IKTI_Rad" })
        {
            var result = await reader.ReadAsync(model, false, default);
            Check(result.State == "ready" && result.Groups?.Count > 0, "public live model resolves: " + model);
            Console.WriteLine($"LIVE {model}: {result.State}, data={result.DataVersion}, groups={result.Groups!.Count}, components={result.Components!.Count}");
        }
        var unknown = await reader.ReadAsync("RSI Skylark", false, default);
        Check(unknown.State == "ready", "approved Skylark selects normal variant");
        Console.WriteLine("LIVE RSI Skylark: approved normal variant ready");
    }

    internal static void Audit(string path)
    {
        using var document = JsonDocument.Parse(File.ReadAllText(path));
        var rows = document.RootElement.EnumerateArray().ToArray();
        var recognized = rows.Select(row => (Row: row, Name: StarBridge.Core.Ships.ShipNameIndex.Bundled.Find(row.GetProperty("keyWord").GetString())))
            .Where(x => x.Name?.RuntimeId is not null).ToArray();
        var oldSearch = recognized.Count(x => x.Row.GetProperty("itemNameEn").GetString()!.Contains(x.Name!.EnglishName, StringComparison.OrdinalIgnoreCase));
        Console.WriteLine($"AUDIT public vehicle records={rows.Length}, established runtime identities={recognized.Length}, old substring reachable={oldSearch}");
        foreach (var item in recognized.Where(x => !x.Row.GetProperty("itemNameEn").GetString()!.Contains(x.Name!.EnglishName, StringComparison.OrdinalIgnoreCase)).Take(12))
            Console.WriteLine($"SEARCH MISS {item.Name!.EnglishName} -> {item.Row.GetProperty("itemNameEn").GetString()}");
        foreach (var row in rows.Where(row => StarBridge.Core.Ships.ShipNameIndex.Bundled.Find(row.GetProperty("keyWord").GetString()) is null))
        {
            var name = StarBridge.Core.Ships.ShipNameIndex.Bundled.Find(row.GetProperty("itemNameEn").GetString());
            if (name?.RuntimeId is not null) Console.WriteLine($"IDENTITY REVIEW {row.GetProperty("keyWord").GetString()} -> {name.RuntimeId} ({row.GetProperty("itemNameEn").GetString()})");
        }
    }

    private static async Task CatalogueBoundaries()
    {
        var paged = new CatalogueHandler();
        using var reader = new ScmShipSpecificationReader(new("https://catalog.invalid/"), paged);
        Check((await reader.ReadAsync("伊德里斯-P", false, default)).State == "ready", "second-page model resolves by keyword even when display label changes");
        using var reordered = new ScmShipSpecificationReader(new("https://catalog.invalid/"),
            new CatalogueHandler { ModelKeyword = "CRUS_Spirit_C1" });
        Check((await reordered.ReadAsync("CRUS_C1_Spirit", false, default)).State == "ready", "verified SCM runtime rename resolves C1 without a display-name guess");
        var requests = paged.Requests;
        Check((await reader.ReadAsync("ANVL_Arrow", false, default)).State == "notFound" && paged.Requests == requests,
            "different models reuse the complete identity catalogue without bulk detail reads");
        await reader.ReadAsync("伊德里斯-P", true, default);
        Check(paged.Requests == requests * 2, "explicit refresh also refreshes identity catalogue");
        foreach (var bad in new[] { new CatalogueHandler { DuplicatePage = true },
            new CatalogueHandler { MissingProfile = true }, new CatalogueHandler { WrongDetail = true } })
        {
            using var invalid = new ScmShipSpecificationReader(new("https://catalog.invalid/"), bad);
            await Expect<HttpRequestException>(() => invalid.ReadAsync("伊德里斯-P", false, default));
        }
    }

    private sealed class CatalogueHandler : HttpMessageHandler
    {
        internal int Requests;
        internal bool DuplicatePage, MissingProfile, WrongDetail;
        internal string ModelKeyword = "AEGS_Idris_P";
        internal string? ModelName;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Requests++;
            var uri = request.RequestUri!;
            Check(!uri.Query.Contains("keyword="), "identity catalogue is not a substring search");
            object data;
            if (uri.AbsolutePath.EndsWith("search-list"))
            {
                var ids = uri.Query.Contains("pageNo=1&") ? Enumerable.Range(1, 100) : new[] { DuplicatePage ? 1 : 101 };
                data = new { total = 101, list = ids.Select(id => new { id, itemNameEn = "Vehicle " + id }).ToArray() };
            }
            else if (uri.AbsolutePath.EndsWith("warehouse-profiles"))
            {
                var ids = uri.Query.Split("ids=")[1].Split(',').Select(int.Parse);
                data = ids.Where(id => !MissingProfile || id != 101).Select(id => new {
                    id, itemNameEn = id == 101 && ModelName is not null ? ModelName : "Renamed vehicle " + id, keyWord = id == 101 ? ModelKeyword : "UNKNOWN_" + id
                }).ToArray();
            }
            else
            {
                Check(uri.Query.Contains("id=101"), "only selected model detail is requested");
                data = new { id = 101, itemType = 1, itemNameEn = ModelName ?? "Another display label",
                    keyWord = WrongDetail ? "AEGS_Idris_P_TSG" : ModelKeyword, extendedAttrs = new { cargo = 995 } };
            }
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) {
                Content = new StringContent(JsonSerializer.Serialize(new { code = 0, data })) });
        }
    }

    private static async Task BridgeBoundary()
    {
        var host = new Host();
        var transport = new Handler();
        using var runtime = new AccountBridgeRuntime(host, shipSpecifications:
            new ScmShipSpecificationReader(new("https://catalog.invalid/"), transport));
        using var composed = new CompositeBridgeDispatcher(new RejectDispatcher(), runtime, new RejectDispatcher());
        BridgeEnvelope Request(object body, long generation = 7) => BridgeEnvelope.Request(
            "ships.specifications", Guid.NewGuid().ToString("N"), generation, body, host.CurrentContext);
        var result = await composed.DispatchAsync(Request(new { schemaVersion = 1, model = "Carrack" }));
        Check(result.Response.Status == BridgeResponseStatuses.Ok && result.Response.Payload.GetProperty("specifications").GetProperty("state").GetString() == "ready", "real runtime route projected");
        var before = transport.Requests;
        Check((await composed.DispatchAsync(Request(new { schemaVersion = 1, model = "Carrack", url = "https://untrusted.invalid" }))).Response.Error?.Code == "ships.invalid_request", "no caller URLs");
        Check((await composed.DispatchAsync(Request(new { schemaVersion = 1, model = "Carrack" }, 6))).Response.Error?.Code == "hangar.account_changed", "generation bound");
        Check(before == transport.Requests, "invalid requests do no IO");
        var unrelated = await composed.DispatchAsync(BridgeEnvelope.Request("ships.update", Guid.NewGuid().ToString("N"), 7,
            new { schemaVersion = 1 }, host.CurrentContext));
        Check(unrelated.Response.Error?.Code == BridgeErrorCodes.CapabilityUnavailable && transport.Requests == before,
            "specification route does not enable neighboring ship writes");
        transport.BeforeReply = host.Switch;
        var changed = await composed.DispatchAsync(Request(new { schemaVersion = 1, model = "Carrack", refresh = true }));
        Check(changed.Response.Error?.Code == "hangar.account_changed", "late response cannot cross account transition");
    }

    private sealed class RejectDispatcher : IBridgeRequestDispatcher
    {
        public event Action<BridgeEnvelope>? EventReady { add { } remove { } }
        public ValueTask<BridgeDispatchBatch> DispatchAsync(BridgeEnvelope request, CancellationToken token = default) =>
            throw new Exception("Model specifications cannot become host/device or preference operations.");
        public void Dispose() { }
    }

    private sealed class Clock : TimeProvider
    {
        internal DateTimeOffset Now = new(2026, 10, 15, 12, 0, 0, TimeSpan.Zero);
        public override DateTimeOffset GetUtcNow() => Now;
    }
    private sealed class IdrisHandler : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            var uri = request.RequestUri!;
            var body = uri.AbsolutePath.EndsWith("search-list")
                ? (uri.Query.Contains("keyword=") ? "{\"code\":0,\"data\":{\"total\":0,\"list\":[]}}" : """
                    {"code":0,"data":{"total":2,"list":[{"id":54738,"itemNameEn":"Aegis Idris-P"},{"id":57615,"itemNameEn":"Aegis Idris-P"}]}}
                    """)
                : uri.AbsolutePath.EndsWith("warehouse-profiles") ? """
                    {"code":0,"data":[{"id":54738,"itemNameEn":"Aegis Idris-P","keyWord":"AEGS_Idris_P"},{"id":57615,"itemNameEn":"Aegis Idris-P","keyWord":"AEGS_Idris_P_TSG"}]}
                    """ : """
                    {"code":0,"data":{"id":54738,"itemType":1,"itemNameEn":"Aegis Idris-P","keyWord":"AEGS_Idris_P","extendedAttrs":{"cargo":995}}}
                    """;
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent(body) });
        }
    }
    private sealed class Handler : HttpMessageHandler
    {
        internal int Requests;
        internal bool Fail, DuplicateBase, Malformed;
        internal Action? BeforeReply;
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Interlocked.Increment(ref Requests);
            Check(request.Headers.Authorization is null && !request.Headers.Contains("Cookie"), "anonymous transport");
            Check(request.Method == HttpMethod.Get && request.RequestUri!.AbsolutePath.StartsWith("/app-api/product/items/"), "fixed public routes only");
            await Task.Delay(5, token);
            if (Fail) return new(HttpStatusCode.ServiceUnavailable);
            if (Malformed) return new(HttpStatusCode.OK) { Content = new StringContent("{\"code\":0,\"data\":{\"total\":null}}") };
            BeforeReply?.Invoke(); BeforeReply = null;
            var search = request.RequestUri!.AbsolutePath.EndsWith("search-list");
            if (search) return new(HttpStatusCode.OK) { Content = new StringContent("""
                {"code":0,"data":{"total":2,"list":[{"id":101,"itemNameEn":"Anvil Carrack"},{"id":102,"itemNameEn":"Anvil Carrack"}]}}
                """) };
            if (request.RequestUri.AbsolutePath.EndsWith("warehouse-profiles"))
                return new(HttpStatusCode.OK) { Content = new StringContent(JsonSerializer.Serialize(new {
                    code = 0, data = new[] {
                        new { id = 101, itemNameEn = "Anvil Carrack", keyWord = "ANVL_Carrack" },
                        new { id = 102, itemNameEn = "Anvil Carrack", keyWord = DuplicateBase ? "ANVL_Carrack" : "ANVL_Carrack_BIS2950" }
                    }
                })) };
            var keyword = request.RequestUri.Query.Contains("id=101") || DuplicateBase ? "ANVL_Carrack" : "ANVL_Carrack_BIS2950";
            var id = request.RequestUri.Query.Contains("id=101") ? 101 : 102;
            return new(HttpStatusCode.OK) { Content = new StringContent(JsonSerializer.Serialize(new {
                code = 0, data = new { id, itemType = 1, itemNameEn = "Anvil Carrack", keyWord = keyword,
                dataVersion = "test-version", thumbnailUrl = "https://untrusted.invalid/image.png",
                extendedAttrs = new { cargo = 0, crew = (int?)null, length = 10,
                    shield = new { hp = 6000 }, hardpoints = new { turrets = new[] { new {
                        equipped = "Fixture mount", size = 2, children = new[] { new {
                            equipped = "Fixture cannon", type = "WeaponGun.Gun", size = 2, editable = true
                        } }
                    } } } } }
            })) };
        }
    }
    private sealed class Host : IAccountBridgeHost
    {
        public long Generation { get; private set; } = 7;
        public BridgeAccountContext? CurrentContext => new("development", "synthetic-issuer", "subject-a");
        public HangarAccountIdentity? HangarIdentity => new(CurrentContext!, Generation,
            new(StarBridge.Core.Identity.ScmGameIdentityStatus.Verified, "Pilot_Alpha", "pilot_alpha"));
        public event Action<long>? AccountChanged;
        internal void Switch() { Generation++; AccountChanged?.Invoke(Generation); }
        private static Task<T> Unexpected<T>() => throw new Exception("Unexpected account operation.");
        public Task<AccountBridgeSessionProjection> GetCurrentAsync(CancellationToken t) => Unexpected<AccountBridgeSessionProjection>();
        public Task<AccountBridgeSessionProjection> LoginAsync(CancellationToken t) => Unexpected<AccountBridgeSessionProjection>();
        public Task CancelLoginAsync() => Task.CompletedTask;
        public Task LogoutAsync(BridgeAccountContext c, CancellationToken t) => Unexpected<bool>();
        public Task<AccountBridgeProfileProjection> GetProfileAsync(BridgeAccountContext c, CancellationToken t) => Unexpected<AccountBridgeProfileProjection>();
        public Task<PersonalProfileDocumentContract> GetPersonalProfileAsync(BridgeAccountContext c, CancellationToken t) => Unexpected<PersonalProfileDocumentContract>();
        public Task<PersonalProfileDocumentContract> UpdatePersonalProfileAsync(BridgeAccountContext c, PersonalProfilePresentationUpdateContract p, CancellationToken t) => Unexpected<PersonalProfileDocumentContract>();
        public Task<AccountBridgeOfficialFleetProjection> GetOfficialFleetAsync(BridgeAccountContext c, CancellationToken t) => Unexpected<AccountBridgeOfficialFleetProjection>();
        public Task<AccountBridgeCompatibilityProjection> GetCompatibilityStateAsync(BridgeAccountContext c, CancellationToken t) => Unexpected<AccountBridgeCompatibilityProjection>();
        public Task<AccountBridgeCompatibilityProjection> LinkLegacyAccountAsync(BridgeAccountContext c, AccountBridgeLegacyCredential? p, CancellationToken t) => Unexpected<AccountBridgeCompatibilityProjection>();
        public Task<AccountBridgeCompatibilityProjection> CreateCompatibilityIdentityAsync(BridgeAccountContext c, CancellationToken t) => Unexpected<AccountBridgeCompatibilityProjection>();
        public Task<AccountBridgeProfileProjection> PatchPreferencesAsync(BridgeAccountContext c, AccountBridgePreferencePatch p, CancellationToken t) => Unexpected<AccountBridgeProfileProjection>();
        public Task<bool> ClearProfileCacheAsync(BridgeAccountContext c, CancellationToken t) => Unexpected<bool>();
        public Task<AccountBridgeIdentityProjection> GetGameIdentityPolicyAsync(BridgeAccountContext c, CancellationToken t) => Unexpected<AccountBridgeIdentityProjection>();
    }
    private static void Check(bool condition, string message) { if (!condition) throw new Exception(message); }
    private static async Task Expect<T>(Func<Task> work) where T : Exception
    { try { await work(); } catch (T) { return; } throw new Exception("Expected " + typeof(T).Name); }
}
