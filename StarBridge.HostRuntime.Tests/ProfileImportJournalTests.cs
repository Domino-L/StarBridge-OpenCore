using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.Json.Serialization;
using StarBridge.Core.Profiles;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.Profiles;
using StarBridge.NativeBridge;
using Coordinator = StarBridge.HostRuntime.Profiles.SelectedProfileImportCoordinator;

internal static partial class ProfileImportJournalTests
{
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web) {
        PropertyNameCaseInsensitive = false, UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow, MaxDepth = 12
    };
    private static readonly BridgeAccountContext Owner = new("test", "https://authority.invalid", "synthetic-journal");
    private static string Hash(byte[] bytes) => Convert.ToHexString(SHA256.HashData(bytes));
    private static string Text<T>(T value) => JsonSerializer.Serialize(value, Json);
    private static void Check(bool value, string message) { if (!value) throw new Exception(message); }
    private static LocalProfileContent Content => new("导入兼容", "保留内容", 1, "none", [], [],
        new(["pilot"], ["exploration"], ["medical"]), new("America/Regina", "weekends", [new([1, 6], "23:30", "02:15")]), true,
        [new("achievements", true)], ["first-flight"]);
    private static Coordinator.Intent Value => new("journal-ticket", 0, Guid.NewGuid().ToString("N"), Content,
        new("previewed", "journal-ticket", Source: new("源", "简介", 0, 0, 1), Target: new("目标", "", 0, 0, null),
            Choices: new(1, [], [], true, []), SelectedContent: new("导入兼容", [], null, null, null),
            Presentation: new("旧展示", 2, "none", PersonalProfileContentContract.Empty with {
                Showcases = [new("achievements", false)], AchievementShowcase = [] })),
        Previous: new(0, null, null, Content with { Showcases = [], AchievementShowcase = ["first-flight"] }));
    private sealed class Fixture : IDisposable
    {
        internal readonly string Root = Path.Combine(Path.GetTempPath(), "StarBridge-PIMPORTJ-" + Guid.NewGuid().ToString("N"));
        internal string Key => Hash(JsonSerializer.SerializeToUtf8Bytes(Owner));
        internal string Main => Path.Combine(Root, "personal-profile-import-v1", Key + ".dat");
        internal string Side => Main + ".showcases";
        internal byte[] Entropy => Encoding.UTF8.GetBytes("StarBridge.SelectedProfileImport.v1\0" + Key);
        internal Coordinator Coordinator => new(new(Root));
        internal Task Write(Coordinator.Intent value) => Coordinator.RunAsync(Owner, () => true, session => {
            // Reach the real journal writer without changing production visibility.
            var field = typeof(Coordinator.Session).GetFields(BindingFlags.NonPublic | BindingFlags.Instance)
                .Single(f => f.FieldType == typeof(Action<Coordinator.Intent>));
            ((Action<Coordinator.Intent>)field.GetValue(session)!)(value);
            return Task.FromResult(0);
        });
        internal Task<Coordinator.Intent?> Read() => Coordinator.RunAsync(Owner, () => true, session => {
            var field = typeof(Coordinator.Session).GetFields(BindingFlags.NonPublic | BindingFlags.Instance)
                .Single(f => f.FieldType == typeof(Coordinator.Intent));
            return Task.FromResult((Coordinator.Intent?)field.GetValue(session));
        });
        internal byte[] Clear(string path) => ProtectedData.Unprotect(File.ReadAllBytes(path), Entropy, DataProtectionScope.CurrentUser);
        internal void Encrypt(string path, byte[] clear) => File.WriteAllBytes(path,
            ProtectedData.Protect(clear, Entropy, DataProtectionScope.CurrentUser));
        internal void Inline(Coordinator.Intent value) => Encrypt(Main, JsonSerializer.SerializeToUtf8Bytes(new { version = 1, owner = Key, intent = value }, Json));
        internal JsonObject SideJson() => JsonNode.Parse(Clear(Side))!.AsObject();
        internal void SideJson(JsonObject side, bool rehash = true)
        {
            if (rehash) side["integrity"] = Hash(JsonSerializer.SerializeToUtf8Bytes(new {
                version = side["version"]!.GetValue<int>(), owner = side["owner"]!.GetValue<string>(), entries = side["entries"]
            }, Json));
            Encrypt(Side, JsonSerializer.SerializeToUtf8Bytes(side, Json));
        }
        public void Dispose() { if (Directory.Exists(Root)) Directory.Delete(Root, true); }
    }
    internal static async Task Run()
    {
        var cases = new List<(string Name, Func<Task> Run)> {
            ("old Disallow contract and exact plaintext bytes", OldReader),
            ("read write read preserves complete intent", RoundTrip),
            ("main commit failure preserves A and rejects changed A", MainFailure),
            ("side commit failure leaves both files intact", SideFailure),
            ("shared journal lock", SharedLock),
            ("inline migration main failure and retry", InlineFailure),
            ("confirmation, apply and replay", ApplyReplay),
            ("first main commit failure leaves no active intent", FirstFailure),
            ("real full preview preserves previous showcases", FullStage),
            ("inline side failure preserves values and clears", InlineSideFailure),
            ("old confirmation interrupted before Applied recovers", OldConfirmRecovery),
            ("old confirmation and Applied preserve full intent", OldApplied),
            ("old new Stage does not inherit showcases", OldNewStage),
            ("progress commit failure preserves immutable operation slot", ProgressFailure),
            ("same operation with changed body is isolated", ChangedBody),
            ("legacy v1 companion remains readable and upgrades", LegacySide),
            ("inline split progress commit failure preserves both slots", InlineProgressFailure)
        };
        foreach (var mode in new[] { "missing", "cipher", "json", "owner", "integrity", "duplicate", "unknown", "version", "size", "binding" })
            cases.Add(("optional side " + mode, () => Damaged(mode)));
        foreach (var reverse in new[] { false, true })
            foreach (var empty in new[] { false, true })
                cases.Add(($"inline independent fields reverse={reverse} empty={empty}", () => InlineMerge(reverse, empty)));
        var failures = 0;
        foreach (var (name, run) in cases)
            try { await run(); Console.WriteLine("PASS PIMPORTJ " + name); }
            catch (Exception e) { failures++; Console.WriteLine("FAIL PIMPORTJ " + name + ": " + e); }
        Console.WriteLine($"SUMMARY PIMPORTJ passed={cases.Count - failures} failed={failures}");
        if (failures != 0) throw new Exception("PIMPORTJ regression failed");
    }
    private static void OldBytes(Fixture f, Coordinator.Intent value)
    {
        var clear = f.Clear(f.Main);
        var old = JsonSerializer.Deserialize<OldEnvelope>(clear, Json)!;
        var projection = new JsonSerializerOptions(Json) { UnmappedMemberHandling = JsonUnmappedMemberHandling.Skip };
        var expected = JsonSerializer.Deserialize<OldEnvelope>(Text(new { version = 1, owner = f.Key, intent = value }), projection);
        Check(clear.SequenceEqual(JsonSerializer.SerializeToUtf8Bytes(expected, Json)), "fe6c1cfc plaintext differs");
        Check(Text(old) == Text(expected), "old reader content differs");
    }
    private static async Task OldReader()
    {
        using var f = new Fixture();
        foreach (var value in new[] { Value, Value with { Content = null, Previous = null }, Value with {
            Preview = Value.Preview with { Presentation = null } }, Value with { Content = Content with {
                Modules = [new("favorite-ships", 1, true, 0, [new string('a', 32)])], FavoriteShipIds = [new string('a', 32)] } } })
        { await f.Write(value); OldBytes(f, value); Check(Text(await f.Read()) == Text(value), "new fields lost"); }
    }
    private static async Task RoundTrip()
    {
        using var f = new Fixture(); var value = Value;
        await f.Write(value); var first = (await f.Read())!;
        await f.Write(first); Check(Text(await f.Read()) == Text(value), "roundtrip identity changed");
        Check(!Encoding.UTF8.GetString(File.ReadAllBytes(f.Side)).Contains("first-flight"), "side not encrypted");
    }
    private static async Task Damaged(string mode)
    {
        using var f = new Fixture(); var value = Value; await f.Write(value);
        var side = f.SideJson();
        switch (mode)
        {
            case "missing": File.Delete(f.Side); break;
            case "cipher": File.WriteAllBytes(f.Side, [1, 2, 3]); break;
            case "size": File.WriteAllBytes(f.Side, new byte[512 * 1024 + 1]); break;
            case "json": f.Encrypt(f.Side, Encoding.UTF8.GetBytes("{")); break;
            case "duplicate": f.Encrypt(f.Side, Encoding.UTF8.GetBytes(side.ToJsonString()[..^1] + ",\"version\":1}")); break;
            default:
                if (mode == "owner") side["owner"] = new string('A', 64);
                if (mode == "integrity") side["integrity"] = "invalid";
                if (mode == "unknown") side["unexpected"] = true;
                if (mode == "version") side["version"] = 3;
                if (mode == "binding") side["entries"]![0]!["mainHash"] = new string('A', 64);
                f.SideJson(side, mode != "integrity"); break;
        }
        var read = (await f.Read())!;
        Check(read.Content!.Showcases is null && read.Content.AchievementShowcase is null &&
            read.Previous!.Content!.Showcases is null && read.Previous.Content.AchievementShowcase is null &&
            read.Preview.Presentation!.Content.Showcases is null && read.Preview.Presentation.Content.AchievementShowcase is null,
            "damaged side retained additions");
        OldBytes(f, value);
    }
    private static async Task ExpectIo(Func<Task> action)
    {
        try { await action(); } catch (IOException) { return; }
        throw new Exception("Expected IOException");
    }
    private static async Task MainFailure()
    {
        using var f = new Fixture(); var a = Value; await f.Write(a);
        var b = Value with { Content = Content with { Showcases = [], AchievementShowcase = [] } };
        var bytes = File.ReadAllBytes(f.Main);
        using (var locked = new FileStream(f.Main, FileMode.Open, FileAccess.Read, FileShare.Read))
            await ExpectIo(() => f.Write(b));
        Check(bytes.SequenceEqual(File.ReadAllBytes(f.Main)) && Text(await f.Read()) == Text(a), "failed B changed A");
        await f.Write(a); Check(Text(await f.Read()) == Text(a), "A replay changed identity");
        await ExpectIo(() => f.Write(a with { Content = a.Content! with { AchievementShowcase = [] } }));
        Check(Text(await f.Read()) == Text(a), "changed A committed");
        await f.Write(b); Check(Text(await f.Read()) == Text(b), "B retry failed");
    }
    private static async Task SideFailure()
    {
        using var f = new Fixture(); var a = Value; await f.Write(a);
        var main = File.ReadAllBytes(f.Main); var side = File.ReadAllBytes(f.Side);
        using (var locked = new FileStream(f.Side, FileMode.Open, FileAccess.Read, FileShare.Read))
            await ExpectIo(() => f.Write(Value));
        Check(main.SequenceEqual(File.ReadAllBytes(f.Main)) && side.SequenceEqual(File.ReadAllBytes(f.Side)) &&
            Text(await f.Read()) == Text(a), "failed side changed committed journal");
    }
    private static async Task SharedLock()
    {
        using var f = new Fixture(); var a = Value; await f.Write(a);
        using var locked = new FileStream(f.Main + ".lock", FileMode.Open, FileAccess.ReadWrite, FileShare.None);
        await ExpectIo(() => f.Write(Value));
    }
    private static async Task InlineMerge(bool reverse, bool empty)
    {
        using var f = new Fixture(); var value = Value; await f.Write(value);
        LocalProfileContent InlineContent(LocalProfileContent c) => reverse
            ? c with { Showcases = null, AchievementShowcase = empty ? [] : ["first-flight"] }
            : c with { Showcases = empty ? [] : [new("achievements", false)], AchievementShowcase = null };
        var p = value.Preview.Presentation!;
        var inline = value with { Content = InlineContent(value.Content!), Previous = value.Previous! with {
            Content = InlineContent(value.Previous.Content!) }, Preview = value.Preview with { Presentation = p with { Content = p.Content with {
                Showcases = reverse ? null : empty ? [] : [new("achievements", true)],
                AchievementShowcase = reverse ? empty ? [] : ["first-flight"] : null
            } } } };
        f.Inline(inline);
        // Bind a synthetic companion to the normalized inline body to exercise mixed sources.
        var side = f.SideJson(); side["entries"]![0]!["mainHash"] = NormalizedHash(f.Clear(f.Main)); f.SideJson(side);
        var merged = (await f.Read())!;
        Check(merged.Content!.Showcases is not null && merged.Content.AchievementShowcase is not null &&
            merged.Previous!.Content!.Showcases is not null && merged.Previous.Content.AchievementShowcase is not null &&
            merged.Preview.Presentation!.Content.Showcases is not null && merged.Preview.Presentation.Content.AchievementShowcase is not null,
            "one inline field masked the other side field");
        Check(reverse ? merged.Content.AchievementShowcase!.Count == (empty ? 0 : 1) :
            merged.Content.Showcases!.Count == (empty ? 0 : 1), "inline clear revived stale value");
        await f.Write(merged); OldBytes(f, merged);
        Check(Text(await f.Read()) == Text(merged), "inline split lost values");
    }
    private static async Task InlineFailure()
    {
        using var f = new Fixture(); var a = Value; await f.Write(a); f.Inline(a);
        Check(Text(await f.Read()) == Text(a), "old inline not readable");
        using (var locked = new FileStream(f.Main, FileMode.Open, FileAccess.Read, FileShare.Read))
            await ExpectIo(() => f.Write(Value));
        Check(Text(await f.Read()) == Text(a), "failed inline split changed A");
        await f.Write(a); OldBytes(f, a); Check(Text(await f.Read()) == Text(a), "inline retry changed A");
    }
    private static async Task FirstFailure()
    {
        using var f = new Fixture(); var value = Value;
        Directory.CreateDirectory(f.Main);
        await ExpectIo(() => f.Write(value));
        Check(await f.Read() is null && File.Exists(f.Side), "uncommitted first intent became active");
        Directory.Delete(f.Main);
        await f.Write(value); OldBytes(f, value);
        Check(Text(await f.Read()) == Text(value), "first write retry lost additions");
    }
    private static async Task FullStage()
    {
        using var f = new Fixture(); var store = new LocalPersonalProfileStore(f.Root);
        var before = store.Save(Owner, 0, Guid.NewGuid().ToString("N"), Content, () => true);
        var view = Value.Preview with { Choices = new(2, [], [], true, []), SelectedContent = null };
        await f.Coordinator.RunAsync(Owner, () => true, s => Task.FromResult(s.Stage(view,
            new([], [], false, ReplaceAllDisplayContent: true))));
        var intent = (await f.Read())!;
        Check(Text(intent.Previous) == Text(before) && Text(intent.Preview) == Text(view), "real full preview lost fields");
        OldBytes(f, intent);
    }
    private static async Task InlineSideFailure()
    {
        foreach (var empty in new[] { false, true })
        {
            using var f = new Fixture(); var a = Value;
            if (empty) a = a with { Content = a.Content! with { Showcases = [], AchievementShowcase = [] } };
            await f.Write(a); f.Inline(a);
            using (var locked = new FileStream(f.Side, FileMode.Open, FileAccess.Read, FileShare.Read))
                await ExpectIo(() => f.Write(Value));
            Check(Text(await f.Read()) == Text(a), "failed side split changed inline content");
            await f.Write(a); OldBytes(f, a);
            Check(Text(await f.Read()) == Text(a), "split retry revived old fields");
        }
    }
    private static async Task ApplyReplay()
    {
        using var f = new Fixture(); var a = Value; await f.Write(a);
        var completed = a.Preview with { State = "completed" };
        await f.Coordinator.RunAsync(Owner, () => true, s => { s.BeforeConfirm(a.Ticket); s.Apply(completed); return Task.FromResult(0); });
        var applied = (await f.Read())!;
        Check(applied.Confirmed && applied.Applied && Text(applied.Content) == Text(a.Content), "confirmation content changed");
        await f.Coordinator.RunAsync(Owner, () => true, s => { s.BeforeConfirm(a.Ticket); s.Apply(completed); return Task.FromResult(0); });
        Check(new LocalPersonalProfileStore(f.Root).Read(Owner).Revision == 1 && Text(await f.Read()) == Text(applied), "replay changed journal or revision");
    }

    private static void OldRewrite(Fixture f, Func<OldIntent, OldIntent> change)
    {
        var old = JsonSerializer.Deserialize<OldEnvelope>(f.Clear(f.Main), Json)!;
        f.Encrypt(f.Main, JsonSerializer.SerializeToUtf8Bytes(old with { Intent = change(old.Intent!) }, Json));
    }
    private static string NormalizedHash(byte[] bytes)
    {
        var body = JsonNode.Parse(bytes)!;
        body["intent"]!["confirmed"] = false;
        body["intent"]!["applied"] = false;
        return Hash(JsonSerializer.SerializeToUtf8Bytes(body, Json));
    }
    private static async Task<Coordinator.Intent> StageSelected(Fixture f)
    {
        var store = new LocalPersonalProfileStore(f.Root);
        store.Save(Owner, 0, Guid.NewGuid().ToString("N"), Content, () => true);
        await f.Coordinator.RunAsync(Owner, () => true, s => Task.FromResult(s.Stage(Value.Preview)));
        var intent = (await f.Read())!;
        Check(intent.Content!.Showcases is { Count: > 0 } && intent.Content.AchievementShowcase is { Count: > 0 },
            "Stage did not preserve existing showcases");
        return intent;
    }
    private static async Task OldConfirmRecovery()
    {
        using var f = new Fixture(); var staged = await StageSelected(f);
        OldRewrite(f, old => old with { Confirmed = true });
        // The old profile writer preserves its own companion additions. Model the
        // already-saved result, then interrupt before the old journal writes Applied.
        var store = new LocalPersonalProfileStore(f.Root);
        store.SaveImported(Owner, staged.ExpectedRevision, staged.Operation, staged.Content!, () => true);
        var completed = staged.Preview with { State = "completed" };
        await f.Coordinator.RunAsync(Owner, () => true, s => {
            s.BeforeConfirm(staged.Ticket);
            Check(s.Apply(completed).State == "completed", "recovery did not complete");
            return Task.FromResult(0);
        });
        var recovered = (await f.Read())!;
        Check(Text(recovered) == Text(staged with { Confirmed = true, Applied = true }), "recovery lost full Content");
        Check(store.Read(Owner).Revision == staged.ExpectedRevision + 1 &&
            Text(store.Read(Owner).Content) == Text(staged.Content), "recovery reapplied or changed profile");
    }
    private static async Task OldApplied()
    {
        using var f = new Fixture(); var staged = await StageSelected(f);
        OldRewrite(f, old => old with { Confirmed = true });
        OldRewrite(f, old => old with { Applied = true });
        Check(Text(await f.Read()) == Text(staged with { Confirmed = true, Applied = true }),
            "old completed progress lost showcases");
    }
    private static async Task OldNewStage()
    {
        using var f = new Fixture(); var staged = await StageSelected(f);
        // Even a repeated ticket is a new Stage when its operation changes.
        OldRewrite(f, old => old with { Operation = Guid.NewGuid().ToString("N") });
        var read = (await f.Read())!;
        Check(read.Ticket == staged.Ticket && read.Operation != staged.Operation &&
            read.Content!.Showcases is null && read.Content.AchievementShowcase is null,
            "old new operation inherited prior showcases");
    }
    private static async Task ProgressFailure()
    {
        using var f = new Fixture(); var a = Value; await f.Write(a);
        var main = File.ReadAllBytes(f.Main);
        using (var locked = new FileStream(f.Main, FileMode.Open, FileAccess.Read, FileShare.Read))
            await ExpectIo(() => f.Write(a with { Confirmed = true }));
        Check(main.SequenceEqual(File.ReadAllBytes(f.Main)) && Text(await f.Read()) == Text(a),
            "failed progress commit lost committed additions");
        Check(f.SideJson()["entries"]!.AsArray().Count == 1, "progress consumed a second operation slot");
        await ExpectIo(() => f.Write(a with { Confirmed = true, Content = a.Content! with { AchievementShowcase = [] } }));
        Check(Text(await f.Read()) == Text(a), "progress allowed changing an immutable additions slot");
        OldRewrite(f, old => old with { Confirmed = true });
        var confirmed = a with { Confirmed = true };
        Check(Text(await f.Read()) == Text(confirmed), "old progress after half commit lost additions");
        await f.Write(confirmed with { Applied = true });
        Check(Text(await f.Read()) == Text(confirmed with { Applied = true }), "progress retry failed");
    }
    private static async Task ChangedBody()
    {
        foreach (var field in new[] { "ticket", "revision", "content", "previous", "preview", "hangar" })
        {
            using var f = new Fixture(); var a = Value; await f.Write(a);
            OldRewrite(f, old => field switch {
                "ticket" => old with { Ticket = "other-ticket", Preview = old.Preview with { PreviewId = "other-ticket" } },
                "revision" => old with { ExpectedRevision = old.ExpectedRevision + 1 },
                "content" => old with { Content = old.Content! with { Introduction = "changed" } },
                "previous" => old with { Previous = old.Previous! with { Revision = 9 } },
                "preview" => old with { Preview = old.Preview with { SourceRevision = 9 } },
                _ => old with { HangarRevision = 9 }
            });
            var read = (await f.Read())!;
            Check(read.Content!.Showcases is null && read.Content.AchievementShowcase is null &&
                read.Previous!.Content!.Showcases is null && read.Previous.Content.AchievementShowcase is null &&
                read.Preview.Presentation!.Content.Showcases is null && read.Preview.Presentation.Content.AchievementShowcase is null,
                "changed " + field + " inherited unrelated additions");
        }
    }
    private static async Task LegacySide()
    {
        using var f = new Fixture(); var a = Value; await f.Write(a);
        var side = f.SideJson(); side["version"] = 1;
        side["entries"]![0]!["mainHash"] = Hash(f.Clear(f.Main)); f.SideJson(side);
        Check(Text(await f.Read()) == Text(a), "v1 exact-byte companion not readable");
        OldRewrite(f, old => old with { Confirmed = true });
        Check(Text(await f.Read()) == Text(a with { Confirmed = true }), "v1 Stage lost fields after old progress");
        await f.Write(a with { Confirmed = true });
        Check(f.SideJson()["version"]!.GetValue<int>() == 2 &&
            Text(await f.Read()) == Text(a with { Confirmed = true }), "v1 explicit-write upgrade lost fields");
    }
    private static async Task InlineProgressFailure()
    {
        using var f = new Fixture(); var a = Value; await f.Write(a); f.Inline(a);
        var main = File.ReadAllBytes(f.Main);
        using (var locked = new FileStream(f.Main, FileMode.Open, FileAccess.Read, FileShare.Read))
            await ExpectIo(() => f.Write(a with { Confirmed = true }));
        Check(f.SideJson()["entries"]!.AsArray().Count == 2 && main.SequenceEqual(File.ReadAllBytes(f.Main)) &&
            Text(await f.Read()) == Text(a), "inline half commit did not preserve two distinct bodies");
        await f.Write(a with { Confirmed = true }); OldBytes(f, a with { Confirmed = true });
        OldRewrite(f, old => old with { Applied = true });
        Check(Text(await f.Read()) == Text(a with { Confirmed = true, Applied = true }), "inline split progress lost fields");
    }
}
