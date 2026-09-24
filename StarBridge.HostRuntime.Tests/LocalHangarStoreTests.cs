using StarBridge.Core.Hangar;
using StarBridge.HostRuntime.Hangar;
using StarBridge.NativeBridge;
using System.Text;
using System.Text.Json.Nodes;
using System.Text.Json;
using System.Security.Cryptography;
using System.Diagnostics;
using System.Security.AccessControl;
using System.Security.Principal;

internal static class LocalHangarStoreTests
{
    public static Task Verify()
    {
        FirstSaveReopens();
        FormerOwnershipSurvivesAndRemainsInstanceScoped();
        ReorderedMultisetsKeepInstances();
        PartialIsAdditiveAndEmptyNeedsConfirmation();
        RevisionAndRetryAreConditional();
        ChangedDuplicateCountsAreAmbiguous();
        DamagedStorageCannotBeReadOrOverwritten();
        InvalidRequestsDoNotCreateStorage();
        CommitGuardAndFailedWritersPreserveSnapshot();
        CustomFieldsRequireUnambiguousInstances();
        OwnersAreIsolatedWithoutRawIdentityPaths();
        StrictSnapshotValidation();
        AnotherProcessCannotWriteWhileLocked();
        PermissionFailuresPreserveSnapshot();
        CapacityAndPartialCancellationPreserveSnapshot();
        return Task.CompletedTask;
    }

    private static void FormerOwnershipSurvivesAndRemainsInstanceScoped()
    {
        using var test = new Fixture();
        var store = new LocalHangarStore(test.Root);
        var first = store.Save(Owner, 0, "history-first", [Ship("a", 0, "Carrack"), Ship("b", 0, "Carrack")], false, false);
        var id = first.Ships.Single(s => s.PledgeKey == "a").Id;
        var partial = store.Save(Owner, 1, "history-partial", [Ship("b", 0, "Carrack")], true, false);
        Require(partial.Ships.Count == 2 && partial.FormerShips is null, "Partial scan never archives missing ships.");
        var removed = store.Save(Owner, 2, "history-remove", [Ship("b", 0, "Carrack")], false, false);
        Require(removed.FormerShips!.Single().Id == id && removed.Ships.Single().Id != id, "Same model instances remain distinct.");
        Require(removed.FormerShips!.Single().RemovedAt == removed.SavedAt, "Removal time belongs to the confirming save.");
        Require(new LocalHangarStore(test.Root).Read(Owner).FormerShips!.Single().Id == id, "History persists across restart.");
        var retry = store.Save(Owner, 2, "history-remove", [Ship("b", 0, "Carrack")], false, false);
        Require(retry.FormerShips!.Count == 1, "Save retry does not duplicate history.");
        var returned = store.Save(Owner, 3, "history-return", [Ship("a", 0, "Carrack"), Ship("c", 0, "Carrack")], false, false);
        Require(returned.Ships.Single(s => s.PledgeKey == "a").Id == id && returned.FormerShips!.Single().PledgeKey == "b",
            "Only exact verified pledge identity returns; another purchase is independent.");
        Require(returned.Ships.All(s => s.RemovedAt is null), "Reowned instances clear their removal timestamp.");
        store.Save(Owner, 4, "history-empty", [], false, true);
        var empty = store.Read(Owner);
        Require(empty.Ships.Count == 0 && empty.FormerShips!.Count == 3, "Confirmed empty keeps all former instances.");
        Require(store.Read(Owner with { Subject = "other-history-owner" }).FormerShips is null, "History is account isolated.");
    }

    private static void FirstSaveReopens()
    {
        using var test = new Fixture();
        var store = new LocalHangarStore(test.Root);
        var empty = store.Read(Owner);
        Require(empty.Revision == 0 && empty.SavedAt is null && empty.OperationId is null && empty.Ships.Count == 0,
            "A never-saved owner has an unsaved empty snapshot.");
        var saved = store.Save(Owner, 0, "first", [Ship("pledge-a", 0, "Carrack")], false, false);
        var reopened = new LocalHangarStore(test.Root).Read(Owner);
        Require(reopened.Revision == 1 && reopened.OperationId == "first" && reopened.SavedAt == saved.SavedAt &&
            reopened.SavedAt is not null && !reopened.Partial && reopened.Ships.SequenceEqual(saved.Ships) &&
            reopened.Ships.Count == 1 && reopened.Ships[0].Id.Length > 0 && reopened.Ships[0].Title == "Carrack",
            "The first save must survive a new store instance.");
    }

    private static void ReorderedMultisetsKeepInstances()
    {
        using var test = new Fixture();
        var store = new LocalHangarStore(test.Root);
        CollectedHangarShip[] original = [Ship("pack", 0, "Carrack", "Anvil"), Ship("pack", 1, "Carrack", "Anvil"),
            Ship("pack", 2, "Vulture"), Ship("other", 0, "Carrack", "Anvil"), Ship("pack", 3, "Carrack", "Different")];
        var first = store.Save(Owner, 0, "one", original, false, false);
        var reordered = original.Reverse().Select((s, i) => s with { ItemIndex = i + 10 }).ToArray();
        var second = store.Save(Owner, 1, "two", reordered, false, false);
        Require(first.Ships.OrderBy(s => s.Id).SequenceEqual(second.Ships.OrderBy(s => s.Id)),
            "Reordered child items and duplicate models must preserve every instance and AddedAt.");
        var normalized = store.Save(Owner, 2, "three", [Ship("other", 42, "  CARRACK  ", " anvil ")], false, false);
        Require(first.Ships.Single(s => s.PledgeKey == "other").Id == normalized.Ships.Single().Id,
            "Exact normalized model/liner matches only within its pledge.");
        var moved = store.Save(Owner, 3, "four", [Ship("new-pledge", 0, "Carrack", "Anvil")], false, false);
        Require(first.Ships.All(s => s.Id != moved.Ships.Single().Id), "Matching must never cross pledges.");
    }

    private static void PartialIsAdditiveAndEmptyNeedsConfirmation()
    {
        using var test = new Fixture();
        var store = new LocalHangarStore(test.Root);
        var first = store.Save(Owner, 0, "one", [Ship("a", 0, "Carrack"), Ship("b", 0, "Vulture")], false, false);
        var partial = store.Save(Owner, 1, "two", [Ship("a", 99, "Carrack"), Ship("new", 0, "Unknown Future Ship")], true, false);
        Require(partial.Partial && partial.Ships.Count == 3 && first.Ships.All(s => partial.Ships.Contains(s)) &&
            partial.Ships.Any(s => s.Title == "Unknown Future Ship"), "Partial results preserve all old records and unknown models.");
        Expect("hangar.empty_confirmation_required", () => store.Save(Owner, 2, "zero-partial", [], true, true));
        Expect("hangar.empty_confirmation_required", () => store.Save(Owner, 2, "zero-full", [], false, false));
        Require(store.Read(Owner).Revision == 2, "Rejected empty operations must not mutate the snapshot.");
        var empty = store.Save(Owner, 2, "empty", [], false, true);
        Require(empty.Revision == 3 && !empty.Partial && empty.Ships.Count == 0, "Explicit full empty confirmation replaces the snapshot.");
    }

    private static void RevisionAndRetryAreConditional()
    {
        using var test = new Fixture();
        var store = new LocalHangarStore(test.Root);
        CollectedHangarShip[] ships = [Ship("a", 0, "Carrack")];
        var saved = store.Save(Owner, 0, "retry", ships, false, false);
        var retried = new LocalHangarStore(test.Root).Save(Owner, 0, "retry", ships, false, false);
        Require(retried.Revision == saved.Revision && retried.SavedAt == saved.SavedAt && retried.Ships.SequenceEqual(saved.Ships),
            "A successful operation retried after reopen returns the saved result before checking its old base revision.");
        Expect("hangar.revision_conflict", () => store.Save(Owner, 0, "other", ships, false, false));
        Expect("hangar.revision_conflict", () => store.Save(Owner, 1, "retry", ships, false, false));
        Expect("hangar.revision_conflict", () => store.Save(Owner, 0, "retry", [Ship("b", 0, "Vulture")], false, false));
        Require(store.Read(Owner).Revision == 1, "Conflicts must leave the saved revision intact.");
    }

    private static void ChangedDuplicateCountsAreAmbiguous()
    {
        using var test = new Fixture();
        var store = new LocalHangarStore(test.Root);
        var saved = store.Save(Owner, 0, "duplicates", [Ship("pack", 0, "Carrack"), Ship("pack", 1, "Carrack")], false, false);
        foreach (var partial in new[] { false, true })
        {
            Expect("hangar.ambiguous_instances", () => store.Save(Owner, 1, "reduce", [Ship("pack", 7, "Carrack")], partial, false));
            Expect("hangar.ambiguous_instances", () => store.Save(Owner, 1, "increase",
                [Ship("pack", 0, "Carrack"), Ship("pack", 1, "Carrack"), Ship("pack", 2, "Carrack")], partial, false));
        }
        Require(store.Read(Owner).Ships.SequenceEqual(saved.Ships), "Ambiguous duplicate changes preserve every old instance.");
    }

    private static void DamagedStorageCannotBeReadOrOverwritten()
    {
        using var test = new Fixture();
        var store = new LocalHangarStore(test.Root);
        store.Save(Owner, 0, "valid", [Ship("a", 0, "Unknown Ship")], false, false);
        var path = Directory.GetFiles(Path.Combine(test.Root, "hangar-local-v1"), "*.json").Single();
        var valid = File.ReadAllText(path);
        var wrongSchema = JsonNode.Parse(valid)!;
        wrongSchema["SchemaVersion"] = 999;
        var wrongOwner = JsonNode.Parse(valid)!;
        wrongOwner["OwnerHash"] = new string('0', 64);
        var unknownProperty = JsonNode.Parse(valid)!;
        unknownProperty["Unexpected"] = true;
        foreach (var damaged in new[] { "{", "null", "{}", wrongSchema.ToJsonString(), wrongOwner.ToJsonString(),
            unknownProperty.ToJsonString(), valid.Replace("Unknown Ship", "Tampered Ship", StringComparison.Ordinal),
            "{\"SchemaVersion\":1," + valid[1..], new string(' ', 16 * 1024 * 1024 + 1) })
        {
            File.WriteAllText(path, damaged, new UTF8Encoding(false));
            Expect("hangar.storage_read_failed", () => store.Read(Owner));
            Expect("hangar.storage_read_failed", () => store.Save(Owner, 1, "overwrite", [Ship("b", 0, "Vulture")], false, false));
            Require(File.ReadAllText(path) == damaged, "Invalid or corrupt bytes must never be overwritten.");
        }
    }

    private static void InvalidRequestsDoNotCreateStorage()
    {
        using var test = new Fixture();
        var store = new LocalHangarStore(test.Root);
        Expect("hangar.invalid_request", () => store.Save(Owner, -1, "bad", [Ship("a", 0, "Carrack")], false, false));
        Expect("hangar.invalid_request", () => store.Save(Owner, 0, " ", [Ship("a", 0, "Carrack")], false, false));
        foreach (var observations in new IReadOnlyList<CollectedHangarShip>[] { null!, [null!], [Ship("", 0, "Carrack")],
            [Ship("a", 0, "")], [Ship("a", 0, new string('x', 1025))], [Ship("a", 0, "\uD800")],
            Enumerable.Repeat(Ship("a", 0, "Carrack"), 20001).ToArray() })
            Expect("hangar.invalid_request", () => store.Save(Owner, 0, "bad", observations, false, false));
        Expect("hangar.invalid_request", () => store.Read(Owner with { Subject = "" }));
        Require(!Directory.Exists(test.Root), "Invalid requests must not create storage.");
    }

    private static void CommitGuardAndFailedWritersPreserveSnapshot()
    {
        using var test = new Fixture();
        var store = new LocalHangarStore(test.Root);
        var saved = store.Save(Owner, 0, "original", [Ship("a", 0, "Carrack")], false, false);
        var folder = Path.Combine(test.Root, "hangar-local-v1");
        var path = Directory.GetFiles(folder, "*.json").Single();
        var original = File.ReadAllBytes(path);
        var guardCalls = 0;
        Exception? guardFailure = null;
        Expect("hangar.account_changed", () => store.Save(Owner, 1, "cancelled", [Ship("b", 0, "Vulture")], false, false, () =>
        {
            guardCalls++;
            try
            {
                Require(new LocalHangarStore(test.Root).Read(Owner).Ships.SequenceEqual(saved.Ships), "Old snapshot is visible until commit.");
                Expect("hangar.storage_write_failed", () => new LocalHangarStore(test.Root).Save(Owner, 1, "racer", [Ship("c", 0, "Nox")], false, false));
            }
            catch (Exception error) { guardFailure = error; }
            return false;
        }));
        Require(guardCalls == 1 && File.ReadAllBytes(path).SequenceEqual(original), "Cancellation is checked while holding the writer lock before replacement.");
        if (guardFailure is not null) throw new Exception("Commit guard lock checks failed.", guardFailure);
        using (var blocker = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read))
            Expect("hangar.storage_write_failed", () => store.Save(Owner, 1, "blocked", [Ship("b", 0, "Vulture")], false, false));
        using (var blocker = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.None))
        {
            Expect("hangar.storage_read_failed", () => store.Read(Owner));
            Expect("hangar.storage_read_failed", () => store.Save(Owner, 1, "unreadable", [Ship("b", 0, "Vulture")], false, false));
        }
        Require(File.ReadAllBytes(path).SequenceEqual(original) && Directory.GetFiles(folder, "*.tmp").Length == 0,
            "Failed replacement/read preserves original bytes and cleans only its own temporary file.");
        var next = store.Save(Owner, 1, "next", [Ship("b", 0, "Vulture")], false, false, () => true);
        Require(next.Revision == 2 && store.Read(Owner).Ships.Single().Title == "Vulture", "A later valid save can replace atomically.");
    }

    private static void CustomFieldsRequireUnambiguousInstances()
    {
        using var test = new Fixture();
        var store = new LocalHangarStore(test.Root);
        CollectedHangarShip[] observations = [Ship("pack", 0, "Carrack"), Ship("pack", 1, "Carrack"), Ship("single", 0, "Vulture")];
        store.Save(Owner, 0, "first", observations, false, false);
        var path = Directory.GetFiles(Path.Combine(test.Root, "hangar-local-v1"), "*.json").Single();
        RewriteSnapshot(path, s => s with { Ships = s.Ships.Select((ship, i) => i == 1 ? ship : ship with
            { CustomImagePath = "synthetic-image.png", CustomImageCrop = new(0.1, 0.2, 0.5, 0.5) }).ToArray() });
        var asymmetric = File.ReadAllBytes(path);
        Require(store.Read(Owner).Ships.Count == 3, "Valid persisted customization remains readable.");
        Expect("hangar.ambiguous_instances", () => store.Save(Owner, 1, "asymmetric", observations.Reverse().ToArray(), false, false));
        Require(File.ReadAllBytes(path).SequenceEqual(asymmetric), "Asymmetric per-instance fields block reassignment.");
        RewriteSnapshot(path, s => s with { Ships = s.Ships.Select(ship => ship with
            { CustomImagePath = "synthetic-image.png", CustomImageCrop = new(0.1, 0.2, 0.5, 0.5) }).ToArray() });
        var before = store.Read(Owner);
        var after = store.Save(Owner, 1, "symmetric", observations.Reverse().ToArray(), false, false);
        Require(after.Ships.OrderBy(s => s.Id).SequenceEqual(before.Ships.OrderBy(s => s.Id)),
            "Singleton customization and symmetric duplicate ID/custom-field multisets survive rescanning.");
    }

    // Fault/compatibility fixture authoring only; assertions use the public Read/Save seam.
    private static void RewriteSnapshot(string path, Func<LocalHangarSnapshot, LocalHangarSnapshot> transform)
    {
        var root = JsonNode.Parse(File.ReadAllText(path))!.AsObject();
        root["Data"]!["Snapshot"] = JsonSerializer.SerializeToNode(transform(root["Data"]!["Snapshot"]!.Deserialize<LocalHangarSnapshot>()!));
        var protectedData = new { SchemaVersion = root["SchemaVersion"]!.GetValue<int>(),
            OwnerHash = root["OwnerHash"]!.GetValue<string>(), Data = new {
                Snapshot = root["Data"]!["Snapshot"]!.Deserialize<LocalHangarSnapshot>(),
                ExpectedRevision = root["Data"]!["ExpectedRevision"]!.GetValue<long>(),
                RequestHash = root["Data"]!["RequestHash"]!.GetValue<string>() } };
        root["Integrity"] = Convert.ToHexString(SHA256.HashData(JsonSerializer.SerializeToUtf8Bytes(protectedData)));
        File.WriteAllText(path, root.ToJsonString(), new UTF8Encoding(false));
    }

    private static void OwnersAreIsolatedWithoutRawIdentityPaths()
    {
        using var test = new Fixture();
        var store = new LocalHangarStore(test.Root);
        BridgeAccountContext[] owners = [Owner, Owner with { Environment = "test" }, Owner with { Authority = "https://AUTHORITY.invalid" },
            Owner with { Subject = "Synthetic-Owner" }, new("a/b", "c", "d"), new("a", "b/c", "d")];
        for (var i = 0; i < owners.Length; i++)
        {
            Require(store.Read(owners[i]).Revision == 0, "Environment, authority and subject retain exact casing and independent dimensions.");
            store.Save(owners[i], 0, "same-operation", [Ship("p", 0, $"Synthetic Ship {i}")], false, false);
        }
        for (var i = 0; i < owners.Length; i++)
            Require(new LocalHangarStore(test.Root).Read(owners[i]).Ships.Single().Title == $"Synthetic Ship {i}", "Owners never share snapshots.");
        var files = Directory.GetFiles(Path.Combine(test.Root, "hangar-local-v1"), "*.json");
        Require(files.Length == owners.Length && files.All(p => Path.GetFileNameWithoutExtension(p).Length == 64 &&
            Path.GetFileNameWithoutExtension(p).All(Uri.IsHexDigit)), "Only hashed owner filenames are used.");
        var ownerPath = files.Single(p => File.ReadAllText(p).Contains("Synthetic Ship 0", StringComparison.Ordinal));
        var otherPath = files.Single(p => File.ReadAllText(p).Contains("Synthetic Ship 1", StringComparison.Ordinal));
        File.Copy(ownerPath, otherPath, true);
        Expect("hangar.storage_read_failed", () => store.Read(owners[1]));
    }

    private static void StrictSnapshotValidation()
    {
        using var test = new Fixture();
        var store = new LocalHangarStore(test.Root);
        store.Save(Owner, 0, "valid", [Ship("p", 0, "Unknown")], false, false);
        var path = Directory.GetFiles(Path.Combine(test.Root, "hangar-local-v1"), "*.json").Single();
        var original = File.ReadAllBytes(path);
        Func<LocalHangarSnapshot, LocalHangarSnapshot>[] invalid = [
            s => s with { Revision = 0 }, s => s with { SavedAt = null }, s => s with { OperationId = "" },
            s => s with { Ships = [s.Ships[0], s.Ships[0]] }, s => s with { Ships = null! },
            s => s with { Ships = [s.Ships[0] with { Title = "" }] },
            s => s with { Ships = [s.Ships[0] with { AddedAt = DateTimeOffset.MinValue }] },
            s => s with { Ships = [s.Ships[0] with { CustomImageCrop = new(0, 0, 2, 1) }] },
            s => s with { Partial = true, Ships = [] }];
        foreach (var transform in invalid)
        {
            File.WriteAllBytes(path, original);
            RewriteSnapshot(path, transform);
            var damaged = File.ReadAllBytes(path);
            Expect("hangar.storage_read_failed", () => store.Read(Owner));
            Expect("hangar.storage_read_failed", () => store.Save(Owner, 1, "overwrite", [Ship("b", 0, "Vulture")], true, false));
            Require(File.ReadAllBytes(path).SequenceEqual(damaged), "Even a valid checksum cannot authorize invalid snapshot fields.");
        }
    }

    private static void AnotherProcessCannotWriteWhileLocked()
    {
        if (!OperatingSystem.IsWindows()) return;
        using var test = new Fixture();
        var store = new LocalHangarStore(test.Root);
        store.Save(Owner, 0, "first", [Ship("p", 0, "Carrack")], false, false);
        var path = Directory.GetFiles(Path.Combine(test.Root, "hangar-local-v1"), "*.json").Single();
        var original = File.ReadAllBytes(path);
        var start = new ProcessStartInfo("powershell.exe") { UseShellExecute = false, CreateNoWindow = true,
            RedirectStandardInput = true, RedirectStandardOutput = true, RedirectStandardError = true };
        start.ArgumentList.Add("-NoProfile");
        start.ArgumentList.Add("-NonInteractive");
        start.ArgumentList.Add("-Command");
        var lockPath = (path + ".lock").Replace("'", "''", StringComparison.Ordinal);
        start.ArgumentList.Add($"$held = [IO.File]::Open('{lockPath}', [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None); try {{ [Console]::WriteLine('LOCKED'); [Console]::ReadLine() | Out-Null }} finally {{ $held.Dispose() }}");
        using var process = Process.Start(start) ?? throw new Exception("Could not start lock fixture.");
        try
        {
            Require(process.StandardOutput.ReadLineAsync().WaitAsync(TimeSpan.FromSeconds(10)).GetAwaiter().GetResult() == "LOCKED", "External process acquired the lock.");
            Expect("hangar.storage_write_failed", () => new LocalHangarStore(test.Root).Save(Owner, 1, "competing", [Ship("new", 0, "Nox")], true, false));
            Require(File.ReadAllBytes(path).SequenceEqual(original), "Cross-process write exclusion preserves the snapshot.");
        }
        finally
        {
            if (!process.HasExited) process.StandardInput.WriteLine("release");
            if (!process.WaitForExit(5000)) { process.Kill(entireProcessTree: true); process.WaitForExit(); }
        }
        Require(store.Save(Owner, 1, "after-release", [Ship("new", 0, "Nox")], true, false).Revision == 2, "Released locks allow later saves.");
    }

    private static void PermissionFailuresPreserveSnapshot()
    {
        if (!OperatingSystem.IsWindows()) return;
        using var test = new Fixture();
        var store = new LocalHangarStore(test.Root);
        store.Save(Owner, 0, "first", [Ship("p", 0, "Carrack")], false, false);
        var path = Directory.GetFiles(Path.Combine(test.Root, "hangar-local-v1"), "*.json").Single();
        var original = File.ReadAllBytes(path);
        using var identity = WindowsIdentity.GetCurrent();
        foreach (var (target, rights, code) in new[] { (path, FileSystemRights.ReadData, "hangar.storage_read_failed"),
            (path + ".lock", FileSystemRights.WriteData, "hangar.storage_write_failed") })
        {
            var info = new FileInfo(target);
            var descriptor = info.GetAccessControl(AccessControlSections.Access).GetSecurityDescriptorBinaryForm();
            var restore = new FileSecurity();
            restore.SetSecurityDescriptorBinaryForm(descriptor, AccessControlSections.Access);
            var denied = new FileSecurity();
            denied.SetSecurityDescriptorBinaryForm(descriptor, AccessControlSections.Access);
            denied.AddAccessRule(new FileSystemAccessRule(identity.User!, rights, AccessControlType.Deny));
            try
            {
                info.SetAccessControl(denied);
                if (target == path) Expect(code, () => store.Read(Owner));
                Expect(code, () => store.Save(Owner, 1, "denied", [Ship("new", 0, "Nox")], true, false));
            }
            finally { info.SetAccessControl(restore); }
            Require(File.ReadAllBytes(path).SequenceEqual(original), "Permission failures preserve original bytes.");
        }
    }

    private static void CapacityAndPartialCancellationPreserveSnapshot()
    {
        using var test = new Fixture();
        var store = new LocalHangarStore(test.Root);
        var observations = Enumerable.Range(0, HangarScanSession.MaximumTotalItems).Select(i => Ship($"p{i}", 0, "Unknown")).ToArray();
        var saved = store.Save(Owner, 0, "at-limit", observations, false, false);
        Require(saved.Ships.Count == 20_000 && new LocalHangarStore(test.Root).Read(Owner).Ships.Count == 20_000,
            "The full Core 20,000-item capacity is supported.");
        var path = Directory.GetFiles(Path.Combine(test.Root, "hangar-local-v1"), "*.json").Single();
        var original = File.ReadAllBytes(path);
        Expect("hangar.storage_write_failed", () => store.Save(Owner, 1, "merged-overflow", [Ship("extra", 0, "Nox")], true, false));
        Expect("hangar.account_changed", () => store.Save(Owner, 1, "partial-cancelled", [observations[0]], true, false, () => false));
        Expect("hangar.account_changed", () => store.Save(Owner, 1, "callback-threw", [observations[0]], true, false,
            () => throw new OperationCanceledException()));
        var oversized = observations.Take(9000).Select(s => s with { Title = new string('x', 1024), AcquiredText = new string('y', 1024) }).ToArray();
        Expect("hangar.storage_write_failed", () => store.Save(Owner, 1, "byte-overflow", oversized, false, false));
        Require(File.ReadAllBytes(path).SequenceEqual(original), "Partial cancellation, merged-count overflow and byte overflow preserve all original data.");
    }

    private static void Expect(string code, Action action)
    {
        try { action(); }
        catch (LocalHangarStoreException error) when (error.Code == code) { return; }
        throw new Exception($"Expected {code}.");
    }

    private static readonly BridgeAccountContext Owner = new("Test", "https://authority.invalid", "synthetic-owner");
    private static CollectedHangarShip Ship(string pledge, int index, string title, string? liner = null) =>
        new(pledge, index, title, liner, "synthetic acquisition");
    private static void Require(bool condition, string message)
    {
        if (!condition) throw new Exception(message);
    }

    private sealed class Fixture : IDisposable
    {
        public string Root { get; } = Path.Combine(Path.GetTempPath(), "starbridge-local-hangar-tests", Guid.NewGuid().ToString("N"));
        public void Dispose()
        {
            // Only this fixture's randomly named, synthetic directory is removed.
            if (Directory.Exists(Root)) Directory.Delete(Root, true);
        }
    }
}
