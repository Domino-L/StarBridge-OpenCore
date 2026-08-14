using System.Windows;
using System.Windows.Controls;
using StarBridge.Desktop.Theming;

namespace StarBridge.Desktop;

public partial class SanctionAppealView : System.Windows.Controls.UserControl
{
    private readonly Action<string?> _complete;

    public SanctionAppealView(string sanctionLabel, Action<string?> complete)
    {
        InitializeComponent();
        BridgeSceneContext.ApplyFixed(this, BridgeSceneKind.Review);
        _complete = complete;
        ContextText.Text = $"申诉对象：{sanctionLabel}。请说明你认为需要复核的事实或上下文。";
        Loaded += (_, _) => DetailsTextBox.Focus();
    }

    public string Details => DetailsTextBox.Text.Trim();

    private void SubmitButton_Click(object sender, RoutedEventArgs e)
    {
        if (string.IsNullOrWhiteSpace(Details))
        {
            ValidationText.Text = "请填写申诉理由。";
            return;
        }

        _complete(Details);
    }

    private void CancelButton_Click(object sender, RoutedEventArgs e) => _complete(null);
}
