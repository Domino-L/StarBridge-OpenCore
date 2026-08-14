using StarBridge.Core.Chat;
using StarBridge.Desktop.Theming;
using System.Windows;
using System.Windows.Media;
using WpfBrush = System.Windows.Media.Brush;
using WpfColor = System.Windows.Media.Color;
using WpfColorConverter = System.Windows.Media.ColorConverter;

namespace StarBridge.Desktop;

/// <summary>
/// Resolves chat-only visual data through the shared Bridge token seams.
/// Missing application tokens are configuration failures; malformed colours
/// received from external chat data safely use an already-resolved token.
/// </summary>
internal static class ChatPresentationBrushes
{
    public static WpfBrush ResolveSenderRole(
        FrameworkElement resourceScope,
        bool isLocal,
        string? publishedColor)
    {
        ArgumentNullException.ThrowIfNull(resourceScope);

        if (isLocal)
        {
            return BridgeSceneContext.GetRequiredAccentBrush(resourceScope);
        }

        var fallback = BridgeTokenBrushes.GetRequired(resourceScope, BridgeBrushToken.StatusInfo);
        if (string.IsNullOrWhiteSpace(publishedColor))
        {
            return fallback;
        }

        try
        {
            if (WpfColorConverter.ConvertFromString(publishedColor) is not WpfColor color)
            {
                return fallback;
            }

            var brush = new SolidColorBrush(color);
            brush.Freeze();
            return brush;
        }
        catch (FormatException)
        {
            return fallback;
        }
        catch (NotSupportedException)
        {
            return fallback;
        }
    }

    public static WpfBrush ResolveAttachmentStatus(
        FrameworkElement resourceScope,
        ChatAttachmentContract? attachment) =>
        BridgeTokenBrushes.GetRequired(resourceScope, ChatAttachmentPresentation.StatusToken(attachment));
}
