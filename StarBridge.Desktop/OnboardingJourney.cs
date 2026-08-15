namespace StarBridge.Desktop;

internal enum OnboardingJourneyChapter
{
    Login,
    Account,
    Settings,
    ProfileAndHangar,
    Friends,
    Fleet,
    Rooms,
    Overlay,
    Support,
    Complete
}

internal readonly record struct OnboardingJourneyStage(
    OnboardingJourneyChapter Chapter,
    int AuthenticatedIndex,
    int AuthenticatedTotal,
    bool AllowsFreeInteraction,
    bool CanPause,
    bool RequiresTargetAction);

internal static class OnboardingJourney
{
    private static readonly OnboardingJourneyChapter[] AuthenticatedChapters =
    [
        OnboardingJourneyChapter.Account,
        OnboardingJourneyChapter.Settings,
        OnboardingJourneyChapter.ProfileAndHangar,
        OnboardingJourneyChapter.Friends,
        OnboardingJourneyChapter.Fleet,
        OnboardingJourneyChapter.Rooms,
        OnboardingJourneyChapter.Overlay,
        OnboardingJourneyChapter.Support
    ];

    public static int AuthenticatedChapterCount => AuthenticatedChapters.Length;

    public static OnboardingJourneyStage Resume(bool isLoggedIn, int savedChapterIndex)
    {
        if (!isLoggedIn)
        {
            return Create(OnboardingJourneyChapter.Login, authenticatedIndex: -1);
        }

        var index = Math.Clamp(savedChapterIndex, 0, AuthenticatedChapters.Length);
        return index == AuthenticatedChapters.Length
            ? Create(OnboardingJourneyChapter.Complete, index)
            : Create(AuthenticatedChapters[index], index);
    }

    public static OnboardingJourneyStage Next(OnboardingJourneyStage current, bool isLoggedIn)
    {
        if (!isLoggedIn)
        {
            return Create(OnboardingJourneyChapter.Login, authenticatedIndex: -1);
        }

        if (current.Chapter == OnboardingJourneyChapter.Login)
        {
            return Resume(isLoggedIn: true, savedChapterIndex: 0);
        }

        return Resume(isLoggedIn: true, savedChapterIndex: current.AuthenticatedIndex + 1);
    }

    public static OnboardingJourneyStage Previous(OnboardingJourneyStage current)
    {
        if (current.AuthenticatedIndex <= 0)
        {
            return Resume(isLoggedIn: true, savedChapterIndex: 0);
        }

        return Resume(isLoggedIn: true, savedChapterIndex: current.AuthenticatedIndex - 1);
    }

    private static OnboardingJourneyStage Create(OnboardingJourneyChapter chapter, int authenticatedIndex) =>
        new(
            chapter,
            authenticatedIndex,
            AuthenticatedChapters.Length,
            AllowsFreeInteraction: chapter != OnboardingJourneyChapter.Login,
            CanPause: true,
            RequiresTargetAction: chapter == OnboardingJourneyChapter.Login);
}
