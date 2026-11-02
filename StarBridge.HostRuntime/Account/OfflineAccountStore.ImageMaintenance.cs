using System.Text.Json;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Account;

internal sealed record OfflineOrganizationImageRead(BridgeAccountContext Owner, string? Epoch);

internal sealed partial class OfflineAccountStore
{
    // A display-resource generation only. It never selects an account, finishes
    // a pending authorization read, or substitutes for the original policy.
    internal int ClearOrganizationImages()
    {
        Safe(OrganizationsPath); Safe(OrganizationsPolicyPath);
        if (File.Exists(Path.GetDirectoryName(_path)) || Directory.Exists(OrganizationsPath) || Directory.Exists(OrganizationsPolicyPath))
            throw new IOException("Organization image cache has an invalid path shape.");
        if (!File.Exists(OrganizationsPath) && !File.Exists(OrganizationsPolicyPath)) return 0;
        using var writer = OrganizationWriter();
        var document = ReadOrganizations();
        var policy = ReadOrganizationPolicy();
        if (document is null && policy is null) return 0;
        var fenced = (policy ?? new(1, document!.Owner, Guid.NewGuid().ToString("N"), document.Version, document.Version, []))
            with { ImageEpoch = Guid.NewGuid().ToString("N") };
        // Fence old observers before changing the protected bytes. A failure
        // remains an explicit failed maintenance operation, never success.
        if (!PublishOrganizationPolicy(fenced, () => true)) throw new IOException("Organization image fence was not published.");
        var count = document?.Items.Count(row => row.LogoImageData is not null) ?? 0;
        if (count == 0) return 0;
        var next = document! with
        {
            Version = Guid.NewGuid().ToString("N"),
            MetadataVersion = document.MetadataVersion ?? document.Version,
            Items = document.Items.Select(row => row with { LogoImageData = null, LogoCachedAtUtc = null }).ToArray()
        };
        if (!PublishProtectedBytes(OrganizationsPath, JsonSerializer.SerializeToUtf8Bytes(next, Json),
                OrganizationsEntropy, OrganizationLimit, () => true)) throw new IOException("Organization images were not cleared.");
        lock (_organizationsGate) { _organizationsMemory = null; _organizationsStamp = null; }
        // Preserve exactly the eligibility and pending-read state that existed
        // before maintenance; a resource reset cannot grant read permission.
        var updated = fenced.Owner == next.Owner ? fenced with
        {
            AllowedVersion = fenced.AllowedVersion == document.Version ? next.Version : fenced.AllowedVersion,
            CandidateVersion = fenced.CandidateVersion == document.Version ? next.Version : fenced.CandidateVersion
        } : fenced;
        if (!PublishOrganizationPolicy(updated, () => true)) throw new IOException("Organization image version was not published.");
        return count;
    }

    internal OfflineOrganizationImageRead? CaptureOrganizationImageRead(BridgeAccountContext owner, Func<bool> current)
    {
        if (!OnlineOrganizationOwner(owner, current)) return null;
        var policy = ReadOrganizationPolicy();
        if (policy is not null && policy.Owner != owner) return null;
        if (policy?.ImageEpoch is null)
        {
            // Even the first optional media read must leave a durable admission
            // stamp. Otherwise an empty cleanup could not fence it before a
            // later directory creates the first protected image destination.
            using var writer = OrganizationWriter();
            if (!OnlineOrganizationOwner(owner, current)) return null;
            policy = ReadOrganizationPolicy();
            if (policy is not null && policy.Owner != owner) return null;
            if (policy?.ImageEpoch is null)
            {
                var directory = ReadOrganizations();
                var legacyVersion = directory?.Owner == owner ? directory.Version : null;
                policy = (policy ?? new(1, owner, Guid.NewGuid().ToString("N"), legacyVersion, legacyVersion, []))
                    with { ImageEpoch = Guid.NewGuid().ToString("N") };
                if (!PublishOrganizationPolicy(policy, current)) return null;
            }
        }
        return current() ? new(owner, policy?.ImageEpoch) : null;
    }
}
