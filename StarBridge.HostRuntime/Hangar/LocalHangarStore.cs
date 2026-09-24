using System.Security.Cryptography;
using System.Text.Json;
using System.Text;
using System.Text.Json.Serialization;
using StarBridge.Core.Hangar;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Hangar;

/// <summary>
/// Owns only hangar-local-v1 beneath the injected root; never reads or promotes legacy files.
/// Owner dimensions are exact, authenticated Host input. Titles/liners match by Unicode NFC,
/// collapsed whitespace and invariant case; opaque pledge keys never normalize. Full saves
/// replace, partial saves retain every previous instance. Latest-operation retries require
/// identical content and base revision; older base revisions conflict. Limits: Core's total
/// item bound, 16 MiB UTF-8 JSON, depth 16, 1024-character observed fields, 256-character
/// operation IDs and 2048-character owner dimensions. Checksums detect corruption, not a
/// malicious local writer. The caller owns authentication and scan completeness/confirmation.
/// </summary>
public sealed class LocalHangarStore
{
    private readonly string _directory;
    private const int MaximumBytes = 16 * 1024 * 1024;
    private const int MaximumShips = HangarScanSession.MaximumTotalItems;
    private static readonly JsonSerializerOptions Json = new()
    {
        UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow,
        MaxDepth = 16
    };

    public LocalHangarStore(string root) => _directory = Path.Combine(Path.GetFullPath(root), "hangar-local-v1");

    public LocalHangarSnapshot Read(BridgeAccountContext owner) => ReadFile(owner)?.Snapshot ?? new(0, null, null, Array.Empty<LocalHangarShip>());

    private SavedFile? ReadFile(BridgeAccountContext owner)
    {
        var ownerHash = OwnerHash(owner);
        try
        {
            if (!CheckDirectory() || !CheckFile(GetPath(owner))) return null;
            using var stream = new FileStream(GetPath(owner), FileMode.Open, FileAccess.Read, FileShare.Read | FileShare.Delete);
            if (stream.Length is <= 0 or > MaximumBytes) throw new InvalidDataException("Invalid file size.");
            var bytes = new byte[(int)stream.Length];
            stream.ReadExactly(bytes);
            if (stream.ReadByte() != -1) throw new InvalidDataException("File length changed.");
            using var document = JsonDocument.Parse(bytes, new JsonDocumentOptions { MaxDepth = 16 });
            RejectDuplicateProperties(document.RootElement);
            var envelope = JsonSerializer.Deserialize<Envelope>(bytes, Json);
            if (envelope is null || envelope.SchemaVersion != 1 || envelope.OwnerHash != ownerHash ||
                envelope.Data is null || envelope.Integrity != Integrity(ownerHash, envelope.Data))
                throw new InvalidDataException("Invalid schema, ownership or integrity.");
            ValidateFile(envelope.Data);
            return envelope.Data;
        }
        catch (Exception error) when (IsStorageError(error))
        {
            throw new LocalHangarStoreException("hangar.storage_read_failed", "The local hangar could not be read safely.", error);
        }
    }

    public LocalHangarSnapshot Save(BridgeAccountContext owner, long expectedRevision, string operationId,
        IReadOnlyList<CollectedHangarShip> observations, bool partial, bool confirmEmpty, Func<bool>? canCommit = null)
    {
        _ = OwnerHash(owner);
        if (expectedRevision < 0 || expectedRevision == long.MaxValue || !ValidText(operationId, 256) || observations is null ||
            observations.Count > MaximumShips || observations.Any(s => s is null || !ValidText(s.PledgeKey) ||
                !ValidText(s.Title) || !ValidOptionalText(s.Liner) || !ValidOptionalText(s.AcquiredText)))
            throw new LocalHangarStoreException("hangar.invalid_request", "Invalid or oversized local hangar save request.");
        observations = observations.ToArray();
        var requestHash = Hash(JsonSerializer.SerializeToUtf8Bytes(new { partial, confirmEmpty,
            observations = observations.Select(s => JsonSerializer.Serialize(new { s.PledgeKey, s.Title, s.Liner, s.AcquiredText }))
                .OrderBy(s => s, StringComparer.Ordinal).ToArray() }));
        // Preflight errors must not even create a new storage directory. Repeat under
        // the OS file lock: another process may have committed since this read.
        _ = Prepare(ReadFile(owner), expectedRevision, operationId, observations, partial, confirmEmpty, requestHash);
        try
        {
            CheckDirectory();
            Directory.CreateDirectory(_directory);
            var path = GetPath(owner);
            CheckFile(path + ".lock");
            // Keep this file permanently: unlinking a lock can create two lock owners.
            using var writeLock = new FileStream(path + ".lock", FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
            var current = ReadFile(owner);
            var next = Prepare(current, expectedRevision, operationId, observations, partial, confirmEmpty, requestHash);
            if (ReferenceEquals(next, current))
            {
                CheckCanCommit(canCommit);
                return next.Snapshot;
            }
            var bytes = JsonSerializer.SerializeToUtf8Bytes(new Envelope(1, OwnerHash(owner), next, Integrity(OwnerHash(owner), next)), Json);
            if (bytes.Length > MaximumBytes) throw new InvalidDataException("The saved hangar exceeds the storage limit.");
            Commit(path, bytes, current is not null, canCommit);
            return next.Snapshot;
        }
        catch (Exception error) when (IsStorageError(error))
        {
            throw new LocalHangarStoreException("hangar.storage_write_failed", "The local hangar could not be saved safely.", error);
        }
    }

    private static SavedFile Prepare(SavedFile? file, long expectedRevision, string operationId,
        IReadOnlyList<CollectedHangarShip> observations, bool partial, bool confirmEmpty, string requestHash)
    {
        var current = file?.Snapshot ?? new(0, null, null, Array.Empty<LocalHangarShip>());
        if (current.OperationId == operationId)
        {
            if (file!.ExpectedRevision == expectedRevision && file.RequestHash == requestHash) return file;
            throw new LocalHangarStoreException("hangar.revision_conflict", "The operation ID was already used with a different request.");
        }
        if (current.Revision != expectedRevision)
            throw new LocalHangarStoreException("hangar.revision_conflict", "The hangar changed; read the current snapshot before saving.");
        if (observations.Count == 0 && (partial || !confirmEmpty))
            throw new LocalHangarStoreException("hangar.empty_confirmation_required", "A complete empty hangar requires explicit confirmation.");
        var now = DateTimeOffset.UtcNow;
        if (current.SavedAt > now) now = current.SavedAt.Value;
        var known = current.Ships.GroupBy(s => MatchKey(s.PledgeKey, s.Title, s.Liner))
            .ToDictionary(g => g.Key, g => new Queue<LocalHangarShip>(g));
        // An exact, unique pledge instance can return. A same-model purchase
        // under a different pledge remains a different ship.
        var observationCounts = observations.GroupBy(s => MatchKey(s.PledgeKey, s.Title, s.Liner)).ToDictionary(g => g.Key, g => g.Count());
        foreach (var group in (current.FormerShips ?? []).GroupBy(s => MatchKey(s.PledgeKey, s.Title, s.Liner)))
            if (group.Count() == 1 && !known.ContainsKey(group.Key) &&
                observationCounts.GetValueOrDefault(group.Key) == 1)
                known.Add(group.Key, new Queue<LocalHangarShip>(group));
        foreach (var observed in observations.GroupBy(s => MatchKey(s.PledgeKey, s.Title, s.Liner)))
        {
            if (known.TryGetValue(observed.Key, out var previous) && previous.Count != observed.Count())
                throw new LocalHangarStoreException("hangar.ambiguous_instances", "Changed multiplicity cannot identify individual pledge children.");
            if (previous is { Count: > 1 } && previous.Select(s => (s.CustomImagePath, s.CustomImageCrop)).Distinct().Count() != 1)
                throw new LocalHangarStoreException("hangar.ambiguous_instances", "Distinct custom fields cannot be assigned to unverified pledge children.");
        }
        var duplicateGroups = known.Where(g => g.Value.Count > 1).Select(g => g.Key).ToHashSet();
        // Equal duplicate groups provide multiset evidence, NOT verified child IDs.
        // Preserve the entire existing group without mapping per-child observations.
        // ItemIndex is intentionally absent from matching and request fingerprints.
        var ships = observations.Select(ship => known.TryGetValue(MatchKey(ship.PledgeKey, ship.Title, ship.Liner), out var group) && group.Count > 0
            ? duplicateGroups.Contains(MatchKey(ship.PledgeKey, ship.Title, ship.Liner)) ? group.Dequeue()
                : group.Dequeue() with { Title = ship.Title, Liner = ship.Liner, AcquiredText = ship.AcquiredText, RemovedAt = null }
            : new LocalHangarShip(Guid.NewGuid().ToString("N"), ship.PledgeKey, ship.Title, ship.Liner, ship.AcquiredText, now)).ToArray();
        if (partial)
        {
            var observedIds = ships.Select(s => s.Id).ToHashSet(StringComparer.Ordinal);
            ships = ships.Concat(current.Ships.Where(s => !observedIds.Contains(s.Id))).ToArray();
        }
        // History commits atomically with the confirmed inventory. Partial scans
        // retain current instances and cannot establish a removal. Never merge by model.
        var retained = ships.Select(s => s.Id).ToHashSet(StringComparer.Ordinal);
        var former = (current.FormerShips ?? []).Where(s => !retained.Contains(s.Id))
            .Concat(current.Ships.Where(s => !retained.Contains(s.Id)).Select(s => s with { RemovedAt = now })).ToArray();
        var saved = new LocalHangarSnapshot(current.Revision + 1, now, operationId, Array.AsReadOnly(ships), partial,
            former.Length == 0 ? null : Array.AsReadOnly(former));
        var data = new SavedFile(saved, expectedRevision, requestHash);
        if (ships.Length > MaximumShips || former.Length > MaximumShips)
            throw new LocalHangarStoreException("hangar.storage_write_failed", "The merged hangar exceeds the storage limit.");
        return data;
    }

    private void Commit(string path, byte[] bytes, bool replacing, Func<bool>? canCommit)
    {
        var temporary = Path.Combine(_directory, $"{Path.GetFileName(path)}.{Guid.NewGuid():N}.tmp");
        var temporaryCreated = false;
        try
        {
            using (var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None, 4096, FileOptions.WriteThrough))
            {
                temporaryCreated = true;
                stream.Write(bytes);
                stream.Flush(flushToDisk: true);
            }
            CheckDirectory();
            CheckFile(path);
            // The caller supplies a synchronous session/cancellation check. It owns
            // serialization of account transitions; this callback does not authenticate.
            CheckCanCommit(canCommit);
            if (replacing) File.Replace(temporary, path, null);
            else File.Move(temporary, path);
        }
        finally
        {
            try { if (temporaryCreated) File.Delete(temporary); }
            catch (Exception error) when (IsStorageError(error)) { /* Never mask the commit result. */ }
        }
    }

    private static void CheckCanCommit(Func<bool>? canCommit)
    {
        if (canCommit is null) return;
        bool allowed;
        try { allowed = canCommit(); }
        catch (Exception error)
        {
            throw new LocalHangarStoreException("hangar.account_changed", "The bound account or operation is no longer current.", error);
        }
        if (!allowed) throw new LocalHangarStoreException("hangar.account_changed", "The bound account or operation is no longer current.");
    }

    private static (string Pledge, string Title, string Liner) MatchKey(string pledge, string title, string? liner) =>
        (pledge, Normalize(title), Normalize(liner ?? ""));

    private static string Normalize(string value) =>
        string.Join(" ", value.Normalize(NormalizationForm.FormC).Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries)).ToUpperInvariant();

    private static void ValidateFile(SavedFile file)
    {
        var snapshot = file.Snapshot;
        if (snapshot is null || file.ExpectedRevision < 0 || file.ExpectedRevision == long.MaxValue ||
            snapshot.Revision != file.ExpectedRevision + 1 || !IsHash(file.RequestHash) ||
            !ValidText(snapshot.OperationId, 256) || snapshot.SavedAt is null ||
            snapshot.SavedAt < DateTimeOffset.UnixEpoch || snapshot.SavedAt.Value.Offset != TimeSpan.Zero ||
            snapshot.Ships is null || snapshot.Ships.Count > MaximumShips ||
            snapshot.FormerShips?.Count > MaximumShips || snapshot.Partial && snapshot.Ships.Count == 0)
            throw new InvalidDataException("Invalid saved snapshot.");
        var ids = new HashSet<string>(StringComparer.Ordinal);
        foreach (var ship in snapshot.Ships.Concat(snapshot.FormerShips ?? []))
        {
            if (ship is null || !Guid.TryParseExact(ship.Id, "N", out var id) || ship.Id != id.ToString("N") ||
                !ids.Add(ship.Id) || !ValidText(ship.PledgeKey) || !ValidText(ship.Title) ||
                !ValidOptionalText(ship.Liner) || !ValidOptionalText(ship.AcquiredText) ||
                ship.CustomImagePath is not null && !ValidText(ship.CustomImagePath, 2048) || !ValidCrop(ship.CustomImageCrop) ||
                ship.RemovedAt is { } removed && (removed < ship.AddedAt || removed > snapshot.SavedAt || removed.Offset != TimeSpan.Zero) ||
                ship.AddedAt < DateTimeOffset.UnixEpoch || ship.AddedAt > snapshot.SavedAt || ship.AddedAt.Offset != TimeSpan.Zero)
                throw new InvalidDataException("Invalid saved ship.");
        }
    }

    private static bool ValidCrop(LocalHangarImageCrop? crop) => crop is null ||
        double.IsFinite(crop.X) && double.IsFinite(crop.Y) && double.IsFinite(crop.Width) && double.IsFinite(crop.Height) &&
        crop.X >= 0 && crop.Y >= 0 && crop.Width > 0 && crop.Height > 0 && crop.X + crop.Width <= 1 && crop.Y + crop.Height <= 1;

    private bool CheckDirectory()
    {
        var chain = new Stack<string>();
        for (var item = new DirectoryInfo(_directory); item is not null; item = item.Parent) chain.Push(item.FullName);
        foreach (var path in chain)
        {
            var attributes = Attributes(path);
            if (attributes is null) return false;
            if ((attributes & FileAttributes.ReparsePoint) != 0 || (attributes & FileAttributes.Directory) == 0)
                throw new IOException("Storage directory must not redirect to another location.");
        }
        return true;
    }

    private static bool CheckFile(string path)
    {
        var attributes = Attributes(path);
        if (attributes is null) return false;
        if ((attributes & (FileAttributes.ReparsePoint | FileAttributes.Directory)) != 0)
            throw new IOException("Storage file must be a regular file.");
        return true;
    }

    private static FileAttributes? Attributes(string path)
    {
        try { return File.GetAttributes(path); }
        catch (FileNotFoundException) { return null; }
        catch (DirectoryNotFoundException) { return null; }
    }

    private static void RejectDuplicateProperties(JsonElement value)
    {
        if (value.ValueKind == JsonValueKind.Object)
        {
            var names = new HashSet<string>(StringComparer.Ordinal);
            foreach (var property in value.EnumerateObject())
            {
                if (!names.Add(property.Name)) throw new InvalidDataException("Duplicate JSON property.");
                RejectDuplicateProperties(property.Value);
            }
        }
        else if (value.ValueKind == JsonValueKind.Array)
            foreach (var item in value.EnumerateArray()) RejectDuplicateProperties(item);
    }

    private static bool ValidText(string? text, int maximum = 1024) =>
        !string.IsNullOrWhiteSpace(text) && text.Length <= maximum && ValidCharacters(text);
    private static bool ValidOptionalText(string? text) => text is null || text.Length <= 1024 && ValidCharacters(text);
    private static bool ValidCharacters(string value)
    {
        for (var i = 0; i < value.Length; i++)
        {
            if (char.IsControl(value[i])) return false;
            if (char.IsHighSurrogate(value[i]))
            {
                if (++i == value.Length || !char.IsLowSurrogate(value[i])) return false;
            }
            else if (char.IsLowSurrogate(value[i])) return false;
        }
        return true;
    }
    private static bool IsHash(string? hash) => hash is { Length: 64 } && hash.All(c => c is >= '0' and <= '9' or >= 'A' and <= 'F');
    private static bool IsStorageError(Exception error) => error is IOException or InvalidDataException or UnauthorizedAccessException or
        System.Security.SecurityException or JsonException or ArgumentException or NotSupportedException;
    private static string Integrity(string ownerHash, SavedFile data) =>
        Hash(JsonSerializer.SerializeToUtf8Bytes(new { SchemaVersion = 1, OwnerHash = ownerHash, Data = data }, Json));
    private sealed record Envelope([property: JsonRequired] int SchemaVersion, [property: JsonRequired] string OwnerHash,
        [property: JsonRequired] SavedFile Data, [property: JsonRequired] string Integrity);
    private sealed record SavedFile([property: JsonRequired] LocalHangarSnapshot Snapshot,
        [property: JsonRequired] long ExpectedRevision, [property: JsonRequired] string RequestHash);
    private static string Hash(byte[] bytes) => Convert.ToHexString(SHA256.HashData(bytes));
    private static string OwnerHash(BridgeAccountContext owner)
    {
        if (owner is null || !ValidText(owner.Environment, 2048) || !ValidText(owner.Authority, 2048) || !ValidText(owner.Subject, 2048))
            throw new LocalHangarStoreException("hangar.invalid_request", "A complete authenticated owner is required.");
        // JSON dimensions avoid delimiter collisions. Identity casing is never normalized.
        return Hash(JsonSerializer.SerializeToUtf8Bytes(new[] { owner.Environment, owner.Authority, owner.Subject }));
    }
    private string GetPath(BridgeAccountContext owner) => Path.Combine(_directory, OwnerHash(owner) + ".json");
}
