using System.Security.Cryptography;
using StarBridge.HostRuntime.Account;

namespace StarBridge.HostRuntime.Marketplace;

/// <summary>Opaque participant references bind owner and contract; identifiers stay in Host.</summary>
internal sealed class MarketplaceContractReferences
{
    private readonly object gate = new();
    private readonly Dictionary<string, (string Owner, long Contract, long Participant)> references = new();
    private string? currentOwner;

    /// <summary>Called on every contracts call: another account in between voids every older
    /// reference, so A → B → A cannot reuse A's earlier ones (C review P2).</summary>
    internal void Touch(string owner)
    {
        lock (gate)
        {
            if (currentOwner == owner) return;
            references.Clear();
            currentOwner = owner;
        }
    }

    internal string Reference(string owner, long contract, long participant)
    {
        lock (gate)
        {
            foreach (var entry in references)
                if (entry.Value == (owner, contract, participant)) return entry.Key;
            if (references.Count >= 10000) references.Clear();
            var reference = Convert.ToHexString(RandomNumberGenerator.GetBytes(16)).ToLowerInvariant();
            references[reference] = (owner, contract, participant);
            return reference;
        }
    }

    internal long Resolve(string owner, long contract, string reference)
    {
        lock (gate)
            return references.TryGetValue(reference, out var found) && found.Owner == owner &&
                found.Contract == contract && found.Participant > 0 ? found.Participant
                : throw new AccountBridgeHostException("marketplace.invalid_request");
    }
}