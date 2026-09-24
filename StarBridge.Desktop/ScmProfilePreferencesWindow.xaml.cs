namespace StarBridge.Desktop;

using StarBridge.Core.Profiles;
using StarBridge.HostRuntime.Auth;
using System.Windows;

public partial class ScmProfilePreferencesWindow : Window
{
    private sealed record LocaleOption(string Label, string? Value)
    {
        public override string ToString() => Label;
    }

    private sealed record TimeZoneOption(string Label, string? Value)
    {
        public override string ToString() => Label;
    }

    private readonly string? _initialLocale;
    private readonly string? _initialTimeZone;

    public ScmProfilePreferencesWindow(
        string? locale,
        string? timeZone,
        IReadOnlyList<ScmTimeZoneDirectoryEntry> timeZones)
    {
        InitializeComponent();
        ArgumentNullException.ThrowIfNull(timeZones);
        _initialLocale = ScmProfileContractPolicy.NormalizeLocale(locale);
        _initialTimeZone = ScmProfileContractPolicy.NormalizeIanaTimeZone(timeZone);
        LocaleBox.ItemsSource = new[]
        {
            new LocaleOption("未设置（跟随 SCM 默认）", null),
            new LocaleOption("简体中文（zh-CN）", "zh-CN"),
            new LocaleOption("English (en-US)", "en-US")
        };
        LocaleBox.SelectedIndex = _initialLocale?.Equals("zh-CN", StringComparison.OrdinalIgnoreCase) == true
            ? 1
            : _initialLocale?.Equals("en-US", StringComparison.OrdinalIgnoreCase) == true ? 2 : 0;

        var options = new List<TimeZoneOption>
        {
            new("未设置（跟随 SCM 默认）", null)
        };
        options.AddRange(timeZones.Select(entry =>
            new TimeZoneOption($"{entry.Label} · {entry.Value}", entry.Value)));
        if (_initialTimeZone is not null &&
            options.All(option => !string.Equals(option.Value, _initialTimeZone, StringComparison.Ordinal)))
        {
            options.Insert(1, new TimeZoneOption(
                $"当前保存值（目录已停用） · {_initialTimeZone}",
                _initialTimeZone));
        }

        TimeZoneBox.ItemsSource = options;
        TimeZoneBox.SelectedItem = options.First(option =>
            string.Equals(option.Value, _initialTimeZone, StringComparison.Ordinal));
    }

    public string? SelectedLocale { get; private set; }

    public string? SelectedTimeZone { get; private set; }

    public bool LocaleChanged { get; private set; }

    public bool TimeZoneChanged { get; private set; }

    private void SaveButton_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            SelectedLocale = ScmProfileContractPolicy.NormalizeLocale(
                (LocaleBox.SelectedItem as LocaleOption)?.Value);
            SelectedTimeZone = ScmProfileContractPolicy.NormalizeIanaTimeZone(
                (TimeZoneBox.SelectedItem as TimeZoneOption)?.Value);
            LocaleChanged = !string.Equals(SelectedLocale, _initialLocale, StringComparison.Ordinal);
            TimeZoneChanged = !string.Equals(SelectedTimeZone, _initialTimeZone, StringComparison.Ordinal);
            if (!LocaleChanged && !TimeZoneChanged)
            {
                ValidationText.Text = "没有需要保存的更改。";
                return;
            }

            DialogResult = true;
        }
        catch (ArgumentException exception)
        {
            ValidationText.Text = exception.Message;
        }
    }
}
