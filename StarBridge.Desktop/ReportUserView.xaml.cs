using StarBridge.Core.TrustSafety;
using StarBridge.Desktop.Theming;
using System.Windows;
using System.Windows.Controls;

namespace StarBridge.Desktop;

public sealed record ReportUserSubmission(string Reason, string Details);

public partial class ReportUserView : System.Windows.Controls.UserControl
{
    private readonly Action<ReportUserSubmission?> _complete;

    private sealed record ReasonOption(string Value, string Label)
    {
        public override string ToString() => Label;
    }

    public string Reason => ReasonComboBox.SelectedItem is ReasonOption option ? option.Value : "";
    public string Details => DetailsTextBox.Text.Trim();

    public ReportUserView(
        string targetDisplayName,
        Action<ReportUserSubmission?> complete,
        string? title = null,
        string? description = null)
    {
        InitializeComponent();
        BridgeSceneContext.ApplyFixed(this, BridgeSceneKind.Review);
        _complete = complete;
        TargetNameText.Text = targetDisplayName;
        if (!string.IsNullOrWhiteSpace(title))
        {
            HeadingText.Text = title.Trim();
        }

        if (!string.IsNullOrWhiteSpace(description))
        {
            DescriptionText.Text = description.Trim();
        }
        ReasonComboBox.ItemsSource = new[]
        {
            new ReasonOption(ReportReasons.Harassment, "骚扰或辱骂"),
            new ReasonOption(ReportReasons.Spam, "垃圾信息"),
            new ReasonOption(ReportReasons.Impersonation, "冒充他人"),
            new ReasonOption(ReportReasons.HateOrThreat, "仇恨或威胁"),
            new ReasonOption(ReportReasons.InappropriateContent, "不当内容"),
            new ReasonOption(ReportReasons.FraudOrScam, "欺诈或诈骗"),
            new ReasonOption(ReportReasons.Privacy, "侵犯隐私"),
            new ReasonOption(ReportReasons.Other, "其他问题")
        };
    }

    private void DetailsTextBox_TextChanged(object sender, System.Windows.Controls.TextChangedEventArgs e)
    {
        DetailsCountText.Text = $"{DetailsTextBox.Text.Length} / {ReportValidation.MaximumDetailsLength}";
    }

    private void CancelButton_Click(object sender, RoutedEventArgs e)
    {
        _complete(null);
    }

    private void SubmitButton_Click(object sender, RoutedEventArgs e)
    {
        if (ReasonComboBox.SelectedItem is null)
        {
            ReasonComboBox.Focus();
            return;
        }

        _complete(new ReportUserSubmission(Reason, Details));
    }
}
