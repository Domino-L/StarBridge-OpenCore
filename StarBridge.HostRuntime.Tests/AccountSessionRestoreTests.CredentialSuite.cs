internal static partial class AccountSessionRestoreTests
{
    private static async Task CredentialVersionRegression()
    {
        await ReviewFixes();
        var cases = new (string Name, Func<Task> Run)[] {
            ("stale retry", CredentialRace),
            ("single-flight", RestoreSingleFlight),
            ("concurrent 401 and background", Concurrent401AndBackgroundRestore),
            ("logout and switch", LogoutAndAccountSwitchDoNotResurrect),
            ("token read budget", TokenReadBudget),
            ("refresh classifiers", RefreshTransientClassifiers),
            ("late responses and unconfirmed rotation", LateResponsesAndUnconfirmedRotation)
        };
        foreach (var (name, run) in cases)
        {
            await run();
            Console.WriteLine("PASS CX-L07 " + name);
        }
        Console.WriteLine("CX-L07 SUMMARY PASS 7/7");
    }
}
