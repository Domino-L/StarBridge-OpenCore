namespace StarBridge.Desktop;

using StarBridge.HostRuntime.Overlay;

public sealed partial class NativeInformationOverlayRuntime
{
    private bool RefreshPresentationLanguage()
    {
        if (_workspace is null || _languageProvider is null) return false;
        string language;
        try { language = InformationOverlayLanguage.Resolve(_languageProvider()); }
        catch { return false; } // An unavailable preference read cannot close the overlay.
        if (language == _workspace.Language) return false;
        _workspace = _workspace with { Language = language };
        return true;
    }
}
