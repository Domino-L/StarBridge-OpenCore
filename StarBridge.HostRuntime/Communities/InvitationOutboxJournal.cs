using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using StarBridge.Core.Chat;

namespace StarBridge.HostRuntime.Communities;

internal sealed record InvitationOutboxItem(string Id, string SourceCode, string Channel, string DestinationId,
    string Origin, DateTimeOffset RequestedAt, int MaxUses, string DeliveryId, string Phase,
    InvitationGenerationResult? Generation = null, InvitationDeliveryResult? Delivery = null, ChatAttachmentContract? Card = null,
    string SourceName = "", string DestinationName = "");

// Local recovery data, not account migration. Tokens and UI-scoped references are never stored.
internal sealed class InvitationOutboxJournal
{
    private const int MaximumBytes = 1024 * 1024;
    private readonly string _root;
    internal InvitationOutboxJournal(string? root = null) => _root = Path.GetFullPath(root ??
        Path.Combine(HostDataRoot.CurrentRoot, "community-invitation-outbox"));

    internal async Task<T> RunAsync<T>(string accountKey, Func<Session, Task<T>> action)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(accountKey);
        var partition = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(accountKey)));
        Directory.CreateDirectory(_root);
        var path = Path.Combine(_root, partition + ".dat");
        // Also excludes a second Native Host/process. A failed lock never permits an unlocked write.
        using var lease = new FileStream(path + ".lock", FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
        var entropy = Encoding.UTF8.GetBytes("StarBridge.InvitationOutbox.v1\0" + partition);
        var rows = new Dictionary<string, InvitationOutboxItem>(StringComparer.Ordinal);
        if (File.Exists(path))
        {
            if (new FileInfo(path).Length > MaximumBytes) throw new InvalidDataException("Invitation outbox exceeds size limit.");
            var clear = ProtectedData.Unprotect(await File.ReadAllBytesAsync(path), entropy, DataProtectionScope.CurrentUser);
            try
            {
                var stored = JsonSerializer.Deserialize<Envelope>(clear) ?? throw new InvalidDataException("Invalid invitation outbox.");
                if (stored.SchemaVersion != 1 || stored.Partition != partition || stored.Items is null || stored.Items.Length > 128)
                    throw new InvalidDataException("Invalid invitation outbox.");
                foreach (var item in stored.Items)
                {
                    Validate(item);
                    if (!rows.TryAdd(item.Id, item)) throw new InvalidDataException("Duplicate invitation intent.");
                }
            }
            finally { CryptographicOperations.ZeroMemory(clear); }
        }
        return await action(new Session(rows, async candidate =>
        {
            var clear = JsonSerializer.SerializeToUtf8Bytes(new Envelope(1, partition, candidate.Values.ToArray()));
            byte[] encrypted;
            try
            {
                if (clear.Length > MaximumBytes / 2) throw new InvalidDataException("Invitation outbox exceeds size limit.");
                encrypted = ProtectedData.Protect(clear, entropy, DataProtectionScope.CurrentUser);
            }
            finally { CryptographicOperations.ZeroMemory(clear); }
            var temporary = path + ".tmp";
            await File.WriteAllBytesAsync(temporary, encrypted);
            File.Move(temporary, path, true);
        }));
    }

    internal sealed class Session(Dictionary<string, InvitationOutboxItem> rows,
        Func<Dictionary<string, InvitationOutboxItem>, Task> persist)
    {
        internal InvitationOutboxItem? Find(string id) => rows.GetValueOrDefault(id);
        internal InvitationOutboxItem[] Items => rows.Values.ToArray();
        internal async Task SaveAsync(InvitationOutboxItem item)
        {
            Validate(item);
            if (rows.TryGetValue(item.Id, out var old))
            {
                if ((old with { Phase = item.Phase, Generation = item.Generation, Delivery = item.Delivery, Card = item.Card }) != item)
                    throw new InvalidDataException("Invitation intent cannot change.");
                if (old.Generation is not null && old.Generation != item.Generation)
                    throw new InvalidDataException("Generated invitation cannot change.");
                if (old.Card is not null && old.Card != item.Card) throw new InvalidDataException("Original invitation attachment cannot change.");
                if (old.Phase != item.Phase && (old.Phase, item.Phase) is not
                    (("prepared", "generating") or ("generating", "ready") or ("ready", "sending") or ("sending", "ready") or ("sending", "sent")))
                    throw new InvalidDataException("Invalid invitation phase transition.");
                if (old.Phase == "sent" && old != item) throw new InvalidDataException("Delivered invitation is final.");
            }
            else if (rows.Count >= 128) throw new InvalidDataException("Invitation outbox is full.");
            var candidate = new Dictionary<string, InvitationOutboxItem>(rows, StringComparer.Ordinal) { [item.Id] = item };
            await persist(candidate);
            rows = candidate; // Publish only after the final replacement succeeds.
        }
    }
    private sealed record Envelope(int SchemaVersion, string Partition, InvitationOutboxItem[] Items);
    internal static bool IsId(string? value) => value is { Length: 32 } && value.All(c => c is >= '0' and <= '9' or >= 'a' and <= 'f');
    private static void Validate(InvitationOutboxItem item)
    {
        if (item.SourceName is null || item.DestinationName is null || item.SourceName.Length > 512 || item.DestinationName.Length > 512
            || item.SourceName.Any(char.IsControl) || item.DestinationName.Any(char.IsControl)) throw new InvalidDataException("Invalid invitation labels.");
        static bool Text(string? value, int max) => !string.IsNullOrWhiteSpace(value) && value.Length <= max && !value.Any(char.IsControl);
        if (!IsId(item.Id) || !IsId(item.DeliveryId) || !Text(item.SourceCode, 256) || !Text(item.DestinationId, 256)
            || item.Channel is not ("private" or "room") || item.MaxUses is < 1 or > 50
            || item.Phase is not ("prepared" or "generating" or "ready" or "sending" or "sent")
            || !Uri.TryCreate(item.Origin, UriKind.Absolute, out var origin) || origin.UserInfo.Length != 0
            || origin.Query.Length != 0 || origin.Fragment.Length != 0
            || origin.Scheme != "https" && !(origin.Scheme == "http" && origin.IsLoopback)
            || item.RequestedAt > DateTimeOffset.UtcNow.AddMinutes(5)) throw new InvalidDataException("Invalid invitation intent.");
        if (item.Phase is "prepared" or "generating" && (item.Generation is not null || item.Delivery is not null || item.Card is not null))
            throw new InvalidDataException("Unexpected invitation receipt.");
        if (item.Phase is "ready" or "sending" or "sent")
        {
            var generated = item.Generation;
            if (generated?.Status != "accepted" || !IsId(generated.InviteId) || !Text(generated.Code, 40)
                || generated.ExpiresAt is null) throw new InvalidDataException("Invitation generation receipt missing.");
            if (!ChatAttachmentPolicy.TryNormalize(item.Card, out var card, out _) || card?.Kind != ChatAttachmentKinds.FleetInvitation
                || card != item.Card || card.FleetInviteCode != generated.Code || card.ExpiresAt != generated.ExpiresAt)
                throw new InvalidDataException("Original invitation attachment missing.");
        }
        if (item.Phase == "sent" && (item.Delivery?.Status != "sent" || !IsId(item.Delivery.MessageId)
            || item.Delivery.Sequence is null or <= 0 || item.Delivery.CreatedAt is null))
            throw new InvalidDataException("Invitation delivery receipt missing.");
    }
}
