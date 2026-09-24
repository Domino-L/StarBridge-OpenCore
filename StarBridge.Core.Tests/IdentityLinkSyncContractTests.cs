namespace StarBridge.Core.Tests;

// Source wiring contract only: desktop orchestration stays in Desktop. The
// recovery coordinator and startup gate are exercised by Desktop.Tests.
internal static class IdentityLinkSyncContractTests
{
    internal static void RunAll()
    {
        var root = new DirectoryInfo(AppContext.BaseDirectory);
        while (root is not null && !File.Exists(Path.Combine(root.FullName, "StarBridge.sln")))
        {
            root = root.Parent;
        }
        if (root is null)
        {
            throw new InvalidOperationException("Cannot find the active solution root.");
        }

        var source = File.ReadAllText(Path.Combine(root.FullName,
            "StarBridge.Desktop", "MainWindow.Authentication.cs"));
        foreach (var (start, end, confirmedPaths) in new[]
        {
            ("private async Task LinkLegacyIdentityAsync()",
                "private async Task ProvisionCompatibilityAccountAsync()", 4),
            ("private async Task ProvisionCompatibilityAccountAsync()",
                "private async Task RefreshLegacyIdentityLinkStateAsync(", 3)
        })
        {
            var methodStart = source.IndexOf(start, StringComparison.Ordinal);
            Require(methodStart >= 0, "Identity link method was not found.");
            var methodEnd = source.IndexOf(end, methodStart, StringComparison.Ordinal);
            Require(methodStart >= 0 && methodEnd > methodStart, "Identity link method boundary changed.");
            var method = source[methodStart..methodEnd];
            Require(method.Split("resumeRuntimeSynchronization = true;", StringSplitOptions.None).Length - 1 == confirmedPaths,
                "A confirmed link or timeout reconciliation no longer resumes startup sync.");
            var finallyStart = method.LastIndexOf("finally", StringComparison.Ordinal);
            Require(finallyStart >= 0, "Identity link completion block was not found.");
            var completion = method[finallyStart..];
            var unlock = completion.IndexOf("_identityLinkInProgress = false;", StringComparison.Ordinal);
            var resume = completion.IndexOf("ScheduleScmRuntimeRecovery(", StringComparison.Ordinal);
            Require(unlock >= 0 && resume > unlock,
                "Link completion must request runtime recovery after releasing the operation busy gate.");
            Require(completion.Contains("!operationCancellation.IsCancellationRequested", StringComparison.Ordinal) &&
                    completion.Contains("resumeRuntimeSynchronization", StringComparison.Ordinal) &&
                    completion.Contains("forceDependencyReplay: true", StringComparison.Ordinal),
                "Cancelled/unconfirmed links must not resume; confirmed links must replay even when Relay is ready.");
        }

        var scheduleStart = source.IndexOf("private void ScheduleScmRuntimeRecovery(", StringComparison.Ordinal);
        Require(scheduleStart >= 0, "Runtime recovery scheduler was not found.");
        var recoverStart = source.IndexOf("private async Task<bool> RecoverScmRuntimeStateAsync(", scheduleStart, StringComparison.Ordinal);
        Require(recoverStart > scheduleStart, "Runtime recovery entry was not found.");
        var observeStart = source.IndexOf("private static async Task ObserveScmRuntimeRecoveryAsync(", recoverStart, StringComparison.Ordinal);
        Require(observeStart > recoverStart, "Runtime recovery boundary changed.");
        var schedule = source[scheduleStart..recoverStart];
        var recover = source[recoverStart..observeStart];
        Require(schedule.Contains("!IsCurrentScmSessionIdentity(session)", StringComparison.Ordinal) &&
                schedule.Contains("_scmRuntimeRecoveryCoordinator.RequestAsync(", StringComparison.Ordinal),
            "Link completion must retain the current-account and single recovery lane guards.");
        Require(recover.Contains("CanPublishScmRuntimeRecovery(session, lease)", StringComparison.Ordinal) &&
                recover.Contains("_syncPrivacySettings.SyncConsentCompleted", StringComparison.Ordinal) &&
                recover.Contains("CurrentSyncConsentVersion", StringComparison.Ordinal) &&
                recover.Contains("await AutoConnectNetworkAsync();", StringComparison.Ordinal),
            "Recovery must enter the consent- and identity-guarded startup path.");
    }

    private static void Require(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException(message);
    }
}
