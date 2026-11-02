using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Nodes;
using StarBridge.HostRuntime.Communities;
using StarBridge.HostRuntime.Hangar;
using StarBridge.NativeBridge;
using D = OfficialFleetDiagnosticFixture;

internal static class OfficialHangarShapeDiagnosticTests
{
    private const string Stage = "official-hangar-shape", ScopeName = "SENTINEL";
    private static readonly string Edit = new('a', 32), Scope = new('b', 32), Ship = new('c', 32), Other = new('d', 32);
    private static JsonObject Draft() => JsonSerializer.SerializeToNode(new {
        schemaVersion = 1, editRef = Edit, sourceRef = D.Source, state = "available", strategy = "notShared",
        inventoryState = "complete", canGrant = true, canPublish = true, canReduce = true, selectionKnown = true,
        selectedCount = 0, maximumSelected = 10000, selectedRefs = Array.Empty<string>(),
        scopes = new[] { new { scopeRef = Scope, name = ScopeName, isCurrent = true } }, scopeRef = Scope,
        page = new { schemaVersion = 1, editRef = Edit, offset = 0, totalOptions = 1, next = (int?)null,
            options = new[] { new { shipRef = Ship, name = D.Name, missing = false, grantable = true } } }
    })!.AsObject();
    private static JsonObject Page(JsonObject d) => d["page"]!.AsObject();
    private static JsonObject Option(JsonObject d) => Page(d)["options"]![0]!.AsObject();
    private static JsonObject ScopeRow(JsonObject d) => d["scopes"]![0]!.AsObject();
    private static void Images(JsonObject d)
    {
        d["imageFeatures"] = JsonSerializer.SerializeToNode(new { protocolVersion = 1, read = true, upload = true, report = true, reduce = true });
        d["imageCount"] = 1; d["canClearImages"] = true;
    }
    internal static IEnumerable<(string Name, Func<Task> Test)> Cases()
    {
        var index = 0;
        foreach (var (code, change) in Mutations())
            yield return ($"CX-HANGARSHAPE {++index} {code}", () => Classify(code, change));
        yield return ("CX-HANGARSHAPE draft-invalid", () => Observe(new[] { D.Name, D.Reference }, "draft-invalid"));
        yield return ("CX-HANGARSHAPE unclassified serialization failure", () => Observe(new ThrowingProjection(), "unclassified"));
        yield return ("CX-HANGARSHAPE unclassified decoding failure", DecodeFailure);
        yield return ("CX-HANGARSHAPE first failure order", () => Classify("state-invalid", d => { d["state"] = D.Token; Option(d)["name"] = ""; }));
        yield return ("CX-HANGARSHAPE throwing journal preserves same response", ThrowingJournal);
        yield return ("CX-HANGARSHAPE read and image draft return probes", ReadEntrypoints);
    }

    // Each predicate/alternative in the Flutter guards has a mutation, including
    // nested page validation, the optional terminal `next`, and image features.
    private static IEnumerable<(string Code, Action<JsonObject> Change)> Mutations()
    {
        yield return ("ok", _ => { });
        yield return ("ok", Images);
        yield return ("ok", FullPage);
        yield return ("ok", d => Page(d).Remove("next"));
        yield return ("ok", d => { Option(d)["name"] = null; Option(d)["missing"] = true; Option(d)["grantable"] = false; });
        yield return ("ok", d => { d["canGrant"] = false; d["canReduce"] = false; d["canPublish"] = false; d["scopeRef"] = null; d["sourceRef"] = null; });
        yield return ("ok", d => { d["strategy"] = null; d["selectionKnown"] = false; });
        yield return ("ok", d => { Option(d)["name"] = new string('x', 512); ScopeRow(d)["name"] = new string('x', 10); });
        yield return ("ok", d => Option(d)["name"] = "x\u0085y"); // Flutter checks ASCII controls only.
        yield return ("draft-fields-invalid", d => d["CXDIAG_BODY_SENTINEL"] = D.Token);
        yield return ("draft-fields-invalid", d => d.Remove("state"));
        yield return ("draft-fields-invalid", d => { Images(d); d.Remove("imageCount"); });
        yield return ("draft-fields-invalid", d => d["canClearImages"] = false);
        yield return ("schema-invalid", d => d["schemaVersion"] = 2);
        yield return ("edit-ref-invalid", d => d["editRef"] = D.Reference);
        yield return ("source-ref-invalid", d => d["sourceRef"] = D.Reference);
        yield return ("source-ref-invalid", d => { d["canGrant"] = false; d["canReduce"] = false; d["canPublish"] = false; d["sourceRef"] = ""; });
        yield return ("state-invalid", d => d["state"] = D.Name);
        yield return ("strategy-invalid", d => d["strategy"] = D.Name);
        yield return ("inventory-state-invalid", d => d["inventoryState"] = D.Name);
        yield return ("maximum-selected-invalid", d => d["maximumSelected"] = 9999);
        foreach (var value in new object[] { -1, 10001, 1.5, D.Name })
            yield return ("selected-count-invalid", d => d["selectedCount"] = JsonSerializer.SerializeToNode(value));
        yield return ("selected-refs-invalid", d => d["selectedRefs"] = D.Name);
        yield return ("selected-refs-invalid", d => d["selectedRefs"] = new JsonArray(D.Reference));
        yield return ("selected-refs-invalid", d => d["selectedRefs"] = JsonSerializer.SerializeToNode(Enumerable.Repeat(Ship, 10001)));
        yield return ("selected-refs-duplicate", d => d["selectedRefs"] = new JsonArray(Ship, Ship));
        yield return ("scopes-invalid", d => d["scopes"] = D.Name);
        yield return ("scopes-invalid", d => d["scopes"] = JsonSerializer.SerializeToNode(Enumerable.Range(0, 102).Select(_ => new { scopeRef = Scope, name = ScopeName, isCurrent = true })));
        yield return ("scope-ref-invalid", d => d["scopeRef"] = D.Reference);
        foreach (var key in new[] { "canGrant", "canPublish", "canReduce", "selectionKnown" })
            yield return ("flags-invalid", d => d[key] = D.Name);
        yield return ("image-features-invalid", d => { Images(d); d["imageFeatures"] = null; });
        yield return ("image-features-invalid", d => { Images(d); d["imageFeatures"]!["protocolVersion"] = 2; });
        yield return ("image-features-invalid", d => { Images(d); d["imageFeatures"]!["CXDIAG_BODY_SENTINEL"] = D.Name; });
        foreach (var key in new[] { "read", "upload", "report", "reduce" })
        {
            yield return ("image-features-invalid", d => { Images(d); d["imageFeatures"]![key] = D.Name; });
            yield return ("image-features-invalid", d => { Images(d); d["imageFeatures"]!.AsObject().Remove(key); });
        }
        foreach (var value in new object[] { -1, 10001, 1.5, D.Name })
            yield return ("image-count-invalid", d => { Images(d); d["imageCount"] = JsonSerializer.SerializeToNode(value); });
        yield return ("clear-images-invalid", d => { Images(d); d["canClearImages"] = D.Name; });
        yield return ("clear-images-invalid", d => { Images(d); d["canReduce"] = false; });
        yield return ("clear-images-invalid", d => { Images(d); d["imageFeatures"]!["reduce"] = false; });
        yield return ("clear-images-invalid", d => { Images(d); d["imageCount"] = 0; });
        yield return ("publish-without-complete", d => d["canGrant"] = false);
        yield return ("publish-without-complete", d => d["inventoryState"] = "partial");
        yield return ("scope-missing", d => d["scopeRef"] = null);
        yield return ("scope-missing", d => d["sourceRef"] = null);
        yield return ("scope-missing", d => d["sourceRef"] = "");
        yield return ("scope-missing", d => d["scopeRef"] = "");
        yield return ("scope-missing", d => { d["canGrant"] = false; d["canPublish"] = false; d["scopeRef"] = null; });
        yield return ("selected-count-mismatch", d => d["selectedCount"] = 1);
        yield return ("selection-unknown-with-refs", d => { d["selectionKnown"] = false; d["selectedRefs"] = new JsonArray(Ship); });
        yield return ("selected-without-pool", d => { d["selectedCount"] = 1; d["selectedRefs"] = new JsonArray(Ship); });
        yield return ("scope-row-invalid", d => d["scopes"]![0] = D.Name);
        yield return ("scope-fields-invalid", d => ScopeRow(d)["CXDIAG_BODY_SENTINEL"] = D.Name);
        yield return ("scope-fields-invalid", d => ScopeRow(d).Remove("name"));
        yield return ("scope-ref-invalid", d => ScopeRow(d)["scopeRef"] = D.Reference);
        yield return ("scope-ref-duplicate", d => d["scopes"]!.AsArray().Add(ScopeRow(d).DeepClone()));
        foreach (var name in new object?[] { null, "", "   ", new string('x', 11), "x\u0001", 7 })
            yield return ("scope-name-invalid", d => ScopeRow(d)["name"] = JsonSerializer.SerializeToNode(name));
        yield return ("scope-current-invalid", d => ScopeRow(d)["isCurrent"] = D.Name);
        yield return ("scope-not-found", d => d["scopeRef"] = Other);
        yield return ("page-invalid", d => d["page"] = D.Name);
        yield return ("page-fields-invalid", d => Page(d)["CXDIAG_BODY_SENTINEL"] = D.Name);
        yield return ("page-fields-invalid", d => Page(d).Remove("offset"));
        yield return ("schema-invalid", d => Page(d)["schemaVersion"] = 2);
        yield return ("edit-ref-invalid", d => Page(d)["editRef"] = D.Reference);
        foreach (var value in new object[] { -1, 1, 0.5, D.Name })
            yield return ("page-offset-invalid", d => Page(d)["offset"] = JsonSerializer.SerializeToNode(value));
        foreach (var value in new object[] { -1, 20001, 0.5, D.Name })
            yield return ("page-total-invalid", d => Page(d)["totalOptions"] = JsonSerializer.SerializeToNode(value));
        yield return ("page-total-invalid", d => Page(d)["offset"] = 100);
        yield return ("options-invalid", d => Page(d)["options"] = D.Name);
        yield return ("options-too-many", d => Page(d)["options"] = JsonSerializer.SerializeToNode(Enumerable.Repeat(Option(d), 101)));
        yield return ("page-count-mismatch", d => Page(d)["totalOptions"] = 2);
        yield return ("page-next-invalid", d => Page(d)["next"] = 1);
        yield return ("page-next-invalid", d => { FullPage(d); Page(d).Remove("next"); });
        yield return ("page-next-invalid", d => { FullPage(d); Page(d)["next"] = 99; });
        yield return ("page-next-invalid", d => { FullPage(d); Page(d)["next"] = JsonNode.Parse("100.0"); });
        yield return ("option-invalid", d => Page(d)["options"]![0] = D.Name);
        yield return ("option-fields-invalid", d => Option(d)["CXDIAG_BODY_SENTINEL"] = D.Name);
        yield return ("option-fields-invalid", d => Option(d).Remove("name"));
        yield return ("ship-ref-invalid", d => Option(d)["shipRef"] = D.Reference);
        yield return ("ship-ref-duplicate", d => { Page(d)["options"]!.AsArray().Add(Option(d).DeepClone()); Page(d)["totalOptions"] = 2; });
        yield return ("option-flags-invalid", d => Option(d)["missing"] = D.Name);
        yield return ("option-flags-invalid", d => Option(d)["grantable"] = D.Name);
        yield return ("option-flags-invalid", d => Option(d)["grantable"] = false);
        yield return ("option-flags-invalid", d => Option(d)["missing"] = true);
        foreach (var name in new string?[] { null, "", "   " })
            yield return ("blank-name", d => Option(d)["name"] = name);
        yield return ("name-invalid", d => Option(d)["name"] = 7);
        yield return ("name-too-long", d => Option(d)["name"] = D.Name + new string('x', 513));
        yield return ("name-control-char", d => Option(d)["name"] = D.Name + "\u0001");
        yield return ("name-control-char", d => Option(d)["name"] = D.Name + "\u007f");
        yield return ("page-edit-mismatch", d => Page(d)["editRef"] = Other);
        yield return ("page-offset-not-zero", d => { Page(d)["offset"] = 100; Page(d)["totalOptions"] = 100; Page(d)["options"] = new JsonArray(); });
    }
    private static void FullPage(JsonObject d)
    {
        Page(d)["totalOptions"] = 101; Page(d)["next"] = 100;
        Page(d)["options"] = JsonSerializer.SerializeToNode(Enumerable.Range(0, 100).Select(i => new {
            shipRef = i.ToString("x32"), name = D.Name, missing = false, grantable = true }));
    }
    private static Task Classify(string code, Action<JsonObject> change)
    {
        var d = Draft(); change(d);
        return Observe(JsonSerializer.SerializeToElement(d), code);
    }
    private static Task Observe(object response, string code)
    {
        using var f = new D();
        var original = response is JsonElement row ? row.GetRawText() : null;
        var returned = f.Client.ObserveOfficialHangarShape(response);
        D.Check(ReferenceEquals(returned, response), "Shape probe returns the identical response object");
        if (original is not null) D.Check(((JsonElement)returned).GetRawText() == original, "Probe leaves all wire fields untouched");
        var lines = f.Lines(Stage);
        D.Check(lines.Length == 1 && lines[0].Contains($" stage={Stage} code={code} status=none elapsedMs="), "First fixed shape classification: " + code);
        Private(lines);
        return Task.CompletedTask;
    }
    private static void Private(string[] lines)
    {
        D.Private(lines);
        foreach (var sentinel in new[] { ScopeName, Edit, Scope, Ship, Other })
            D.Check(lines.All(line => !line.Contains(sentinel, StringComparison.Ordinal)), "No generated ref or short scope label in journal");
    }
    private static Task DecodeFailure()
    {
        var raw = Draft().ToJsonString().Replace(D.Name, "\\uD800", StringComparison.Ordinal);
        using var json = JsonDocument.Parse(raw);
        return Observe(json.RootElement.Clone(), "unclassified");
    }
    private sealed class ThrowingProjection
    {
        public string Name => throw new InvalidOperationException(D.Name + D.Reference);
    }
    private static Task ThrowingJournal()
    {
        using var f = new D();
        f.Client.ReadDiagnostic = (_, _, _, _) => throw new IOException(D.Name + D.Reference);
        foreach (var bad in new[] { false, true })
        {
            var d = Draft(); if (bad) Option(d)["name"] = "";
            object response = JsonSerializer.SerializeToElement(d);
            D.Check(ReferenceEquals(f.Client.ObserveOfficialHangarShape(response), response), "Throwing journal preserves both valid and invalid responses");
        }
        return Task.CompletedTask;
    }
    private static async Task ReadEntrypoints()
    {
        foreach (var images in new[] { false, true })
        foreach (var blank in new[] { false, true })
        {
            using var f = new D();
            using var handler = new SharingHandler();
            using var client = new CommunityClient(new Uri("https://cxdiag.invalid/"), handler) { ReadDiagnostic = f.Journal.Record };
            var local = new LocalHangarSnapshot(1, DateTimeOffset.UtcNow, D.Reference, [
                new LocalHangarShip(D.Reference, D.Token, blank ? "" : D.Name, D.Token, D.Token, DateTimeOffset.UtcNow, null)]);
            Task<object> Read() => images
                ? client.ReadOfficialHangarImageDraftAsync(D.Token, D.Open, D.Reference, () => { }, () => local, default)
                : client.ReadOfficialHangarSharingAsync(D.Token, D.Open, D.Reference, () => { }, () => local, default);
            var raw = await Read();
            var result = BridgeEnvelope.Response(BridgeEnvelope.Request("officialFleet.readHangarSharing", "fixture", 1), raw).Payload;
            D.Check(result.GetProperty("page").GetProperty("options")[0].GetProperty("name").GetString() == (blank ? "" : D.Name), "Real projection is unchanged, including invalid names");
            var code = images ? blank ? "blank-name" : "ok" : "draft-fields-invalid";
            D.Check(images || !result.TryGetProperty("imageFeatures", out _) && result.TryGetProperty("imageCount", out _), "Probe matches the actual Bridge null-omitting conversion");
            D.Check(f.Lines(Stage).Single().Contains(" code=" + code + " "), "One probe for either read entrypoint");
            await Read();
            D.Check(f.Lines(Stage).Length == 2 && handler.Calls == 4, "Every open logs once and adds no requests");
            Private(f.Lines(Stage));
            client.ReadDiagnostic = (_, _, _, _) => throw new IOException(D.Token);
            var returned = JsonSerializer.SerializeToElement(await Read());
            D.Check(returned.GetProperty("page").GetProperty("options")[0].GetProperty("name").GetString() == (blank ? "" : D.Name), "A throwing journal preserves the actual read result");
        }
    }
    private sealed class SharingHandler : HttpMessageHandler
    {
        internal int Calls;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Calls++;
            var target = new { authorityNamespace = "https://cxdiag.invalid/", organizationId = 70007, sid = ScopeName,
                membershipEpoch = "scm-observed-membership-row-v1:7" };
            var revision = new string('e', 32);
            var features = new { protocolVersion = 1, read = true, upload = true, report = true, reduce = true };
            object value = request.RequestUri!.AbsolutePath.EndsWith("/intents", StringComparison.Ordinal)
                ? new { schemaVersion = 2, imageFeatures = features, intents = new { state = "available", totalCount = 1, offset = 0, limit = 20,
                    hasMore = false, items = new[] { new { target, revision, strategy = "notShared", selectedCount = 0, instanceRefs = Array.Empty<string>(), imageCount = 0 } } } }
                : new { schemaVersion = 2, imageFeatures = features, target, intentRevision = revision,
                    imageConsent = new { count = 0, grantRefs = Array.Empty<string>() }, sharing = new {
                        state = "available", version = new string('f', 64), strategy = "notShared", instanceRefs = Array.Empty<string>() } };
            // Plain readers negotiate only V1; image readers accept V2.
            if (!request.Headers.Contains("X-StarBridge-Official-Fleet-Hangar-Version"))
            {
                var row = JsonSerializer.SerializeToNode(value)!.AsObject(); row["schemaVersion"] = 1;
                value = row;
            }
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = JsonContent.Create(value) });
        }
    }
}
