using StarBridge.Core.Profiles;

namespace StarBridge.Core.Tests;

internal static class ProfileTimeZoneContractTests
{
    public static void RunAll()
    {
        KnownIanaIdsResolveWithoutChangingTheWireValue();
        WindowsIdsConvertOnlyForLocalMigration();
        UnknownAndMissingIdsFallbackWithoutLosingTheServerValue();
    }

    private static void KnownIanaIdsResolveWithoutChangingTheWireValue()
    {
        var asia = ProfileTimeZoneContract.ResolveIana("Asia/Shanghai");
        AssertEqual("Asia/Shanghai", asia.RequestedId, "server IANA value was not retained");
        AssertEqual("Asia/Shanghai", asia.IanaId, "server IANA value was rewritten");
        AssertEqual(false, asia.UsedUtcFallback, "known Asia IANA value fell back to UTC");
        AssertEqual(
            TimeSpan.FromHours(8),
            asia.TimeZone.GetUtcOffset(DateTimeOffset.Parse("2026-01-15T00:00:00Z")),
            "Asia/Shanghai resolved to the wrong Windows offset");

        var australia = ProfileTimeZoneContract.ResolveIana("Australia/Sydney");
        AssertEqual("Australia/Sydney", australia.IanaId, "Australian IANA value was rewritten");
        AssertEqual(false, australia.UsedUtcFallback, "known Australian IANA value fell back to UTC");
        AssertEqual(true, !string.IsNullOrWhiteSpace(australia.WindowsId),
            "Australian IANA value did not produce a Windows identifier");
    }

    private static void WindowsIdsConvertOnlyForLocalMigration()
    {
        AssertEqual(
            true,
            ProfileTimeZoneContract.TryConvertWindowsToIana("China Standard Time", out var ianaId),
            "known Windows identifier did not convert to IANA");
        AssertEqual("Asia/Shanghai", ianaId, "Windows-to-IANA mapping was unstable");

        var wireViolation = ProfileTimeZoneContract.ResolveIana("China Standard Time");
        AssertEqual(true, wireViolation.UsedUtcFallback,
            "a Windows identifier was accepted as the network profile contract");
        AssertEqual("China Standard Time", wireViolation.RequestedId,
            "fallback discarded the server-supplied identifier needed for diagnostics");
    }

    private static void UnknownAndMissingIdsFallbackWithoutLosingTheServerValue()
    {
        var unknown = ProfileTimeZoneContract.ResolveIana("Mars/Olympus_Mons");
        AssertEqual(ProfileTimeZoneContract.UtcIanaId, unknown.IanaId,
            "unknown identifier did not fall back to UTC");
        AssertEqual("Mars/Olympus_Mons", unknown.RequestedId,
            "unknown identifier was discarded during fallback");
        AssertEqual(true, unknown.UsedUtcFallback, "unknown identifier did not report fallback");

        var missing = ProfileTimeZoneContract.ResolveIana(null);
        AssertEqual(ProfileTimeZoneContract.UtcIanaId, missing.IanaId,
            "missing identifier did not fall back to UTC");
        AssertEqual(true, missing.UsedUtcFallback, "missing identifier did not report fallback");
    }

    private static void AssertEqual<T>(T expected, T actual, string message)
    {
        if (!EqualityComparer<T>.Default.Equals(expected, actual))
        {
            throw new InvalidOperationException($"{message}. Expected: {expected}; Actual: {actual}");
        }
    }
}
