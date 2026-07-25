namespace StarBridge.Desktop;

public readonly record struct AccountSessionIdentity(string? AccountId, string? AccountName)
{
    public string StableKey => !string.IsNullOrWhiteSpace(AccountId)
        ? $"id:{AccountId.Trim()}"
        : string.IsNullOrWhiteSpace(AccountName)
            ? ""
            : $"name:{AccountName.Trim()}";
}

public readonly record struct AccountSessionLease(long Revision, string StableKey);

public readonly record struct AccountSessionTransition(
    bool AccountChanged,
    AccountSessionLease Lease);

/// <summary>
/// Owns the account-session seam. Every asynchronous account-scoped read captures a lease;
/// responses from an earlier login are rejected after a switch or logout.
/// </summary>
public sealed class AccountSessionCoordinator
{
    private long _revision;
    private AccountSessionIdentity _current;

    public AccountSessionTransition Begin(
        AccountSessionIdentity previous,
        AccountSessionIdentity next)
    {
        var accountChanged = HasChanged(previous, next);
        var stableIdentityChanged = !_current.StableKey.Equals(
            next.StableKey,
            StringComparison.OrdinalIgnoreCase);
        _current = next;
        if (stableIdentityChanged)
        {
            _revision++;
        }

        var lease = new AccountSessionLease(_revision, next.StableKey);
        return new AccountSessionTransition(accountChanged, lease);
    }

    public AccountSessionLease Capture() => new(_revision, _current.StableKey);

    public bool IsCurrent(AccountSessionLease lease) =>
        lease.Revision == _revision &&
        lease.StableKey.Equals(_current.StableKey, StringComparison.OrdinalIgnoreCase);

    public void End()
    {
        _current = default;
        _revision++;
    }

    public static bool HasChanged(
        AccountSessionIdentity previous,
        AccountSessionIdentity next)
    {
        if (!string.IsNullOrWhiteSpace(previous.AccountId) &&
            !string.IsNullOrWhiteSpace(next.AccountId))
        {
            return !previous.AccountId.Trim().Equals(
                next.AccountId.Trim(),
                StringComparison.OrdinalIgnoreCase);
        }

        if (string.IsNullOrWhiteSpace(previous.AccountName))
        {
            return false;
        }

        return !previous.AccountName.Trim().Equals(
            next.AccountName?.Trim(),
            StringComparison.OrdinalIgnoreCase);
    }
}
