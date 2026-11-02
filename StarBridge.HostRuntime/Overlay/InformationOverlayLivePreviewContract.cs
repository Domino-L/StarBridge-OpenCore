using System.Text;
using System.Text.Json;
using StarBridge.Core.Overlay;

namespace StarBridge.HostRuntime.Overlay;

/// <summary>Finite display intent. No source binding, account, hotkey or usage
/// receipt. Settings/layout use the normal workspace codecs, not preview defaults.</summary>
public sealed class InformationOverlayLivePreviewDraft
{
    private readonly InformationOverlayLayoutItem[] _layout;
    public string AppearanceId { get; }
    public OverlayDisplaySettings Settings { get; }
    public OverlayAppearanceOptions Options { get; }
    public string Language { get; }
    public bool ReduceMotion { get; }
    public IReadOnlyList<InformationOverlayLayoutItem> CopyLayout() => _layout.Select(Copy).ToArray();

    private InformationOverlayLivePreviewDraft(string id, OverlayDisplaySettings settings,
        IReadOnlyList<InformationOverlayLayoutItem> layout, OverlayAppearanceOptions options, string language, bool reduced)
    {
        AppearanceId = id; Settings = settings; _layout = layout.Select(Copy).ToArray();
        Options = options; Language = language; ReduceMotion = reduced;
    }
    public static InformationOverlayLivePreviewDraft Parse(JsonElement value)
    {
        Exact(value, "appearanceId", "settings", "layout", "appearanceOptions", "language", "reduceMotion");
        if (Encoding.UTF8.GetByteCount(value.GetRawText()) > 64 * 1024 ||
            value.GetProperty("appearanceId").ValueKind != JsonValueKind.String ||
            value.GetProperty("language").ValueKind != JsonValueKind.String ||
            value.GetProperty("reduceMotion").ValueKind is not (JsonValueKind.True or JsonValueKind.False))
            throw new FormatException("Invalid preview frame.");
        var id = value.GetProperty("appearanceId").GetString()!;
        var language = value.GetProperty("language").GetString()!;
        if (id.Length is < 1 or > 64 || id.Any(c => !char.IsAsciiLetterOrDigit(c) && c is not ('_' or '-')) ||
            language is not ("zh" or "zh-CN" or "zh-Hant" or "en" or "en-US"))
            throw new FormatException("Invalid preview identity.");
        var layoutElement = value.GetProperty("layout");
        if (layoutElement.ValueKind != JsonValueKind.Array || layoutElement.GetArrayLength() > 8)
            throw new FormatException("Invalid preview layout.");
        var settings = OverlayWorkspaceWireProjection.ParseSettings(value.GetProperty("settings"));
        var layout = OverlayWorkspaceStore.ValidateLayout(OverlayWorkspaceWireProjection.ParseLayout(layoutElement));
        var options = OverlayAppearanceOptions.Parse(value.GetProperty("appearanceOptions").GetRawText());
        return new(id, settings, layout, options, language, value.GetProperty("reduceMotion").GetBoolean());
    }
    internal static void Exact(JsonElement value, params string[] keys)
    {
        if (value.ValueKind != JsonValueKind.Object || !value.EnumerateObject().Select(p => p.Name)
            .Order(StringComparer.Ordinal).SequenceEqual(keys.Order(StringComparer.Ordinal)))
            throw new FormatException("Invalid preview fields.");
    }
    private static InformationOverlayLayoutItem Copy(InformationOverlayLayoutItem item) => new(item.Key,
        item.X, item.Y, item.Width, item.Height, item.HorizontalAnchor, item.VerticalAnchor, item.IsLocked,
        item.TextOpacity, item.BackgroundOpacity, item.DecorationOpacity);
}

/// <summary>Host-created current-generation lease. Its callback reads current
/// in-memory identity state, never trusts a client-specified account.</summary>
public sealed class InformationOverlayLivePreviewScope(long generation, Func<bool> isCurrent,
    Func<OverlayPreviewClientViewport?>? clientViewport = null)
{
    public long Generation { get; } = generation;
    public bool IsCurrent() { try { return isCurrent(); } catch { return false; } }
    public bool HasClientViewport => clientViewport is not null;
    public OverlayPreviewClientViewport? CurrentClientViewport() { try { return clientViewport?.Invoke(); } catch { return null; } }
}

public interface IInformationOverlayLivePreviewRuntime
{
    // Detached presentation feedback for the exact applied frame; never rewrites
    // options, grants ownership or introduces appearance-specific geometry here.
    ValueTask<IReadOnlyList<OverlayAppearancePlacementState>?> ReadLivePreviewPlacementStatesAsync(
        string sessionId, long revision, CancellationToken cancellationToken = default)
        => ValueTask.FromResult<IReadOnlyList<OverlayAppearancePlacementState>?>([]);
    IReadOnlyList<string> GetLiveAppearancePreviewIds();
    ValueTask<string?> OpenLiveAppearancePreviewAsync(InformationOverlayLivePreviewDraft draft,
        InformationOverlayLivePreviewScope scope, CancellationToken cancellationToken = default);
    ValueTask<long?> UpdateLiveAppearancePreviewAsync(string sessionId, long revision,
        InformationOverlayLivePreviewDraft draft, CancellationToken cancellationToken = default);
    // Page liveness only. Never changes the frame, source demand, pet state or
    // queue. Host chooses the bounded lease; an expired session cannot revive.
    ValueTask<long?> RenewLiveAppearancePreviewAsync(string sessionId, long revision,
        CancellationToken cancellationToken = default);
    ValueTask CloseLiveAppearancePreviewAsync(string sessionId, CancellationToken cancellationToken = default);
}

public readonly record struct OverlayAppearancePlacementState(string SlotId, string Reason);

/// Normalized primary Flutter-client regions, never renderer-supplied HWNDs or
/// screen positions. Host resolves the registered current client independently.
public readonly record struct OverlayPreviewControlArea(double X, double Y, double Width, double Height)
{
    public bool IsValid => double.IsFinite(X) && double.IsFinite(Y) && double.IsFinite(Width) &&
        double.IsFinite(Height) && X >= 0 && Y >= 0 && Width > 0 && Height > 0 &&
        X + Width <= 1.000000001 && Y + Height <= 1.000000001;
}
public readonly record struct OverlayPreviewClientViewport(int X, int Y, int Width, int Height)
{
    public bool IsValid => X is >= -262144 and <= 262144 && Y is >= -262144 and <= 262144 &&
        Width is >= 1 and <= 16384 && Height is >= 1 and <= 16384;
}
public interface IInformationOverlayLivePreviewControls
{
    ValueTask<long?> ProtectLivePreviewControlsAsync(string sessionId, long revision,
        OverlayPreviewClientViewport viewport, IReadOnlyList<OverlayPreviewControlArea> areas,
        CancellationToken cancellationToken = default);
}

// Finite normal example arrivals/withdrawals. Never pet poses, free text,
// source grants, timing controls or an entitlement/usage receipt.
public enum OverlayAppearancePreviewPlayback { NoticeShow, NoticeHide, EventAdd, EventHide, EventSequence, Barrage, Stop, Transition }
public readonly record struct OverlayPreviewPlaybackReceipt(long Revision, bool Accepted);
public interface IInformationOverlayLivePreviewPlayback
{
    ValueTask<OverlayPreviewPlaybackReceipt?> PlayLivePreviewAsync(string sessionId, long revision,
        OverlayAppearancePreviewPlayback action, CancellationToken cancellationToken = default);
}
