using System.Security.AccessControl;
using System.Security.Principal;
using System.Text.Json;
using System.Text.Json.Nodes;
using StarBridge.Core.Identity;
using StarBridge.HostRuntime.Hangar;
using StarBridge.NativeBridge;

internal static class LocalHangarReadFailureTests
{
    public static Task Verify()
    {
        var wire = Capture();
        Require(wire["busy"].Error is { Code: "hangar.storage_busy", Retryable: true },
            $"Read contention needs an explicit retryable result, got {wire["busy"].Error?.Code}/{wire["busy"].Error?.Retryable}.");
        Require(wire["writeBusy"].Error is { Code: "hangar.storage_busy", Retryable: false },
            "Write contention must never request automatic write replay.");
        foreach (var key in new[] { "malformed", "ownerMismatch", "integrity", "fileKind", "directoryKind", "permission" })
            Require(wire[key].Error is { Code: "hangar.storage_read_failed", Retryable: false },
                $"{key} must remain a hard rejection.");
        foreach (var key in new[] { "otherOwner", "staleGeneration", "retiredDuringRead", "storageOwnerRetired" })
            Require(wire[key].Error is { Code: "hangar.account_changed", Retryable: false },
                $"{key} must not be softened to a busy read.");
        Require(wire["success"].Payload.GetProperty("revision").GetInt64() == 1 &&
            wire["recovered"].Payload.GetRawText() == wire["success"].Payload.GetRawText(),
            "Recovery must preserve the exact confirmed inventory without rewriting it.");
        Require(wire["absent"].Payload.GetProperty("revision").GetInt64() == 0 &&
            wire["absent"].Payload.GetProperty("total").GetInt32() == 0,
            "True absence remains an unsaved empty inventory.");
        return Task.CompletedTask;
    }

    public static string Wire() => JsonSerializer.Serialize(Capture(), BridgeProtocol.JsonOptions);

    private static Dictionary<string, BridgeEnvelope> Capture()
    {
        using var fixture = new Fixture();
        var wire = new Dictionary<string, BridgeEnvelope> { ["success"] = fixture.Send() };
        var original = File.ReadAllBytes(fixture.FilePath);
        using (File.Open(fixture.FilePath, FileMode.Open, FileAccess.Read, FileShare.None))
        {
            wire["busy"] = fixture.Send();
            wire["writeBusy"] = fixture.Send("favorite", new JsonObject {
                ["shipId"] = fixture.ShipId, ["favorite"] = true, ["expectedRevision"] = 1,
                ["operationId"] = "read-failure-no-write-replay" });
            wire["otherOwner"] = fixture.Send(context: fixture.Owner.Account with { Subject = "other" });
            wire["staleGeneration"] = fixture.Send(generation: fixture.Owner.Generation - 1);
            var owner = fixture.Owner;
            fixture.Store.ResolveOwner = account => { fixture.Owner = owner with { Generation = owner.Generation + 1 }; return account; };
            wire["retiredDuringRead"] = fixture.Send();
            fixture.Store.ResolveOwner = null; fixture.Owner = owner;
            var resolutions = 0;
            fixture.Store.ResolveOwner = account => ++resolutions == 1 ? account : account with { Subject = "other-local-owner" };
            wire["storageOwnerRetired"] = fixture.Send();
            fixture.Store.ResolveOwner = null;
        }
        Require(File.ReadAllBytes(fixture.FilePath).SequenceEqual(original), "Busy reads/writes must preserve every byte.");
        wire["recovered"] = fixture.Send();
        foreach (var key in new[] { "malformed", "ownerMismatch", "integrity" })
        {
            try
            {
                var node = JsonNode.Parse(original)!.AsObject();
                if (key == "ownerMismatch") node["OwnerHash"] = new string('F', 64);
                if (key == "integrity") node["Integrity"] = new string('0', 64);
                File.WriteAllText(fixture.FilePath, key == "malformed" ? "{invalid" : node.ToJsonString());
                var broken = File.ReadAllBytes(fixture.FilePath);
                wire[key] = fixture.Send();
                Require(File.ReadAllBytes(fixture.FilePath).SequenceEqual(broken), "Rejected reads must not repair corrupt files.");
            }
            finally { File.WriteAllBytes(fixture.FilePath, original); }
        }
        var savedPath = fixture.FilePath + ".fixture";
        fixture.CheckOwned(savedPath);
        File.Move(fixture.FilePath, savedPath);
        try
        {
            wire["absent"] = fixture.Send();
            Directory.CreateDirectory(fixture.FilePath);
            try { wire["fileKind"] = fixture.Send(); }
            finally { Directory.Delete(fixture.FilePath, false); }
        }
        finally { File.Move(savedPath, fixture.FilePath); }
        var directory = Path.GetDirectoryName(fixture.FilePath)!;
        var movedDirectory = directory + ".fixture";
        fixture.CheckOwned(directory); fixture.CheckOwned(movedDirectory);
        Directory.Move(directory, movedDirectory);
        try { File.WriteAllText(directory, "not a directory"); wire["directoryKind"] = fixture.Send(); }
        finally { File.Delete(directory); Directory.Move(movedDirectory, directory); }
        var info = new FileInfo(fixture.FilePath);
        var descriptor = info.GetAccessControl(AccessControlSections.Access).GetSecurityDescriptorBinaryForm();
        var security = new FileSecurity();
        security.SetSecurityDescriptorBinaryForm(descriptor, AccessControlSections.Access);
        var denied = new FileSecurity();
        denied.SetSecurityDescriptorBinaryForm(descriptor, AccessControlSections.Access);
        using (var identity = WindowsIdentity.GetCurrent())
        {
            denied.AddAccessRule(new FileSystemAccessRule(identity.User!, FileSystemRights.ReadData, AccessControlType.Deny));
            try { info.SetAccessControl(denied); wire["permission"] = fixture.Send(); }
            finally { info.SetAccessControl(security); }
        }
        Require(File.ReadAllBytes(fixture.FilePath).SequenceEqual(original), "The complete fault matrix must preserve original storage.");
        return wire;
    }

    private static void Require(bool condition, string message) { if (!condition) throw new Exception(message); }

    private sealed class Fixture : IDisposable
    {
        private readonly DirectoryInfo _root = Directory.CreateTempSubdirectory("sb-hangar-read-failure-");
        private readonly HangarReaderDispatcher _dispatcher;
        public HangarAccountIdentity Owner = new(new("development", "synthetic-issuer", "synthetic-hangar-read"), 7,
            new(ScmGameIdentityStatus.Verified, "SyntheticPilot", "syntheticpilot"));
        public LocalHangarStore Store { get; }
        public string FilePath { get; }
        public string ShipId { get; }
        public Fixture()
        {
            Store = new(_root.FullName);
            ShipId = Store.Save(Owner.Account, 0, "synthetic-read-failure-seed",
                [new("synthetic-pledge", 0, "Carrack", "Anvil", null)], false, false).Ships.Single().Id;
            FilePath = Directory.GetFiles(Path.Combine(_root.FullName, "hangar-local-v1"), "*.json").Single();
            _dispatcher = new(() => Owner, Store);
            CheckOwned(FilePath);
        }
        public void CheckOwned(string path) => Require(
            Path.GetFullPath(path).StartsWith(_root.FullName + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase),
            "Fixture paths must stay under the dedicated test directory before moving fault fixtures.");
        public BridgeEnvelope Send(string action = "inventory", JsonObject? payload = null,
            BridgeAccountContext? context = null, long? generation = null)
        {
            payload ??= new(); payload["schemaVersion"] = 1;
            return _dispatcher.Dispatch(BridgeEnvelope.Request("hangarReader." + action, Guid.NewGuid().ToString("N"),
                generation ?? Owner.Generation, payload, context ?? Owner.Account)).Response;
        }
        public void Dispose()
        {
            _dispatcher.Dispose();
            var target = Path.GetFullPath(_root.FullName);
            Require(_root.Name.StartsWith("sb-hangar-read-failure-", StringComparison.Ordinal) &&
                string.Equals(Path.GetDirectoryName(target), Path.TrimEndingDirectorySeparator(Path.GetFullPath(Path.GetTempPath())), StringComparison.OrdinalIgnoreCase),
                "Recursive fixture cleanup must remain in its explicitly created temporary directory.");
            if (Directory.Exists(target)) Directory.Delete(target, true);
        }
    }
}
