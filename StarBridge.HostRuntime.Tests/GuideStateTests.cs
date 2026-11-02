using System.Text.Json;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Onboarding;
using StarBridge.NativeBridge;

internal static class GuideStateTests
{
    internal static async Task Run()
    {
        // Release runs have no source root; any private scratch folder works.
        var source = Environment.GetEnvironmentVariable("STARBRIDGE_HOST_TEST_SOURCE_ROOT");
        var root = source is null
            ? Path.Combine(Path.GetTempPath(), "starbridge-guide-tests", Guid.NewGuid().ToString("N"))
            : Path.Combine(source, ".codex-build", "guide-tests", Guid.NewGuid().ToString("N"));
        HostDataRoot.UsePreparedRoot(root);
        FirstUseModeRuntime.GuideScope? scope = null;
        using var bridge = new GuideStateBridgeDispatcher(root, () => scope, () => 1);
        var store = new GuideStateStore(root);
        var passed = 0;
        void Check(bool ok, string label) { if (!ok) throw new Exception("FAIL " + label); passed++; Console.WriteLine("PASS " + label); }
        async Task<BridgeEnvelope> Send(string payload, string name = GuideStateBridgeDispatcher.UpdateRequest) =>
            (await bridge.DispatchAsync(BridgeEnvelope.Request(name, Guid.NewGuid().ToString("N"), 1,
                JsonSerializer.Deserialize<JsonElement>(payload)))).Response;
        async Task<JsonElement> Update(string ops)
        {
            var response = await Send("{\"ops\":[" + ops + "]}");
            if (response.Status != "ok") throw new Exception(response.Error?.Code);
            return response.Payload;
        }
        async Task<JsonElement> Read() => (await Send("{}", GuideStateBridgeDispatcher.ReadRequest)).Payload;
        Check((await Read()).GetRawText() == "{\"schemaVersion\":1,\"state\":\"unavailable\"}", "no profile read unavailable");
        Check((await Update("{\"op\":\"markEligible\"}")).GetProperty("state").GetString() == "unavailable" && !Directory.Exists(root), "no profile update never writes");
        scope = new("profile-a", 1, 1);
        Check(!(await Read()).GetProperty("eligible").GetBoolean(), "empty state in installed profile");
        Check((await Send("{\"ops\":[{\"op\":\"unknown\"}]}")).Error?.Code == "guide.invalid_request" && !Directory.Exists(root), "first invalid update creates no directory");
        var value = await Update("{\"op\":\"markSeen\",\"id\":\"tip.fleet\"},{\"op\":\"markSeen\",\"id\":\"tip.fleet\"},{\"op\":\"markDone\",\"id\":\"hangar\"},{\"op\":\"markDone\",\"id\":\"hangar\"}");
        Check(value.GetProperty("seen").GetArrayLength() == 1 && value.GetProperty("checklist").GetProperty("done").GetArrayLength() == 1, "seen and done idempotent");
        Check(value.GetRawText() == (await Read()).GetRawText(), "read and update projections identical");
        value = await Update("{\"op\":\"markEligible\"},{\"op\":\"markEligible\"},{\"op\":\"setChecklist\",\"collapsed\":true,\"dismissed\":true,\"celebrated\":true}");
        Check(value.GetProperty("eligible").GetBoolean() && value.GetProperty("checklist").GetProperty("celebrated").GetBoolean(), "eligibility and checklist persisted");
        value = await Update("{\"op\":\"setChecklist\",\"collapsed\":false}");
        Check(!value.GetProperty("checklist").GetProperty("collapsed").GetBoolean() && value.GetProperty("checklist").GetProperty("dismissed").GetBoolean(), "partial checklist preserves omitted fields");
        value = await Update("{\"op\":\"resetSeen\"},{\"op\":\"resetChecklist\"}");
        var checklist = value.GetProperty("checklist");
        Check(value.GetProperty("seen").GetArrayLength() == 0 && value.GetProperty("eligible").GetBoolean() && checklist.GetProperty("done").GetArrayLength() == 1 &&
            !checklist.GetProperty("collapsed").GetBoolean() && !checklist.GetProperty("dismissed").GetBoolean() && !checklist.GetProperty("celebrated").GetBoolean(), "resets preserve done and eligibility");
        var path = store.StatePath("profile-a");
        async Task Reject(string payload)
        {
            var before = File.ReadAllBytes(path); var stamp = File.GetLastWriteTimeUtc(path);
            var response = await Send(payload);
            Check(response.Error?.Code == "guide.invalid_request" && before.SequenceEqual(File.ReadAllBytes(path)) && stamp == File.GetLastWriteTimeUtc(path), "invalid request leaves file unchanged: " + payload);
        }
        foreach (var payload in new[] {
            "{}", "{\"ops\":[]}", "{\"ops\":null}", "{\"ops\":[{\"op\":\"unknown\"}]}",
            "{\"ops\":[{\"op\":\"markEligible\",\"eligible\":false}]}",
            "{\"ops\":[{\"op\":\"setChecklist\"}]}", "{\"ops\":[{\"op\":\"setChecklist\",\"collapsed\":null}]}",
            "{\"ops\":[{\"op\":\"setChecklist\",\"collapsed\":1}]}",
            "{\"ops\":[{\"op\":\"markSeen\",\"id\":\"UPPER\"}]}",
            "{\"ops\":[{\"op\":\"markSeen\",\"id\":\"a\\n\"}]}",
            "{\"ops\":[{\"op\":\"markDone\",\"id\":1}]}",
            "{\"ops\":[{\"op\":\"markEligible\",\"op\":\"resetSeen\"}]}",
            "{\"ops\":[{\"op\":\"markEligible\"}],\"extra\":true}",
            "{\"ops\":[{\"op\":\"markSeen\",\"id\":\"valid\"},{\"op\":\"unknown\"}]}"
        }) await Reject(payload);
        await Reject(JsonSerializer.Serialize(new { ops = Enumerable.Range(0, 17).Select(_ => new { op = "resetSeen" }) }));
        await Reject(JsonSerializer.Serialize(new { ops = new[] { new { op = "markSeen", id = new string('a', 49) } } }));
        for (var batch = 0; batch < 4; batch++)
            await Send(JsonSerializer.Serialize(new { ops = Enumerable.Range(batch * 16, 16).Select(i => new { op = "markSeen", id = "s" + i }) }));
        Check((await Read()).GetProperty("seen").GetArrayLength() == 64, "64 seen accepted");
        await Reject("{\"ops\":[{\"op\":\"markSeen\",\"id\":\"overflow\"}]}");
        await Update("{\"op\":\"markSeen\",\"id\":\"s0\"}");
        await Send(JsonSerializer.Serialize(new { ops = Enumerable.Range(0, 15).Select(i => new { op = "markDone", id = "d" + i }) }));
        Check((await Read()).GetProperty("checklist").GetProperty("done").GetArrayLength() == 16, "16 done accepted");
        await Reject("{\"ops\":[{\"op\":\"resetSeen\"},{\"op\":\"markDone\",\"id\":\"overflow\"}]}");
        scope = new("profile-b", 2, 2);
        Check(!(await Read()).GetProperty("eligible").GetBoolean() && (await Read()).GetProperty("seen").GetArrayLength() == 0, "second profile independent");
        await Update("{\"op\":\"markSeen\",\"id\":\"tip.other\"}");
        scope = new("profile-a", 3, 3);
        Check((await Read()).GetProperty("seen").GetArrayLength() == 64 && (await Read()).GetProperty("eligible").GetBoolean(), "switch back restores first profile");
        Check(new FileInfo(path).Length <= 8192 && Path.GetFileNameWithoutExtension(path).Length == 64, "bounded hashed storage");
        foreach (var corrupt in new[] { "broken", "{}", "{\"schemaVersion\":1,\"eligible\":true,\"seen\":[],\"checklist\":null}",
            "{\"schemaVersion\":1,\"eligible\":true,\"seen\":[],\"checklist\":{\"collapsed\":false,\"dismissed\":false,\"celebrated\":false,\"done\":[]},\"extra\":0}", new string('x', 8193) })
        {
            File.WriteAllText(path, corrupt);
            Check(!(await Read()).GetProperty("eligible").GetBoolean(), "corrupt document defaults empty");
        }
        value = await Update("{\"op\":\"markSeen\",\"id\":\"recovered\"}");
        Check(value.GetProperty("seen")[0].GetString() == "recovered" && !store.Read("profile-a").Eligible, "update replaces corrupt file");
        Check((await Send("{\"extra\":1}", GuideStateBridgeDispatcher.ReadRequest)).Error?.Code == "guide.invalid_request", "read requires empty object");
        var stale = await bridge.DispatchAsync(BridgeEnvelope.Request(GuideStateBridgeDispatcher.ReadRequest, "stale", 0, new { }));
        Check(stale.Response.Error?.Code == "guide.context_changed", "stale generation rejected");
        var original = File.ReadAllBytes(path);
        var currentCalls = 0;
        var operation = JsonSerializer.Deserialize<JsonElement>("{\"op\":\"markEligible\"}");
        try
        {
            store.Update("profile-a", [operation], () => ++currentCalls == 1);
            throw new Exception("Context change was accepted");
        }
        catch (LocalFirstUseException e)
        {
            Check(e.Code == "guide.context_changed" && original.SequenceEqual(File.ReadAllBytes(path)) &&
                !Directory.EnumerateFiles(Path.GetDirectoryName(path)!, "*.tmp").Any(), "context change before replace preserves file and removes temporary");
        }
        Console.WriteLine($"GuideStateTests: {passed} passed, 0 failed");
    }
}
