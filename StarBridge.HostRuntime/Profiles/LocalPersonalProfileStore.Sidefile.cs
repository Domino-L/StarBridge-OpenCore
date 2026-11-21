using System.Text.Json;
using System.Text.Json.Serialization;
using StarBridge.Core.Profiles;

namespace StarBridge.HostRuntime.Profiles;

public sealed partial class LocalPersonalProfileStore
{
    // Frozen 0.7.2.1 disk contract. New presentation fields belong in SideFile,
    // never in the main record or its checksum (old readers use Disallow).
    private sealed record MainContent(string CallSign, string Introduction, int AvatarStyle,
        string WallpaperId, IReadOnlyList<LocalProfileLayout> Modules, IReadOnlyList<string>? FavoriteShipIds,
        [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] LocalProfilePlayStyle? PlayStyle = null,
        [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] LocalProfileSchedule? Schedule = null,
        [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingDefault)] bool PreserveEmptyFields = false);
    private sealed record MainProfileSnapshot(long Revision, DateTimeOffset? SavedAt, string? OperationId, MainContent? Content);
    private sealed record MainFile(int SchemaVersion, string OwnerHash, MainProfileSnapshot Snapshot, string Integrity);
    private static MainProfileSnapshot MainSnapshot(LocalProfileSnapshot snapshot) => new(snapshot.Revision,
        snapshot.SavedAt, snapshot.OperationId, MainContentFor(snapshot.Content));
    private static MainContent? MainContentFor(LocalProfileContent? c) => c is null ? null : new(c.CallSign, c.Introduction,
        c.AvatarStyle, c.WallpaperId, c.Modules, c.FavoriteShipIds, c.PlayStyle, c.Schedule, c.PreserveEmptyFields);
    private static string MainIntegrity(string owner, MainProfileSnapshot snapshot) =>
        Hash(JsonSerializer.SerializeToUtf8Bytes(new { schemaVersion = 1, owner, snapshot }, Json));

    private sealed record SideFile(int SchemaVersion, string OwnerHash,
        IReadOnlyList<PersonalProfileShowcaseContract>? Showcases, IReadOnlyList<string>? AchievementShowcase, string Integrity,
        [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] string? OperationId = null,
        // 0.7.3 main role. Absent keeps the checksum of earlier sidefiles byte for byte.
        [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] string? MainRole = null);
    private string SidePath(string hash) => Path.Combine(_directory, hash + ".showcases");
    private static string SideIntegrity(string ownerHash, IReadOnlyList<PersonalProfileShowcaseContract>? showcases,
        IReadOnlyList<string>? achievementShowcase, string? operationId, string? mainRole = null) => operationId is null
        // Accept sidefiles from before operation IDs were added, with their exact checksum.
        ? Hash(JsonSerializer.SerializeToUtf8Bytes(new { schemaVersion = 1, ownerHash, showcases, achievementShowcase }, Json))
        : mainRole is null
        ? Hash(JsonSerializer.SerializeToUtf8Bytes(new { schemaVersion = 1, ownerHash, showcases, achievementShowcase, operationId }, Json))
        : Hash(JsonSerializer.SerializeToUtf8Bytes(
            new { schemaVersion = 1, ownerHash, showcases, achievementShowcase, operationId, mainRole }, Json));

    private LocalProfileSnapshot ReadShowcases(string hash, LocalProfileSnapshot snapshot,
        out (bool Readable, string? OperationId) showcase)
    {
        showcase = default;
        if (snapshot.Content is not { } content) return snapshot;
        try
        {
            var path = SidePath(hash);
            if (!CheckPath(path, false)) return snapshot;
            using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read | FileShare.Delete);
            if (stream.Length is <= 0 or > MaximumBytes) throw new IOException();
            var bytes = new byte[(int)stream.Length];
            stream.ReadExactly(bytes);
            if (stream.ReadByte() != -1) throw new IOException();
            using var doc = JsonDocument.Parse(bytes, new JsonDocumentOptions { MaxDepth = 12 });
            RejectDuplicates(doc.RootElement);
            var side = JsonSerializer.Deserialize<SideFile>(bytes, Json);
            if (side is null || side.SchemaVersion != 1 || side.OwnerHash != hash ||
                (side.OperationId is not null && !Guid.TryParseExact(side.OperationId, "N", out _)) ||
                (side.MainRole is not null && side.OperationId is null) ||
                side.Integrity != SideIntegrity(hash, side.Showcases, side.AchievementShowcase, side.OperationId, side.MainRole))
                throw new IOException();
            // Validate even fields masked by inline build 61 values before trusting
            // this file's operation ID as proof that its commit completed.
            Validate(content with { Showcases = side.Showcases, AchievementShowcase = side.AchievementShowcase });
            var combined = content with {
                Showcases = content.Showcases ?? side.Showcases,
                AchievementShowcase = content.AchievementShowcase ?? side.AchievementShowcase,
                // Main may be newer (an old-client edit dropped the role): keep it only while it is a role.
                MainRole = KeptMainRole(content.MainRole ?? side.MainRole, content.PlayStyle)
            };
            Validate(combined);
            showcase = (true, side.OperationId);
            // A sidefile may lag main after a failed save or an old-client edit.
            // Reads intentionally return new main + old side values, never reject
            // the side merely because its operation differs from main's.
            return snapshot with { Content = combined };
        }
        // No diagnostic facility exists in this store. Optional presentation
        // corruption must never turn a valid old main file into read_failed.
        catch (Exception e) when (StorageError(e) || e is LocalProfileException) { return snapshot; }
    }

    private static byte[] ShowcaseBytes(string hash, string operationId, LocalProfileContent content)
    {
        var mainRole = string.IsNullOrEmpty(content.MainRole) ? null : content.MainRole;
        var side = new SideFile(1, hash, content.Showcases, content.AchievementShowcase,
            SideIntegrity(hash, content.Showcases, content.AchievementShowcase, operationId, mainRole), operationId, mainRole);
        var bytes = JsonSerializer.SerializeToUtf8Bytes(side, Json);
        if (bytes.Length > MaximumBytes) throw new LocalProfileException("profile_local.invalid_request");
        return bytes;
    }

    // Save-only migration under path + ".lock", before the normal main-first
    // save. Read already merged each field (inline non-null, including [], wins).
    // Side failure leaves main intact; main failure leaves the original inline
    // main plus equivalent side values. Both failures preserve the read result.
    private void MigrateInline(string hash, LocalProfileSnapshot current, Func<bool> canCommit)
    {
        var disk = MainSnapshot(current);
        var bytes = JsonSerializer.SerializeToUtf8Bytes(new MainFile(1, hash, disk, MainIntegrity(hash, disk)), Json);
        if (bytes.Length > MaximumBytes) throw new LocalProfileException("profile_local.invalid_request");
        var sideBytes = ShowcaseBytes(hash, current.OperationId!, current.Content!);
        WriteAtomic(SidePath(hash), sideBytes, canCommit);
        // Revision, operationId and SavedAt belong to the old committed save.
        WriteAtomic(PathFor(hash), bytes, canCommit);
    }

    // Called only under the main file's existing write lock; every temporary
    // file is created exclusively, written through, flushed, then renamed.
    private void WriteAtomic(string path, byte[] bytes, Func<bool> canCommit)
    {
        CheckPath(_directory, true);
        CheckPath(path, false);
        if (!canCommit()) throw new LocalProfileException("profile_local.account_changed");
        var temporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        var created = false;
        try
        {
            using (var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None, 4096, FileOptions.WriteThrough))
            { created = true; stream.Write(bytes); stream.Flush(true); }
            CheckPath(_directory, true);
            var exists = CheckPath(path, false);
            if (!canCommit()) throw new LocalProfileException("profile_local.account_changed");
            if (exists) File.Replace(temporary, path, null); else File.Move(temporary, path);
        }
        finally
        {
            if (created)
                try { File.Delete(temporary); } catch (Exception e) when (StorageError(e)) { }
        }
    }
}
