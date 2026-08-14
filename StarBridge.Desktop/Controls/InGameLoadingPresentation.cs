namespace StarBridge.Desktop.Controls;

using System.Windows;
using System.Windows.Controls;

internal static class InGameLoadingPresentation
{
    internal static void Apply(
        TextBlock statusText,
        BridgeLoadingIndicator indicator,
        string text,
        bool isLoading)
    {
        ArgumentNullException.ThrowIfNull(statusText);
        statusText.Text = text ?? "";
        Apply(indicator, isLoading);
    }

    internal static void Apply(
        BridgeLoadingIndicator indicator,
        bool isLoading)
    {
        ArgumentNullException.ThrowIfNull(indicator);
        indicator.IsActive = isLoading;
        indicator.Visibility = isLoading
            ? Visibility.Visible
            : Visibility.Collapsed;
    }
}
