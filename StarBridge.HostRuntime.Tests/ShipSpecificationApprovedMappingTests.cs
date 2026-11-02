using System.Net;
using System.Text.Json;
using StarBridge.Core.Ships;
using StarBridge.HostRuntime.Ships;

internal static class ShipSpecificationApprovedMappingTests
{
    internal static async Task Run()
    {
        var transport = new Source();
        using var reader = new ScmShipSpecificationReader(new("https://catalog.invalid/"), transport);
        foreach (var (model, sourceId) in new (string, long)[] {
            ("F7A", 54918), ("F7A Hornet Mk I", 54918), ("ANVL_Hornet_F7A", 54918),
            ("F7A Mk II", 54935), ("Aurora Mk I SE", 57369), ("Aurora Mk I CL", 54928),
            ("Aurora Mk I ES", 54790), ("Aurora Mk I LN", 54709), ("Aurora Mk I LX", 54691),
            ("Aurora Mk I MR", 54927), ("Tyilui", 57645), ("Railen", 57644),
            ("Argo Mole Carbon Edition", 54776), ("Argo Mole Talus Edition", 54776),
            ("Valkyrie Liberator Edition", 54775), ("Mustang Alpha Vindicator", 54933),
            ("Blade", 54873), ("ESPR_Blade", 54873), ("Glaive", 54841), ("ESPR_Glaive", 54841),
            ("Stinger", 54764), ("ESPR_Stinger", 54764),
            ("Carrack w/C8X", 54732), ("Carrack Expedition w/C8X", 54801),
            ("Skylark", 58243), ("RSI Skylark", 58243), ("S-65 Stingray", 57909)
        })
        {
            var result = await reader.ReadAsync(model, false, default);
            Check(result.State == "ready" && result.Groups!.SelectMany(g => g.Fields).Any(f => f.Key == "mass" && f.Value == sourceId.ToString()),
                $"Approved model {model} resolves exact source {sourceId}");
        }
        var explorer = await reader.ReadAsync("600i Explorer", false, default);
        var touring = await reader.ReadAsync("600i Touring", false, default);
        Check(Cargo(explorer) == "44" && Cargo(touring) == "20", "600i Explorer and Touring retain separate actual parameter records");
        var conflictingNames = ShipNameIndex.Parse("""
            {"schemaVersion":1,"entries":[{"runtimeId":"ORIG_600i_Touring","englishName":"600i Touring","chineseName":"旅行版","aliases":["600i Explorer"]}]}
            """);
        using var conflicting = new ScmShipSpecificationReader(new("https://catalog.invalid/"), new Source(), names: conflictingNames);
        Check(Cargo(await conflicting.ReadAsync("600i Explorer", false, default)) == "44" &&
            Cargo(await conflicting.ReadAsync("600i Touring", false, default)) == "20",
            "explicit module selection wins over a conflicting old alias and remains isolated in cache");
        Check((await reader.ReadAsync("Argo Mole Carbon Edition", false, default)).PaintBaseModel == "MOLE",
            "cosmetic parameter origin remains explicit on a cache hit");
        Check(StarBridge.NativeBridge.BridgePayload.From(await reader.ReadAsync("Argo Mole Carbon Edition", false, default))
            .GetProperty("paintBaseModel").GetString() == "MOLE", "wire preserves cosmetic parameter provenance");
        Check((await reader.ReadAsync("MOLE", false, default)).PaintBaseModel is null,
            "cosmetic annotation cannot leak into the base model");
        using var wrongModule = new ScmShipSpecificationReader(new("https://catalog.invalid/"), new Source { WrongExplorerRole = true });
        try { await wrongModule.ReadAsync("600i Explorer", false, default); throw new Exception("Explorer accepted Touring role"); }
        catch (HttpRequestException) { }
        using var missingExplorer = new ScmShipSpecificationReader(new("https://catalog.invalid/"), new Source { MissingExplorer = true });
        Check((await missingExplorer.ReadAsync("600i Explorer", false, default)).State == "notFound",
            "missing Explorer never substitutes the available Touring model");
        Check((await reader.ReadAsync("MOLE unverified special", false, default)).State == "notFound", "unlisted special editions never inherit base parameters");
        var bundle = await reader.ReadAsync("Carrack w/C8X", false, default);
        var expeditionBundle = await reader.ReadAsync("Carrack Expedition w/C8X", false, default);
        Check(bundle.BundleBaseModel == "Carrack" && expeditionBundle.BundleBaseModel == "Carrack Expedition" &&
            bundle.ModelName == "Carrack w/C8X" && expeditionBundle.ModelName == "Carrack Expedition w/C8X",
            "each bundle retains its identity and names its own carrier parameter source");
        Check(StarBridge.NativeBridge.BridgePayload.From(bundle).GetProperty("bundleBaseModel").GetString() == "Carrack" &&
            (await reader.ReadAsync("Carrack", false, default)).BundleBaseModel is null,
            "bundle provenance crosses wire without leaking through carrier cache");
        foreach (var model in new[] { "Blade", "Glaive", "Stinger" })
        {
            using var wrongReplica = new ScmShipSpecificationReader(new("https://catalog.invalid/"), new Source { WrongReplicaName = true });
            try { await wrongReplica.ReadAsync(model, false, default); throw new Exception("Replica accepted unverified original identity"); }
            catch (HttpRequestException) { }
        }
        var exactNames = ShipNameIndex.Parse("""
            {"schemaVersion":1,"entries":[
              {"runtimeId":"RSI_Skylark_Display","englishName":"RSI Skylark","chineseName":"云雀展示","aliases":[]},
              {"runtimeId":"KRIG_S65_Stingray_BALLISTIC","englishName":"Kruger S-65 Stingray","chineseName":"弹道黄貂鱼","aliases":[]}]}
            """);
        using var variants = new ScmShipSpecificationReader(new("https://catalog.invalid/"), new Source(), names: exactNames);
        foreach (var (runtime, id) in new[] { ("RSI_Skylark_Display", 58244), ("KRIG_S65_Stingray_BALLISTIC", 57910) })
        {
            var variant = await variants.ReadAsync(runtime, false, default);
            Check(variant.State != "ready" || variant.Groups!.SelectMany(g => g.Fields).Any(f => f.Key == "mass" && f.Value == id.ToString()),
                "explicit variant never collapses into a normal/default selection: " + runtime);
        }
        Console.WriteLine("PASS approved names, F7A, cosmetic editions, 600i modules, verified replicas, bundles and default variants");
    }

    private static string? Cargo(ShipSpecifications value) => value.Groups?.SelectMany(g => g.Fields).SingleOrDefault(f => f.Key == "cargo")?.Value;
    internal static async Task Live()
    {
        using var reader = new ScmShipSpecificationReader(new("https://scmk.flowcld.com/"));
        foreach (var model in new[] { "F7A", "F7A Mk II", "Aurora Mk I SE", "Aurora Mk I CL", "Aurora Mk I ES",
            "Aurora Mk I LN", "Aurora Mk I LX", "Aurora Mk I MR", "Tyilui", "Railen", "Argo Mole Carbon Edition",
            "Argo Mole Talus Edition", "Valkyrie Liberator Edition", "Mustang Alpha Vindicator", "Blade", "Glaive", "Stinger",
            "Carrack w/C8X", "Carrack Expedition w/C8X", "Skylark", "S-65 Stingray" })
        {
            var result = await reader.ReadAsync(model, false, default);
            Check(result.State == "ready" && result.Groups?.Count > 0, "Live approved model resolves: " + model);
            Console.WriteLine($"APPROVED LIVE {model}: {result.State}, data={result.DataVersion}, paintBase={result.PaintBaseModel ?? "none"}");
        }
        var explorer = await reader.ReadAsync("600i Explorer", false, default);
        var touring = await reader.ReadAsync("600i Touring", false, default);
        Check(Cargo(explorer) == "44" && Cargo(touring) == "20", "Live 600i modules remain separate");
        Console.WriteLine($"APPROVED LIVE 600i Explorer={Cargo(explorer)} SCU; Touring={Cargo(touring)} SCU");
    }
    private static void Check(bool value, string message) { if (!value) throw new Exception(message); }

    private sealed record Item(long Id, string Name, string Runtime, int Cargo = 0, string Role = "fixture");
    private sealed class Source : HttpMessageHandler
    {
        internal bool WrongExplorerRole, MissingExplorer, WrongReplicaName;
        private readonly Item[] _items = [
            new(54918, "Anvil F7A Hornet Mk I", "ANVL_Hornet_F7A_Mk1"),
            new(54935, "Anvil F7A Hornet Mk II", "ANVL_Hornet_F7A_Mk2"),
            new(57369, "RSI Aurora Mk I SE", "RSI_Aurora_GS_SE"),
            new(54928, "RSI Aurora CL", "RSI_Aurora_GS_CL"), new(54790, "RSI Aurora ES", "RSI_Aurora_GS_ES"),
            new(54709, "RSI Aurora LN", "RSI_Aurora_GS_LN"), new(54691, "RSI Aurora Mk I LX", "RSI_Aurora_GS_LX"),
            new(54927, "RSI Aurora MR", "RSI_Aurora_GS_MR"), new(57645, "Gatac Tyilui", "GAMA_Tyilui"),
            new(57644, "Gatac Railen", "GAMA_Railen"), new(54776, "Argo MOLE", "ARGO_MOLE"),
            new(54775, "Anvil Valkyrie", "ANVL_Valkyrie"), new(54933, "Mustang Alpha", "CNOU_Mustang_Alpha"),
            new(54812, "Origin 600i", "ORIG_600i", 44, "Expedition"),
            new(54882, "Origin 600i Touring", "ORIG_600i_Touring", 20, "Luxury Touring"),
            new(54873, "Esperia Blade", "VNCL_Blade"), new(54841, "Vanduul Glaive", "VNCL_Glaive"),
            new(54764, "Vanduul Stinger", "VNCL_Stinger"),
            new(54732, "Anvil Carrack", "ANVL_Carrack", 456), new(54745, "Anvil Carrack", "ANVL_Carrack_BIS2950", 456),
            new(54801, "Anvil Carrack Expedition", "ANVL_Carrack_Expedition", 456),
            new(58244, "RSI Skylark", "RSI_Skylark_Display"), new(58243, "RSI Skylark", "RSI_Skylark"),
            new(57910, "Kruger S-65 Stingray", "KRIG_S65_Stingray_BALLISTIC"), new(57909, "Kruger S-65 Stingray", "KRIG_S65_Stingray")
        ];
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            var uri = request.RequestUri!;
            var items = _items.Where(i => !MissingExplorer || i.Id != 54812).ToArray();
            object data;
            if (uri.AbsolutePath.EndsWith("search-list")) data = new { total = items.Length, list = items.Select(i => new { id = i.Id, itemNameEn = i.Name }) };
            else if (uri.AbsolutePath.EndsWith("warehouse-profiles")) data = items.Select(i => new { id = i.Id, itemNameEn = i.Name, keyWord = i.Runtime }).ToArray();
            else
            {
                var id = long.Parse(uri.Query.Split("id=")[1]);
                var item = _items.Single(i => i.Id == id);
                data = new { id, itemType = 1, itemNameEn = item.Name, keyWord = item.Runtime,
                    extendedAttrs = new { mass = id, cargo = item.Cargo,
                        originalName = item.Runtime.StartsWith("VNCL_") && !WrongReplicaName ? "Esperia " + item.Runtime[5..] : item.Name.Replace("Esperia", "Vanduul"),
                        role = id == 54812 && WrongExplorerRole ? "Luxury Touring" : item.Role, career = "Exploration" } };
            }
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent(JsonSerializer.Serialize(new { code = 0, data })) });
        }
    }
}
