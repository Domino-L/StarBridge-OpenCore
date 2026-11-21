using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Nodes;
using StarBridge.Core.Profiles;

namespace StarBridge.HostRuntime.Profiles;

internal sealed partial class SelectedProfileImportCoordinator
{
    private sealed record ShowcaseFields(IReadOnlyList<PersonalProfileShowcaseContract>? Showcases,
        IReadOnlyList<string>? AchievementShowcase);
    private sealed record Additions(ShowcaseFields? Content, ShowcaseFields? Previous, ShowcaseFields? Presentation);
    // Version 2 keeps the wire name MainHash, but binds the normalized operation
    // body (including Ticket and Operation). Version 1 used exact plaintext bytes.
    private sealed record AdditionEntry(string MainHash, Additions Fields);
    private sealed record AdditionFile(int Version, string Owner, AdditionEntry[] Entries, string Integrity);
    private static string Digest(byte[] clear) => Convert.ToHexString(SHA256.HashData(clear));
    private static string AdditionIntegrity(int version, string owner, AdditionEntry[] entries) =>
        Digest(JsonSerializer.SerializeToUtf8Bytes(new { version, owner, entries }, LocalPersonalProfileStore.Json));
    private static string OperationBinding(byte[] clear)
    {
        // Normalize only progress. Retain every other main-file field, including
        // inline additions, so splitting inline data still needs two distinct slots.
        var body = JsonNode.Parse(clear)!;
        if (body["intent"] is JsonObject intent)
        { intent["confirmed"] = false; intent["applied"] = false; }
        var normalized = JsonSerializer.SerializeToUtf8Bytes(body, LocalPersonalProfileStore.Json);
        try { return Digest(normalized); }
        finally { CryptographicOperations.ZeroMemory(normalized); }
    }
    private static ShowcaseFields? Fields(LocalProfileContent? c) => c is null ? null : new(c.Showcases, c.AchievementShowcase);
    private static Additions AdditionsFor(Intent value) => new(Fields(value.Content), Fields(value.Previous?.Content),
        value.Preview.Presentation is { } p ? new(p.Content.Showcases, p.Content.AchievementShowcase) : null);
    private static LocalProfileContent? Merge(LocalProfileContent? c, ShowcaseFields? fields) => c is null ? null : c with {
        Showcases = c.Showcases ?? fields?.Showcases,
        AchievementShowcase = c.AchievementShowcase ?? fields?.AchievementShowcase
    };

    private static Intent? ReadAdditions(string path, string key, byte[] entropy, string binding, string legacyHash, Intent? intent)
    {
        if (intent is null) return null;
        var fallback = intent with { ShowcaseAdditionsUnavailable = true };
        try
        {
            Check(path);
            if (!File.Exists(path)) return fallback;
            if (new FileInfo(path).Length > Limit) throw new IOException("Import additions too large.");
            var clear = ProtectedData.Unprotect(File.ReadAllBytes(path), entropy, DataProtectionScope.CurrentUser);
            try
            {
                if (clear.Length > Limit) throw new IOException("Import additions too large.");
                using var doc = JsonDocument.Parse(clear);
                LocalPersonalProfileStore.RejectDuplicates(doc.RootElement);
                var side = JsonSerializer.Deserialize<AdditionFile>(clear, LocalPersonalProfileStore.Json);
                if (side is null || side.Version is not (1 or 2) || side.Owner != key || side.Entries is not { Length: >= 1 and <= 2 } ||
                    side.Entries.Any(e => e is null || e.Fields is null || e.MainHash is not { Length: 64 }) ||
                    side.Entries.Select(e => e.MainHash).Distinct().Count() != side.Entries.Length ||
                    side.Integrity != AdditionIntegrity(side.Version, key, side.Entries)) throw new IOException("Invalid import additions.");
                var fields = (side.Version == 1 ? side.Entries.SingleOrDefault(e => e.MainHash == legacyHash) : null)?.Fields
                    ?? side.Entries.SingleOrDefault(e => e.MainHash == binding)?.Fields;
                if (fields is null) return fallback;
                var combined = intent with {
                    Content = Merge(intent.Content, fields.Content),
                    Previous = intent.Previous is { } previous ? previous with { Content = Merge(previous.Content, fields.Previous) } : null,
                    Preview = intent.Preview.Presentation is { } p ? intent.Preview with { Presentation = p with { Content = p.Content with {
                        Showcases = p.Content.Showcases ?? fields.Presentation?.Showcases?.ToArray(),
                        AchievementShowcase = p.Content.AchievementShowcase ?? fields.Presentation?.AchievementShowcase?.ToArray()
                    } } } : intent.Preview
                };
                Validate(combined);
                return combined;
            }
            finally { CryptographicOperations.ZeroMemory(clear); }
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or CryptographicException or JsonException or LocalProfileException)
        { return fallback; }
    }

    // Called under .dat.lock only. Two slots preserve the committed intent while
    // staging its successor. Progress-only changes share one immutable additions
    // slot; a changed operation or body needs a distinct slot.
    private static void WriteAdditions(string path, string key, byte[] entropy, AdditionEntry[] entries, Func<bool> current)
    {
        var clear = JsonSerializer.SerializeToUtf8Bytes(new AdditionFile(2, key, entries,
            AdditionIntegrity(2, key, entries)), LocalPersonalProfileStore.Json);
        byte[] encrypted;
        try
        {
            if (clear.Length > Limit / 2) throw new IOException("Import additions too large.");
            encrypted = ProtectedData.Protect(clear, entropy, DataProtectionScope.CurrentUser);
        }
        finally { CryptographicOperations.ZeroMemory(clear); }
        var temporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            Check(path);
            if (!current()) throw new LocalProfileException("profile_local.account_changed");
            using (var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None, 4096, FileOptions.WriteThrough))
            { stream.Write(encrypted); stream.Flush(true); }
            Check(path);
            if (!current()) throw new LocalProfileException("profile_local.account_changed");
            if (File.Exists(path)) File.Replace(temporary, path, null); else File.Move(temporary, path);
        }
        finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }
}
