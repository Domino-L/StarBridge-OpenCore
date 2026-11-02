using System.Reflection;
using System.Text.Json;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Achievements;
using StarBridge.NativeBridge;

internal static class ScmAchievementTests
{
    private static readonly BridgeAccountContext Owner = new("test", "scm", "synthetic-scm-achievement");
    private static ScmAchievementItem Item(int id) => new($"scm-{id}", "SCM collection", null, "Description", "Condition",
        "https://assets.example.invalid/a.png", "EPIC", "NORMAL", id == 1, null, 1.25m, 2.5m, id);
    private static ScmAchievementCatalog Catalog(int count = 129) => new(1, DateTimeOffset.UtcNow.AddMinutes(-1),
        Enumerable.Range(1, count).Select(Item).ToArray());
    private static void Check(bool value, string message) { if (!value) throw new InvalidOperationException(message); }
    internal static async Task Run()
    {
        await ScmAchievementRemoteTests.Run();
        var snapshot = Catalog(); snapshot.Validate();
        var options = new JsonSerializerOptions(JsonSerializerDefaults.Web);
        string? version = null; var ids = new HashSet<string>();
        for (var offset = 0; offset < snapshot.Items.Length; offset += ScmAchievementPages.Size)
        {
            var page = JsonSerializer.SerializeToElement(ScmAchievementPages.Read(snapshot, offset, version, false), options);
            version = page.GetProperty("snapshotId").GetString();
            foreach (var row in page.GetProperty("items").EnumerateArray()) Check(ids.Add(row.GetProperty("id").GetString()!), "Duplicate page item");
        }
        Check(ids.Count == 129, "Complete catalog survives native paging");
        try { ScmAchievementPages.Read(snapshot,16,"changed",false); throw new Exception("Changed snapshot accepted"); }
        catch (InvalidOperationException) { }
        var large = Catalog(16) with { Items = Enumerable.Range(1,16).Select(id => Item(id) with {
            Name = new string('星',160), Title = new string('星',300), Description = new string('星',4000),
            Condition = new string('星',4000), ImageUrl = "https://assets.example.invalid/" + new string('a',2000)
        }).ToArray() };
        large.Validate();
        var request = BridgeEnvelope.Request("scmAchievements.read", "wire", 1, new { schemaVersion=1 },Owner);
        var bytes = JsonSerializer.SerializeToUtf8Bytes(BridgeEnvelope.Response(request,ScmAchievementPages.Read(large,0,null,false)),BridgeProtocol.JsonOptions);
        Check(bytes.Length < BridgeProtocol.MaximumFrameBytes, "Max escaped source rows fit the real native frame budget");
        var root = Path.Combine(Path.GetTempPath(), "sb-scm-achievement-"+Guid.NewGuid().ToString("N"));
        try {
            var store = new OfflineAccountStore(root);
            store.Observe(Owner,"Synthetic",()=>true);
            store.ObserveAchievements(Owner,new(1,new() { ["first-entry"] = DateTimeOffset.UtcNow.AddDays(-1) }),()=>true);
            store.ObserveScmAchievements(Owner,snapshot,()=>true);
            Check(store.ReadSelectedScmAchievements(Owner,()=>true)?.Items[0].CurrentValue == 1.25m,"SCM cache preserves decimals");
            var revoked = snapshot with { ReadAtUtc = snapshot.ReadAtUtc.AddSeconds(1), Items = [Item(1) with { Unlocked=false, CurrentValue=0.5m }] };
            store.ObserveScmAchievements(Owner,revoked,()=>true);
            Check(store.ReadSelectedScmAchievements(Owner,()=>true) is { Items: [{ Unlocked:false,CurrentValue:0.5m }] },"SCM cache replaces rather than unions");
            Check(store.ReadSelectedAchievements(Owner,()=>true)?.Collection.EarnedAt.ContainsKey("first-entry")==true,"SCM replacement preserves Bridge milestones");
            Check(store.ReadSelectedScmAchievements(Owner with { Subject="other" },()=>true) is null,"Other owner cannot read SCM cache");
            store.Observe(Owner with { Subject="other" },"Other",()=>true);
            Check(store.ReadSelectedScmAchievements(Owner with { Subject="other" },()=>true) is null,"Switching owner drops source snapshot");
        } finally { if (Directory.Exists(root)) Directory.Delete(root,true); }
        var host = DispatchProxy.Create<IAccountBridgeHost, Probe>(); var probe = (Probe)(object)host;
        using var runtime = new AccountBridgeRuntime(host);
        using var composite = new CompositeBridgeDispatcher(runtime,runtime,runtime);
        var first = await composite.DispatchAsync(request);
        Check(first.Response.Status == "ok" && first.Events.Count == 0 && probe.Reads == 1,"Read-only SCM route crosses production composite without celebrations");
        var idVersion=first.Response.Payload.GetProperty("snapshotId").GetString();
        var second=await composite.DispatchAsync(BridgeEnvelope.Request("scmAchievements.read","next",1,new {schemaVersion=1,offset=16,snapshotId=idVersion},Owner));
        Check(second.Response.Status=="ok" && probe.Reads==1,"Later pages reuse the same complete upstream snapshot");
        probe.Generation=2;
        Check((await composite.DispatchAsync(BridgeEnvelope.Request("scmAchievements.read","stale",1,new {schemaVersion=1},Owner))).Response.Status!="ok","Stale generation is denied");
        Console.WriteLine("PASS SCM full catalog, frame bounds, replaceable cache, ownership and composed read-only routing");
    }
    public class Probe : DispatchProxy
    {
        internal long Generation=1; internal int Reads;
        protected override object? Invoke(MethodInfo? method, object?[]? args) => method!.Name switch {
            "get_Generation" => Generation, "get_CurrentContext" => Owner,
            "get_SupportsConcurrentReads" => false,
            "add_AccountChanged" or "remove_AccountChanged" or "Dispose" => null,
            "ReadScmAchievementsAsync" => Read(),
            _ => throw new NotSupportedException(method.Name)
        };
        private Task<ScmAchievementCatalog> Read() { Reads++; return Task.FromResult(Catalog()); }
    }
}
