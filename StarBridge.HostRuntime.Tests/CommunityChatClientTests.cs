using System.Net;
using System.Net.Http.Json;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Communities;

internal static class CommunityChatClientTests
{
    internal static async Task Verify()
    {
        var mode = "ok";
        var requests = new List<string>();
        var receipts = new List<JsonElement>();
        var image = new byte[400 * 1024];
        new byte[] {137,80,78,71,13,10,26,10}.CopyTo(image,0);
        var avatar = "data:image/png;base64," + Convert.ToBase64String(image);
        using var handler = new Handler(async request =>
        {
            Check(request.Headers.Authorization?.Parameter == "test-bearer", "only supplied bearer");
            var path=request.RequestUri!.AbsolutePath;
            var query=Uri.UnescapeDataString(request.RequestUri.Query);
            requests.Add(path+query);
            if (path == "/api/fleets/chat/read")
            {
                Check(request.Method == HttpMethod.Post, "receipt POST only");
                using var requestBody = JsonDocument.Parse(await request.Content!.ReadAsStringAsync());
                receipts.Add(requestBody.RootElement.Clone());
                if (mode == "receipt-lost") throw new HttpRequestException("fixture disconnected");
                if (mode.StartsWith("receipt-status-")) return new((HttpStatusCode)int.Parse(mode[15..]));
                if (mode == "receipt-malformed") return new(HttpStatusCode.OK) { Content = new StringContent("{") };
                if (mode == "receipt-big") return new(HttpStatusCode.OK) { Content = new StringContent(new string('x', 4097)) };
                if (mode == "receipt-duplicate") return new(HttpStatusCode.OK) { Content = new StringContent("{\"channelId\":\"fleet:A\",\"readThroughSequence\":12,\"readThroughSequence\":25}") };
                return Json(new { channelId = mode == "receipt-cross" ? "fleet:B" : "fleet:a",
                    readThroughSequence = mode == "receipt-backward" ? 11 : 25,
                    error = mode == "receipt-error" ? "failure" : null });
            }
            Check(request.Method == HttpMethod.Get, "history and detail never POST");
            if(path=="/api/fleets/directory") return Json(new
            {
                schemaVersion=1,membershipModelVersion=2,view="mine",query="",next=(string?)null,
                items=new[]{"A","B"}.Select(code=>new{code,name="Organization "+code,description="",language="",activeTime="",
                    memberCount=2,relationship="member",joinMode="direct",actions=new[]{"leave"},logoImageData=(string?)null})
            });
            if(mode=="forbidden") return new(HttpStatusCode.Forbidden);
            if(mode=="unauthorized") return new(HttpStatusCode.Unauthorized);
            if(mode=="lost") throw new HttpRequestException("fixture disconnected");
            if(path=="/api/fleets/chat/channels") return Json(new
            {
                totalUnread=2,channels=new[]{new{channelId=mode=="wrong-channel"?"fleet:B":"fleet:A",type="fleet",unreadCount=2,
                    latestSequence=20,lastMessagePreview="Must not leak private extra",canSend=true}}
            });
            Check(path=="/api/fleets/chat/messages" && query.Contains("fleetCode=A") && query.Contains("channelId=fleet:A"), "resolved exact org and main channel");
            if(query.Contains("projection=client"))
            {
                var page=JsonSerializer.SerializeToNode(new
                {
                    schemaVersion=1,channelId="fleet:A",latestSequence=20,oldestSequence=10,hasOlder=true,canSend=true,
                    serverTime="2026-09-07T00:00:00Z",privateField="do-not-export",
                    messages=new[]{10,12}.Select(sequence=>new{sequence,messageId="message-"+sequence,senderAccountId="sender-private-id",
                        senderCallsign="Visible callsign",senderGameId="",senderRoleTitle="成员",senderRoleColor="#29AFFF",
                        text="hello\nworld",createdAt="2026-09-06T23:00:00Z",isSelf=sequence==12,hasAvatar=true,hasAttachment=sequence==12})
                })!;
                switch(mode)
                {
                    case "bad-version":page["schemaVersion"]=2;break;
                    case "bad-oldest":page["oldestSequence"]=11;break;
                    case "bad-latest":page["latestSequence"]=11;break;
                    case "bad-time":page["serverTime"]="not-time";break;
                    case "bad-sequence":page["messages"]![1]!["sequence"]=10;break;
                    case "bad-self":page["messages"]![1]!["isSelf"]="true";break;
                    case "bad-color":page["messages"]![0]!["senderRoleColor"]="red";break;
                    case "bad-text":page["messages"]![0]!["text"]=new string('x',1001);break;
                    case "bad-id":page["messages"]![0]!["messageId"]="";break;
                    case "too-big":page["extra"]=new string('x',1000000);break;
                }
                return Json(page);
            }
            Check(query.EndsWith("&before=13&limit=1",StringComparison.Ordinal), "details only request exact previously projected message");
            return Json(new
            {
                channelId="fleet:A",error=(string?)null,messages=new[]{new{sequence=mode=="gone"?11:12,
                    messageId=mode=="replaced"?"replacement":"message-12",channelId="fleet:a",senderAccountId="sender-private-id",
                    senderAvatarImageData=mode=="changed"?"data:image/png;base64,"+Convert.ToBase64String(image[..^1]):avatar,
                    attachment=new{kind="overlay_preset",title="Fixture",summary="fixture",overlayPresetPackage="{\"version\":1,\"name\":\"Fixture\",\"settings\":\"{}\",\"layout\":\"{}\"}"}}}
            });
        });
        using var client=new CommunityClient(new Uri("https://community.invalid"),handler);
        var directory=await client.ReadAsync("test-bearer",new("mine","",null,null),"scope",default);
        var a=directory.Items[0].TargetRef; var b=directory.Items[1].TargetRef;
        JsonElement Body(long after=0,long before=0)=>JsonSerializer.SerializeToElement(new{schemaVersion=1,targetRef=a,after,before});
        async Task<JsonElement> Read(JsonElement? body=null,Action? current=null)=>JsonSerializer.SerializeToElement(
            await client.ReadChatAsync("test-bearer",body??Body(),"scope",current??(()=>{}),default));
        var page=await Read();
        Check(!page.GetRawText().Contains("sender-private-id") && !page.GetRawText().Contains("do-not-export") &&
            !page.GetRawText().Contains("message-12") && !page.TryGetProperty("channelId",out _),"raw identities and extras stay in Host");
        var rows=page.GetProperty("messages");
        Check(rows[0].GetProperty("senderRef").GetString()==rows[1].GetProperty("senderRef").GetString(),"same author shares scoped menu reference");
        Check(!rows[0].GetProperty("isSelf").GetBoolean() && rows[1].GetProperty("isSelf").GetBoolean(),"authoritative self not guessed from callsign");
        Check(rows[0].GetProperty("text").GetString()=="hello\nworld" && rows[0].GetProperty("createdAt").GetString()=="2026-09-06T23:00:00Z","original text/time preserved");
        var messageRef=rows[1].GetProperty("messageRef").GetString()!;
        var second=await Read();
        Check(second.GetProperty("messages")[1].GetProperty("messageRef").GetString()==messageRef,"stable projected message key across refresh");
        JsonElement DetailBody(string target,int offset=0,string? version=null)=>JsonSerializer.SerializeToElement(new{schemaVersion=1,targetRef=target,messageRef,offset,version});
        async Task<JsonElement> Detail(JsonElement body,string scope="scope",Action? current=null)=>JsonSerializer.SerializeToElement(
            await client.ReadChatDetailAsync("test-bearer",body,scope,current??(()=>{}),default));
        var first=await Detail(DetailBody(a));
        Check(first.GetProperty("next").GetInt32()==192*1024 && first.GetRawText().Length<300000,"bounded chunk fits bridge");
        var version=first.GetProperty("version").GetString()!;
        var bytes=new List<byte>(Convert.FromBase64String(first.GetProperty("data").GetString()!));
        var cursor=first.GetProperty("next");
        while(cursor.ValueKind!=JsonValueKind.Null)
        {
            var chunk=await Detail(DetailBody(a,cursor.GetInt32(),version));
            bytes.AddRange(Convert.FromBase64String(chunk.GetProperty("data").GetString()!)); cursor=chunk.GetProperty("next");
        }
        using(var detail=JsonDocument.Parse(bytes.ToArray()))
        {
            Check(detail.RootElement.GetProperty("avatarImageData").GetString()==avatar,"whole original avatar survives chunk transport");
            Check(detail.RootElement.GetProperty("attachment").GetProperty("kind").GetString()=="overlay_preset","existing preset attachment preserved");
        }
        var count=requests.Count;
        await Error(()=>Detail(DetailBody(b)),"communities.refreshRequired");
        await Error(()=>Detail(DetailBody(a),"other-scope"),"communities.refreshRequired");
        await Error(()=>Detail(DetailBody(a,1)),"communities.dataInvalid");
        await Error(()=>Detail(DetailBody(a,192*1024)),"communities.dataInvalid");
        await Error(()=>Read(Body(1,2)),"communities.dataInvalid");
        await Error(()=>Read(Body(-1)),"communities.dataInvalid");
        Check(requests.Count==count,"invalid references/cursors rejected before network");
        mode="changed"; await Error(()=>Detail(DetailBody(a,192*1024,version)),"communities.mediaChanged");
        foreach(var failure in new[]{"gone","replaced"}){mode=failure;await Error(()=>Detail(DetailBody(a)),"communities.notFound");}
        foreach(var failure in new[]{"wrong-channel","bad-version","bad-oldest","bad-latest","bad-time","bad-sequence","bad-self","bad-color","bad-text","bad-id","too-big"})
        {mode=failure;await Error(()=>Read(),"communities.dataInvalid");}
        foreach(var (failure,error) in new[]{("forbidden","notAllowed"),("unauthorized","identityUnavailable"),("lost","unavailable")})
        {mode=failure;await Error(()=>Read(),"communities."+error);await Error(()=>Detail(DetailBody(a)),"communities."+error);}
        mode="ok";
        var checks=0;
        await Error(()=>Read(current:()=>{if(++checks==3)throw new AccountBridgeHostException("communities.identityUnavailable");}),"communities.identityUnavailable");
        checks=0;
        await Error(()=>Detail(DetailBody(a),current:()=>{if(++checks==2)throw new AccountBridgeHostException("communities.identityUnavailable");}),"communities.identityUnavailable");
        Check(receipts.Count == 0, "fetching and hydrating messages never marks read");
        JsonElement ReadBody(string target, string? reference = null) => JsonSerializer.SerializeToElement(new
            { schemaVersion = 1, targetRef = target, messageRef = reference ?? messageRef });
        async Task<JsonElement> Mark(JsonElement body, string scope = "scope", Action? current = null, CancellationToken token = default) =>
            JsonSerializer.SerializeToElement(await client.MarkChatReadAsync("test-bearer", body, scope, current ?? (() => {}), token));
        mode = "ok";
        var marked = await Mark(ReadBody(a));
        Check(marked.GetProperty("status").GetString() == "accepted" && marked.GetProperty("readThroughSequence").GetInt64() == 25,
            "another device's farther cursor remains authoritative");
        Check(receipts.Single().GetProperty("throughSequence").GetInt64() == 12 &&
            receipts[0].GetProperty("fleetCode").GetString() == "A" && receipts[0].GetProperty("channelId").GetString() == "fleet:A",
            "posts fetched message sequence not page latest or UI supplied channel");
        Check(!marked.TryGetProperty("channelId", out _) && marked.GetProperty("targetRef").GetString() == a &&
            marked.GetProperty("messageRef").GetString() == messageRef, "scoped correlated receipt without raw identities");
        var receiptCount = receipts.Count;
        foreach (var rejected in new[] { await Mark(ReadBody(b)), await Mark(ReadBody(a), "different-account"),
                     await Mark(ReadBody(a, new string('f',32))),
                     await Mark(ReadBody(a), current: () => throw new AccountBridgeHostException("communities.identityUnavailable")),
                     await Mark(ReadBody(a), token: new CancellationToken(true)) })
            Check(rejected.GetProperty("status").GetString() == "rejected", "invalid scope/message/context/cancel rejects before POST");
        await Error(() => Mark(JsonSerializer.SerializeToElement(new { schemaVersion = 1, targetRef = a, messageRef, throughSequence = 999 })),
            "communities.dataInvalid");
        Check(receipts.Count == receiptCount, "invalid receipts cause no network mutation");
        foreach (var failure in new[] { "receipt-lost", "receipt-malformed", "receipt-big", "receipt-duplicate", "receipt-cross", "receipt-backward", "receipt-error", "receipt-status-500", "receipt-status-302" })
        {
            mode = failure;
            var before = receipts.Count;
            var result = await Mark(ReadBody(a));
            Check(result.GetProperty("status").GetString() == "unknown" && result.GetProperty("readThroughSequence").ValueKind == JsonValueKind.Null,
                "uncertain receipt never confirms read: " + failure);
            Check(receipts.Count == before + 1, "no automatic POST retry");
        }
        foreach (var (status, error) in new[] { (400,"dataInvalid"), (401,"identityUnavailable"), (403,"notAllowed"), (404,"refreshRequired"), (429,"rateLimited") })
        {
            mode = "receipt-status-" + status;
            var result = await Mark(ReadBody(a));
            Check(result.GetProperty("status").GetString() == "rejected" && result.GetProperty("error").GetString() == error,
                "server rejection preserved: " + status);
        }
        mode = "ok";
        checks = 0;
        var staleReceipt = await Mark(ReadBody(a), current: () => { if (++checks == 3) throw new AccountBridgeHostException("communities.identityUnavailable"); });
        Check(staleReceipt.GetProperty("status").GetString() == "unknown", "late response after account change does not acknowledge read");
        Check((await Mark(ReadBody(a))).GetProperty("status").GetString() == "accepted", "explicit monotonic retry remains possible");
        client.Dispose();
        await Error(()=>Detail(DetailBody(a)),"communities.refreshRequired");
        receiptCount = receipts.Count;
        Check((await Mark(ReadBody(a))).GetProperty("status").GetString() == "rejected" && receipts.Count == receiptCount,
            "disposed references cannot submit receipts");
    }
    private static HttpResponseMessage Json(object value)=>new(HttpStatusCode.OK){Content=JsonContent.Create(value)};
    private static void Check(bool condition,string label){if(!condition)throw new InvalidOperationException(label);}
    private static async Task Error(Func<Task> action,string code)
    {
        try{await action();throw new InvalidOperationException("Expected "+code);}
        catch(AccountBridgeHostException e)when(e.Code==code){}
    }
    private sealed class Handler(Func<HttpRequestMessage,Task<HttpResponseMessage>> action):HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request,CancellationToken token)=>action(request);
    }
}
