using System.Windows;
using Brushes = System.Windows.Media.Brushes;
using Button = System.Windows.Controls.Button;

namespace StarBridge.Desktop;

public partial class MainWindow
{
    private string _fleetHeaderExternalContactsAccessibleText = "";

    private void FleetHeaderExternalContactsButton_Click(object sender, RoutedEventArgs e)
    {
        var useChinese = _language.Equals("zh", StringComparison.OrdinalIgnoreCase);
        var presentation = FleetHeaderExternalContactProjection.Project(
            _hasFleet,
            _fleetExternalContacts,
            useChinese);
        if (presentation.Entries.Count == 0)
        {
            return;
        }

        _fleetHeaderExternalContactsAccessibleText = presentation.AccessibleText;
        FleetExternalContactsDetailList.ItemsSource = presentation.Entries;
        FleetExternalContactsDetailStatusText.Text = useChinese
            ? $"共 {presentation.Entries.Count} 条舰队内部联系方式"
            : $"{presentation.Entries.Count} fleet contact entries";
        FleetExternalContactsDetailStatusText.Foreground = FindBrush("MutedTextBrush", Brushes.LightSlateGray);
        FleetExternalContactsDetailPanel.Show();
    }

    private async void CopyFleetExternalContactButton_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not Button { Tag: string value } || string.IsNullOrWhiteSpace(value))
        {
            return;
        }

        var copied = await ClipboardTextCopy.TryWriteAsync(value.Trim());
        SetFleetExternalContactsCopyStatus(
            copied,
            "该联系方式已复制。",
            "无法访问剪贴板，请手动复制。");
    }

    private async void CopyAllFleetExternalContactsButton_Click(object sender, RoutedEventArgs e)
    {
        if (string.IsNullOrWhiteSpace(_fleetHeaderExternalContactsAccessibleText))
        {
            return;
        }

        var copied = await ClipboardTextCopy.TryWriteAsync(_fleetHeaderExternalContactsAccessibleText);
        SetFleetExternalContactsCopyStatus(
            copied,
            "全部联系方式已复制。",
            "无法访问剪贴板，请逐条手动复制。");
    }

    private void SetFleetExternalContactsCopyStatus(bool copied, string successText, string failureText)
    {
        FleetExternalContactsDetailStatusText.Text = copied ? successText : failureText;
        FleetExternalContactsDetailStatusText.Foreground = copied
            ? FindBrush("StatusSuccessBrush", Brushes.SpringGreen)
            : FindBrush("StatusWarningBrush", Brushes.Goldenrod);
    }

    private void CloseFleetExternalContactsDetailButton_Click(object sender, RoutedEventArgs e)
    {
        FleetExternalContactsDetailPanel.Hide();
    }
}
