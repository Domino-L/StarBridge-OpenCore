using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Account;

internal sealed class OfflineOrganizationReadLease(BridgeAccountContext owner, string id, string epoch, Semaphore signal, string? imageEpoch = null) : IDisposable
{
    internal BridgeAccountContext Owner { get; } = owner;
    internal string Id { get; } = id;
    internal string Epoch { get; } = epoch;
    internal string? ImageEpoch { get; } = imageEpoch;
    private int _completed;
    internal bool IsActive => Volatile.Read(ref _completed) == 0;
    internal bool TryComplete() => Interlocked.Exchange(ref _completed, 1) == 0;
    public void Dispose() => signal.Dispose();
}

internal sealed partial class OfflineAccountStore
{
    private string OrganizationsPolicyPath => Path.Combine(Path.GetDirectoryName(_path)!, "organizations-policy.bin");
    private static readonly byte[] OrganizationsPolicyEntropy = Encoding.UTF8.GetBytes("StarBridge.offline-account.organizations-policy.v1");
    private sealed record OrganizationReadPolicy(int SchemaVersion, BridgeAccountContext Owner, string Epoch,
        string? AllowedVersion, string? CandidateVersion, string[] Pending, string? LatestReadId = null, string? ImageEpoch = null);

    internal OfflineOrganizationReadLease? BeginOrganizationRead(BridgeAccountContext owner, Func<bool> current)
    {
        if (!current()) return null;
        using var writer = OrganizationWriter();
        if (!OnlineOrganizationOwner(owner, current)) return null;
        OrganizationReadPolicy? old;
        OrganizationsDocument? data;
        try { old = ReadOrganizationPolicy(); data = ReadOrganizations(); }
        catch (Exception error) when (error is IOException or JsonException or CryptographicException or InvalidOperationException or ArgumentException)
        { old = null; data = null; }
        var sameOwner = old?.Owner == owner;
        var active = sameOwner ? old!.Pending.Where(OrganizationReadIsAlive).ToArray() : [];
        var unresolvedExit = sameOwner && active.Length != old!.Pending.Length;
        var candidate = old is null ? data?.Owner == owner ? data.Version : null
            : sameOwner && !unresolvedExit ? old.CandidateVersion : null;
        if (data is null || data.Owner != owner || candidate != data.Version) candidate = null;
        if (active.Length >= 64) throw new IOException("Organization display read limit reached.");
        var epoch = sameOwner && !unresolvedExit ? old!.Epoch : Guid.NewGuid().ToString("N");
        var id = Guid.NewGuid().ToString("N");
        var signal = new Semaphore(0, 1, OrganizationReadSignalName(id), out var created);
        var imageEpoch = old?.ImageEpoch ?? Guid.NewGuid().ToString("N");
        var lease = new OfflineOrganizationReadLease(owner, id, epoch, signal, imageEpoch);
        try
        {
            if (!created) throw new IOException("Organization display read identity collision.");
            var pending = new OrganizationReadPolicy(1, owner, epoch, null, candidate, [.. active, id], id, imageEpoch);
            if (PublishOrganizationPolicy(pending, current)) return lease;
            lease.Dispose();
            return null;
        }
        catch { lease.Dispose(); throw; }
    }

    internal void CompleteOrganizationRead(OfflineOrganizationReadLease lease, bool withdraw, Func<bool> current)
    {
        if (!lease.TryComplete()) return;
        try
        {
            using var writer = OrganizationWriter();
            var policy = ReadOrganizationPolicy();
            if (!current() || Read()?.Owner != lease.Owner || policy?.Owner != lease.Owner || !policy.Pending.Contains(lease.Id)) return;
            // Unknown exits are pruned only by a NEW read. A result started
            // before a failed refusal write cannot declare those exits safe.
            var pending = policy.Pending.Where(id => id != lease.Id).ToArray();
            if (withdraw)
            {
                policy = new(1, lease.Owner, Guid.NewGuid().ToString("N"), null, null, pending, ImageEpoch: policy.ImageEpoch);
                lock (_organizationsGate) { _organizationCursor = null; _organizationsMemory = null; _organizationsStamp = null; }
            }
            else
            {
                var candidate = policy.CandidateVersion;
                var data = ReadOrganizations();
                var allowed = pending.Length == 0 && data is not null && data.Owner == lease.Owner && candidate == data.Version ? candidate : null;
                policy = policy with { Pending = pending, AllowedVersion = allowed };
            }
            if (!PublishOrganizationPolicy(policy, current)) return;
            if (withdraw)
            {
                Safe(OrganizationsPath);
                if (File.Exists(OrganizationsPath)) File.Delete(OrganizationsPath);
            }
        }
        finally { lease.Dispose(); }
    }

    private bool OwnsOrganizationRead(OfflineOrganizationReadLease lease) =>
        lease.IsActive && ReadOrganizationPolicy() is { AllowedVersion: null } policy && policy.Owner == lease.Owner &&
        policy.Epoch == lease.Epoch && policy.LatestReadId == lease.Id && policy.Pending.Contains(lease.Id);

    private string OrganizationReadSignalName(string id) => "Local\\StarBridge.OrganizationRead." +
        Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(Path.GetFullPath(_path).ToUpperInvariant())))[..32] + "." + id;

    private bool OrganizationReadIsAlive(string id)
    {
        try { using var signal = Semaphore.OpenExisting(OrganizationReadSignalName(id)); return true; }
        catch (WaitHandleCannotBeOpenedException) { return false; }
    }

    private static bool OrganizationPolicyAllows(OrganizationReadPolicy? policy, OrganizationsDocument? data) =>
        data is not null && (policy is null || policy.Owner == data.Owner && policy.Pending.Length == 0 && policy.AllowedVersion == data.Version);

    private OrganizationReadPolicy? ReadOrganizationPolicy()
    {
        var clear = ReadProtectedBytes(OrganizationsPolicyPath, OrganizationsPolicyEntropy, 16 * 1024);
        if (clear is null) return null;
        try
        {
            using var json = JsonDocument.Parse(clear, new JsonDocumentOptions { MaxDepth = 8 });
            UniqueOrganizationProperties(json.RootElement);
            var policy = json.RootElement.Deserialize<OrganizationReadPolicy>(Json) ?? throw new InvalidDataException();
            if (policy.SchemaVersion != 1 || policy.Owner is null || !DisplayText(policy.Owner.Environment, 256) ||
                !DisplayText(policy.Owner.Authority, 2048) || !DisplayText(policy.Owner.Subject, 4096) ||
                !Guid.TryParseExact(policy.Epoch, "N", out _) || policy.Pending is null || policy.Pending.Length > 64 ||
                policy.Pending.Distinct(StringComparer.Ordinal).Count() != policy.Pending.Length ||
                policy.Pending.Any(id => !Guid.TryParseExact(id, "N", out _)) ||
                policy.LatestReadId is { } latest && !Guid.TryParseExact(latest, "N", out _) ||
                policy.ImageEpoch is { } imageEpoch && !Guid.TryParseExact(imageEpoch, "N", out _) ||
                policy.AllowedVersion is { } allowed && (!Guid.TryParseExact(allowed, "N", out _) || policy.Pending.Length != 0 || allowed != policy.CandidateVersion) ||
                policy.CandidateVersion is { } candidate && !Guid.TryParseExact(candidate, "N", out _)) throw new InvalidDataException();
            return policy;
        }
        finally { CryptographicOperations.ZeroMemory(clear); }
    }

    private bool PublishOrganizationPolicy(OrganizationReadPolicy policy, Func<bool> current) =>
        PublishProtectedBytes(OrganizationsPolicyPath, JsonSerializer.SerializeToUtf8Bytes(policy, Json),
            OrganizationsPolicyEntropy, 16 * 1024, current);
}
