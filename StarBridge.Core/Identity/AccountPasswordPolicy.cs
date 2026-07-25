namespace StarBridge.Core.Identity;

public static class AccountPasswordPolicy
{
    public const int MinimumLength = 8;
    public const int MaximumLength = 128;

    public static bool IsValidLength(string? password) =>
        password is not null && password.Length is >= MinimumLength and <= MaximumLength;
}
