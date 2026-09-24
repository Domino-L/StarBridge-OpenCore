using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace StarBridge.HostRuntime.Chat;

// Display-only archive. No credentials, command references, invitation codes or grants.
internal sealed record LocalChatLine(long Sequence, string Name, string Text, DateTimeOffset Time, bool Self, bool Attachment);
internal sealed class LocalChatHistory(string? root = null, Func<DateTimeOffset>? clock = null)
{
    private readonly string _root = Path.GetFullPath(root ?? Path.Combine(HostDataRoot.CurrentRoot, "chat-history"));
    private readonly Func<DateTimeOffset> _now = clock ?? (() => DateTimeOffset.UtcNow);
    private static readonly SemaphoreSlim Gate = new(1, 1);
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);
    private sealed record Envelope(int Version, string Account, string Conversation, LocalChatLine[] Lines);
    private static string Hash(string value) => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(value)));

    internal async Task<LocalChatLine[]> Run(string account, string conversation, LocalChatLine[]? append = null, bool clear = false)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(account);
        ArgumentException.ThrowIfNullOrWhiteSpace(conversation);
        await Gate.WaitAsync();
        try
        {
            var partition = Hash(account); var key = Hash(conversation);
            var folder = Path.Combine(_root, partition); var path = Path.Combine(folder, key + ".dat");
            Directory.CreateDirectory(folder);
            using var lease = new FileStream(Path.Combine(folder, "archive.lock"), FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
            if (clear) { File.Delete(path); return []; }
            var entropy = Encoding.UTF8.GetBytes("StarBridge.ChatHistory.v1\0" + partition + key);
            var lines = Array.Empty<LocalChatLine>();
            if (File.Exists(path))
            {
                if (new FileInfo(path).Length > 16 * 1024 * 1024) throw new InvalidDataException();
                var bytes = ProtectedData.Unprotect(await File.ReadAllBytesAsync(path), entropy, DataProtectionScope.CurrentUser);
                try
                {
                    var saved = JsonSerializer.Deserialize<Envelope>(bytes, Json) ?? throw new InvalidDataException();
                    if (saved.Version != 1 || saved.Account != partition || saved.Conversation != key || saved.Lines.Length > 10000)
                        throw new InvalidDataException();
                    lines = saved.Lines;
                }
                finally { CryptographicOperations.ZeroMemory(bytes); }
            }
            var now = _now();
            var all = lines.Concat(append ?? []).ToArray();
            if (all.Any(x => x.Sequence <= 0 || x.Text is null || x.Text.Length > 4096 || x.Name is null || x.Name.Length > 512))
                throw new InvalidDataException();
            var retained = all.Where(x => x.Time >= now.AddDays(-90) && x.Time <= now.AddMinutes(5))
                .GroupBy(x => x.Sequence).Select(g => g.Last()).OrderBy(x => x.Sequence).TakeLast(10000).ToArray();
            // Prune cold conversations too; only this account's known archive files.
            foreach (var file in Directory.EnumerateFiles(folder, "*.dat"))
                if (File.GetLastWriteTimeUtc(file) < now.AddDays(-90).UtcDateTime) File.Delete(file);
            if (retained.Length == 0) { File.Delete(path); return []; }
            if (append is not null || retained.Length != lines.Length)
            {
                if (!File.Exists(path) && Directory.EnumerateFiles(folder, "*.dat").Take(256).Count() >= 256)
                    throw new IOException("Local chat archive capacity reached.");
                var bytes = JsonSerializer.SerializeToUtf8Bytes(new Envelope(1, partition, key, retained), Json);
                byte[] encrypted;
                try
                {
                    if (bytes.Length > 12 * 1024 * 1024) throw new InvalidDataException();
                    encrypted = ProtectedData.Protect(bytes, entropy, DataProtectionScope.CurrentUser);
                }
                finally { CryptographicOperations.ZeroMemory(bytes); }
                await File.WriteAllBytesAsync(path + ".tmp", encrypted);
                File.Move(path + ".tmp", path, true);
            }
            return retained.TakeLast(50).ToArray();
        }
        finally { Gate.Release(); }
    }
}
