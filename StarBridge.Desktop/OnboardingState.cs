using System;
using System.IO;

namespace StarBridge.Desktop;

internal enum OnboardingCompletionStatus
{
    Missing,
    Legacy,
    Current
}

internal static class OnboardingState
{
    private const string LegacyGuideVersion = "starbridge-onboarding-v1";
    private const string PreviousGuideVersion = "starbridge-onboarding-v2";
    private const string PreviousSpotlightGuideVersion = "starbridge-onboarding-v3";
    private const string PreviousInteractiveGuideVersion = "starbridge-onboarding-v4";
    private const string CurrentGuideVersion = "starbridge-onboarding-v5";
    private static readonly string CompletionPath = Path.Combine(
        DesktopAppConfig.ConfigDirectory,
        "onboarding.complete");
    private static readonly string IntroductionPath = Path.Combine(
        DesktopAppConfig.ConfigDirectory,
        "onboarding-introduction.read");
    private static readonly string PreparationPath = Path.Combine(
        DesktopAppConfig.ConfigDirectory,
        "onboarding-preparation.complete");
    private static readonly string FeatureTourPath = Path.Combine(
        DesktopAppConfig.ConfigDirectory,
        "onboarding-feature-tour.step");
    private static readonly string DeferredPath = Path.Combine(
        DesktopAppConfig.ConfigDirectory,
        "onboarding.deferred");

    public static OnboardingCompletionStatus GetCompletionStatus()
    {
        try
        {
            if (!File.Exists(CompletionPath))
            {
                return OnboardingCompletionStatus.Missing;
            }

            return File.ReadAllText(CompletionPath).Trim() switch
            {
                CurrentGuideVersion => OnboardingCompletionStatus.Current,
                LegacyGuideVersion => OnboardingCompletionStatus.Legacy,
                PreviousGuideVersion => OnboardingCompletionStatus.Legacy,
                PreviousSpotlightGuideVersion => OnboardingCompletionStatus.Legacy,
                PreviousInteractiveGuideVersion => OnboardingCompletionStatus.Legacy,
                _ => OnboardingCompletionStatus.Missing
            };
        }
        catch
        {
            return OnboardingCompletionStatus.Missing;
        }
    }

    public static void MarkCompleted()
    {
        try
        {
            Directory.CreateDirectory(DesktopAppConfig.ConfigDirectory);
            File.WriteAllText(CompletionPath, CurrentGuideVersion);
            TryDelete(IntroductionPath);
            TryDelete(PreparationPath);
            TryDelete(FeatureTourPath);
            TryDelete(DeferredPath);
        }
        catch
        {
            // The guide is optional; failure to save the flag must not block startup.
        }
    }

    public static bool HasReadIntroduction() => FileExists(IntroductionPath);

    public static void MarkIntroductionRead() => WriteProgressMarker(IntroductionPath);

    public static bool HasCompletedPreparation() => FileExists(PreparationPath);

    public static void MarkPreparationCompleted() => WriteProgressMarker(PreparationPath);

    public static int GetFeatureTourStep()
    {
        try
        {
            return File.Exists(FeatureTourPath) &&
                   int.TryParse(File.ReadAllText(FeatureTourPath).Trim(), out var step)
                ? Math.Clamp(step, 0, 5)
                : 0;
        }
        catch
        {
            return 0;
        }
    }

    public static void SetFeatureTourStep(int step)
    {
        try
        {
            Directory.CreateDirectory(DesktopAppConfig.ConfigDirectory);
            File.WriteAllText(FeatureTourPath, Math.Clamp(step, 0, 5).ToString());
        }
        catch
        {
            // Progress can be reconstructed from the current product state.
        }
    }

    public static bool IsDeferred() => FileExists(DeferredPath);

    public static void MarkDeferred() => WriteProgressMarker(DeferredPath);

    public static void ClearDeferred() => TryDelete(DeferredPath);

    public static bool IsHintCompleted(string hintId)
    {
        try
        {
            return File.Exists(GetHintPath(hintId));
        }
        catch
        {
            return false;
        }
    }

    public static void MarkHintCompleted(string hintId)
    {
        try
        {
            Directory.CreateDirectory(DesktopAppConfig.ConfigDirectory);
            File.WriteAllText(GetHintPath(hintId), DateTimeOffset.UtcNow.ToString("O"));
        }
        catch
        {
            // Context hints are optional and should never block interaction.
        }
    }

    private static string GetHintPath(string hintId)
    {
        var safeHintId = hintId.Replace('.', '-').Replace('/', '-').Replace('\\', '-');
        return Path.Combine(DesktopAppConfig.ConfigDirectory, $"guide-{safeHintId}.complete");
    }

    private static bool FileExists(string path)
    {
        try
        {
            return File.Exists(path);
        }
        catch
        {
            return false;
        }
    }

    private static void WriteProgressMarker(string path)
    {
        try
        {
            Directory.CreateDirectory(DesktopAppConfig.ConfigDirectory);
            File.WriteAllText(path, DateTimeOffset.UtcNow.ToString("O"));
        }
        catch
        {
            // Progress is optional and must never block normal application use.
        }
    }

    private static void TryDelete(string path)
    {
        try
        {
            if (File.Exists(path))
            {
                File.Delete(path);
            }
        }
        catch
        {
            // Completion is authoritative even if stale progress cleanup fails.
        }
    }
}
