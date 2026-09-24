namespace StarBridge.Core.Tests;

using StarBridge.Core.Profiles;

internal static class ScmProfileContractTests
{
    internal static void RunAll()
    {
        PublicProjectionOmitsPrivateFields();
        PatchDistinguishesMissingFromExplicitNull();
        PatchOwnsOnlyLocaleAndTimeZone();
        PatchRejectsUnsupportedValues();
        OfflineCacheExcludesPrivateAndAuthorizationState();
    }

    private static void PublicProjectionOmitsPrivateFields()
    {
        var self = new ScmSelfProfileContract(
            " subject-a ", " Citizen ", " https://cdn.example/avatar.png ",
            "private@example.com", "zh_CN", "Asia/Shanghai").Normalize();
        var publicProfile = self.ToPublic();

        AssertEqual("subject-a", publicProfile.Subject, "public subject");
        AssertEqual("Citizen", publicProfile.DisplayName, "public display name");
        AssertEqual("https://cdn.example/avatar.png", publicProfile.AvatarUrl, "public avatar");
        AssertEqual(3, publicProfile.GetType().GetProperties().Length,
            "public projection accidentally gained a private field");
    }

    private static void PatchDistinguishesMissingFromExplicitNull()
    {
        var clearLocale = new ScmProfilePatchContract(
            ScmProfilePatchField.Set(null),
            ScmProfilePatchField.Unspecified).ToWirePayload();
        AssertEqual(true, clearLocale.ContainsKey("locale"), "explicit null locale is present");
        AssertEqual<object?>(null, clearLocale["locale"], "explicit null locale clears");
        AssertEqual(false, clearLocale.ContainsKey("timeZone"), "unspecified time zone is omitted");

        var update = new ScmProfilePatchContract(
            ScmProfilePatchField.Set("en_US"),
            ScmProfilePatchField.Set("UTC")).ToWirePayload();
        AssertEqual("en-US", update["locale"], "locale normalization");
        AssertEqual("Etc/UTC", update["timeZone"], "IANA UTC normalization");

        AssertThrows<InvalidOperationException>(() => new ScmProfilePatchContract(
            ScmProfilePatchField.Unspecified,
            ScmProfilePatchField.Unspecified).ToWirePayload(), "empty patch");
    }

    private static void PatchRejectsUnsupportedValues()
    {
        AssertThrows<ArgumentException>(() => new ScmProfilePatchContract(
            ScmProfilePatchField.Set("fr-FR"),
            ScmProfilePatchField.Unspecified).ToWirePayload(), "unsupported locale");
        AssertThrows<ArgumentException>(() => new ScmProfilePatchContract(
            ScmProfilePatchField.Unspecified,
            ScmProfilePatchField.Set("China Standard Time")).ToWirePayload(), "Windows time zone");
    }

    private static void PatchOwnsOnlyLocaleAndTimeZone()
    {
        var payload = new ScmProfilePatchContract(
            ScmProfilePatchField.Set("zh-CN"),
            ScmProfilePatchField.Set("Asia/Shanghai")).ToWirePayload();

        AssertEqual(2, payload.Count, "profile patch field count");
        AssertEqual(true, payload.Keys.SequenceEqual(["locale", "timeZone"]),
            "profile patch must not carry game server region or shard");
        AssertEqual(false, payload.ContainsKey("serverRegion"), "profile patch server region");
        AssertEqual(false, payload.ContainsKey("serverShard"), "profile patch server shard");
    }

    private static void OfflineCacheExcludesPrivateAndAuthorizationState()
    {
        var cached = ScmCachedProfileContract.Create(
            "development",
            "scm-production",
            new ScmSelfProfileContract(
                "subject-a", "Citizen", "https://cdn.example/avatar.png",
                "private@example.com", "zh-CN", "Asia/Shanghai"),
            DateTimeOffset.Parse("2026-08-26T12:00:00Z"));

        AssertEqual(null, cached.ToOfflineProfile().Email, "offline cache email");
        var propertyNames = cached.GetType().GetProperties().Select(property => property.Name).ToArray();
        AssertEqual(false, propertyNames.Any(name => name.Contains("Token", StringComparison.OrdinalIgnoreCase)),
            "offline cache contains token material");
        AssertEqual(false, propertyNames.Any(name => name.Contains("Capability", StringComparison.OrdinalIgnoreCase)),
            "offline cache contains authorization capabilities");
        AssertEqual(false, propertyNames.Any(name => name.Contains("Legacy", StringComparison.OrdinalIgnoreCase)),
            "offline cache contains migration identity");
    }

    private static void AssertEqual<T>(T expected, T actual, string label)
    {
        if (!EqualityComparer<T>.Default.Equals(expected, actual))
        {
            throw new InvalidOperationException($"{label}: expected {expected}, got {actual}");
        }
    }

    private static void AssertThrows<TException>(Action action, string label)
        where TException : Exception
    {
        try
        {
            action();
        }
        catch (TException)
        {
            return;
        }

        throw new InvalidOperationException($"{label}: expected {typeof(TException).Name}");
    }
}
