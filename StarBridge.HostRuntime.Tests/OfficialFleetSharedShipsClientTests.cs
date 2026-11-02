using System.Net;
using System.Text.Json;
using System.Text.Json.Nodes;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Communities;

internal static class OfficialFleetSharedShipsClientTests
{
    internal static async Task Run()
    {
        var mode = "ok";
        var offsets = new List<int>();
        var observedOwners = 0;
        using var handler = new Handler(request =>
        {
            Check(request.Headers.Authorization?.Parameter == "fixture", "only authorized Relay reads");
            if (request.RequestUri!.AbsolutePath == "/api/official-fleets/context") return Json(new {
                schemaVersion = 1, sourceRef = "officialFleet:7", fleetCode = "OFFICIALFLEET:7", name = "Synthetic fleet",
                announcementsAvailable = false, chatAvailable = false, canSend = false, readReceiptsAvailable = false,
                canManageAnnouncements = false, activityAvailable = false });
            Check(request.RequestUri.AbsolutePath == "/api/official-fleets/ships", "no community route fallback");
            var q = request.RequestUri.Query.TrimStart('?').Split('&').Select(v => v.Split('=', 2))
                .ToDictionary(p => WebUtility.UrlDecode(p[0]), p => WebUtility.UrlDecode(p[1]));
            Check(q["sourceRef"] == "officialFleet:7" && !q.ContainsKey("code") && q["q"] == "", "full-scope search retains typed source and no community code");
            var offset = int.Parse(q["offset"]); offsets.Add(offset);
            var row = JsonSerializer.SerializeToNode(new {
                schemaVersion = 1, sourceRef = "officialFleet:7", coverage = "completeAuthorizedProjection", queryVersion = 2,
                query = new { text = "", filter = "concept", sort = "name", descending = false, culture = "en-US" },
                revision = new string(mode == "changed" && offset > 0 ? 'b' : 'a', 64), offset,
                totalCount = 45, matchedCount = 45, next = offset < 40 ? (int?)(offset + 20) : null,
                identityValidUntilUtc = DateTimeOffset.UtcNow.AddSeconds(mode == "expired" ? -1 : 5),
                ownerLookups = new[] { new { memberRef = new string('c',64), memberId = 43, state = "visible", callsign = "Bridge Pilot", identityBinding = new string('d',64) } },
                ships = Enumerable.Range(offset, Math.Min(20,45-offset)).Select(i => new {
                    id = i.ToString("x64"), code = "source-"+i, displayName = "Source "+i,
                    ownerMemberId = new string('c',64), ownerGameName = "", ownerCallsign = "Bridge Pilot", ownerOnline = false,
                    ownerLiveStatus = "Unknown", ownerIsSelf = false, ownerHasAvatar = false, ownerAvatarVersion = (string?)null,
                    instanceId = (string?)null, sharedAt = (string?)null, hangarImportedAt = (string?)null,
                    catalogSpec = "large", catalogRole = "transport", catalogStatus = "Concept", catalogPriceUsd = (string?)null,
                    customImageMediaId = (string?)null, customImageCropFocusX = .5, customImageCropFocusY = .5, customImageCropZoom = 1.0,
                    privateAccount = "private-secret-never-search"
                }) })!;
            if (mode == "wrong-source") row["sourceRef"] = "officialFleet:8";
            if (mode == "partial") row["coverage"] = "requestedOwners";
            if (mode == "large") { row["totalCount"] = 10001; row["matchedCount"] = 10001; }
            if (mode == "no-deadline") row["identityValidUntilUtc"] = null;
            if (mode == "duplicate" && offset > 0) row["ships"]![0]!["id"] = new string('0',64);
            if (mode == "media") row["ships"]![0]!["customImageMediaId"] = "forbidden-media";
            return Json(row);
        });
        using var client = new CommunityClient(new Uri("https://relay.example.test/"), handler,
            shipLoaners: (code,_,_) => int.Parse(code[7..]) < 20 ? [] : [new { code="Replacement",displayName="Replacement",catalogSpec="capital",catalogRole="transport",catalogStatus="flyable" }]);
        var opened = J(await client.OpenOfficialFleetAsync("fixture", "officialFleet:7", "account-generation|officialFleet:7", () => {}, default));
        var reference = opened.GetProperty("targetRef").GetString();
        async Task<IReadOnlyDictionary<string, CommunityClient.OfficialShipOwner>> Authorize(JsonElement root, CancellationToken token)
        {
            token.ThrowIfCancellationRequested(); observedOwners++;
            return await Task.FromResult<IReadOnlyDictionary<string, CommunityClient.OfficialShipOwner>>(new Dictionary<string, CommunityClient.OfficialShipOwner> {
                [new string('c',64)] = new("visible","Bridge Pilot",new string('e',64),null,null) });
        }
        async Task<JsonElement> Search(string text = "Replacement", int offset = 0, string? revision = null, string scope = "account-generation|officialFleet:7") =>
            J(await client.ReadOfficialShipsAsync("fixture", J(new {schemaVersion=1,targetRef=reference,offset,revision,
                query=new{text,filter="concept",sort="name",descending=false,culture="en-US"}}),"officialFleet:7",scope,()=>{},Authorize,TimeProvider.System,default));
        var first = await Search();
        Check(offsets.SequenceEqual(new[] {0,20,40}) && observedOwners == 3, "loaner search reads and authorizes all source pages");
        Check(first.GetProperty("matchedCount").GetInt32()==25 && first.GetProperty("ships")[0].GetProperty("code").GetString()=="source-20", "late-page loaner hits preserved with truthful count");
        var revision = first.GetProperty("revision").GetString();
        var next = await Search(offset:20,revision:revision);
        Check(next.GetProperty("ships").GetArrayLength()==5,"search continuation uses full projected revision");
        var text = first.GetRawText();
        Check(!text.Contains("memberId") && !text.Contains("identityBinding") && !text.Contains("private-secret") && !text.Contains("ownerMemberId"),"private server IDs and raw authority never leave Host");
        Check(first.GetProperty("owners")[0].GetProperty("ownerMemberRef").GetString()!.Length==32 &&
            first.GetProperty("owners")[0].GetProperty("profileReference").GetString()!.Length==64,"display and profile scopes stay distinct");
        Check((await Search("Bridge Pilot")).GetProperty("matchedCount").GetInt32()==45,"owner-name search covers complete authorized projection");
        Check((await Search("private-secret")).GetProperty("matchedCount").GetInt32()==0,"private archive fields never searchable");
        foreach (var fault in new[]{"wrong-source","partial","expired","no-deadline","duplicate","media","large","changed"})
        {
            mode=fault; await Reject(()=>Search());
        }
        mode="ok";var calls=offsets.Count;await Reject(()=>Search(scope:"other-account"));Check(offsets.Count==calls,"foreign account rejected before HTTP");
        Console.WriteLine("PASS actual official client parser/catalog/loaner projection with synthetic authorized owner callback; no real service acceptance");
    }
    private static JsonElement J(object value)=>JsonSerializer.SerializeToElement(value);
    private static void Check(bool value,string message){if(!value)throw new InvalidOperationException(message);}
    private static async Task Reject(Func<Task<JsonElement>> action){try{await action();}catch(AccountBridgeHostException){return;}throw new InvalidOperationException("Expected fail-closed official ships read");}
    private static HttpResponseMessage Json(object value)=>new(HttpStatusCode.OK){Content=new StringContent(JsonSerializer.Serialize(value))};
    private sealed class Handler(Func<HttpRequestMessage,HttpResponseMessage> read):HttpMessageHandler
    {protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request,CancellationToken token)=>Task.FromResult(read(request));}
}
