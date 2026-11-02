namespace StarBridge.Desktop;

using StarBridge.Core.Tools;
using StarBridge.HostRuntime.Notifications;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Shapes;
using System.Windows.Threading;

/// <summary>Live, typed hangar content shared by the actual native card and offline rendering.</summary>
internal sealed class ExecHangarNotificationPanel : StackPanel
{
    private readonly ExecHangarNotificationContent _content;
    private readonly Func<string, string, string, string> _local;
    private readonly TextBlock _title, _remaining, _phase, _time;
    private readonly Ellipse[] _lights;
    private readonly DispatcherTimer _timer;
    private readonly bool _light;
    private readonly bool _compact;
    internal ExecHangarNotificationPanel(ExecHangarNotificationContent content, string locale, bool light,
        Brush primary, Brush secondary, Brush accent, Func<bool> current, Action dismiss, bool compact = false)
    {
        _content = content; _light = light; _compact = compact;
        _local = (cn, tw, en) => !locale.StartsWith("zh", StringComparison.OrdinalIgnoreCase) ? en : locale is "zh-TW" or "zh-Hant" ? tw : cn;
        Margin = compact ? new(0) : new(0, 7, 0, 0);
        TextBlock Line(string name, double size, Brush brush, bool bold = false) => new() {
            Name = name, Foreground = brush, FontSize = size,
            TextWrapping = compact ? TextWrapping.NoWrap : TextWrapping.Wrap,
            TextTrimming = TextTrimming.CharacterEllipsis,
            FontFamily = new("Segoe UI, Microsoft YaHei UI"), FontWeight = bold ? FontWeights.SemiBold : FontWeights.Normal,
            Margin = new(0, 0, 0, compact ? 2 : 5)
        };
        _title = Line("HangarTarget", compact ? 13 : 15, primary, true); Children.Add(_title);
        var row = new StackPanel { Orientation = Orientation.Horizontal, Margin = new(0, 1, 0, 7) };
        _lights = Enumerable.Range(0, 5).Select(_ => new Ellipse { Width = compact ? 8 : 11, Height = compact ? 8 : 11, Margin = new(0, 0, compact ? 4 : 6, 0) }).ToArray();
        foreach (var lamp in _lights) row.Children.Add(lamp);
        _phase = Line("HangarPhase", 11, secondary); _phase.Margin = new(8,0,0,0); row.Children.Add(_phase); Children.Add(row);
        _remaining = Line("HangarRemaining", compact ? 16 : 22, primary, true); Children.Add(_remaining);
        _time = Line("HangarBoundary", compact ? 11 : 12, secondary);
        if (compact) {
            Children.Remove(row); row.Margin = new(0); _phase.Margin = new(4,0,0,0);
            var detail = new Grid();
            detail.ColumnDefinitions.Add(new() { Width = GridLength.Auto });
            detail.ColumnDefinitions.Add(new() { Width = new(1, GridUnitType.Star) });
            detail.Children.Add(row); Grid.SetColumn(_time, 1);
            _time.Margin = new(8,0,0,0); _time.HorizontalAlignment = HorizontalAlignment.Right;
            detail.Children.Add(_time); Children.Add(detail);
        } else Children.Add(_time);
        if (!compact && content.MonitoringEndsAt is {} end) {
            var monitor = Line("HangarMonitorEnd", 11, secondary);
            var clock = end.ToLocalTime().ToString("HH:mm:ss");
            monitor.Text = _local($"监测至 {clock}", $"監測至 {clock}", $"Monitoring until {clock}"); Children.Add(monitor);
        }
        if (!compact && content.Mute is not null) {
            var mute = DesktopNotificationCard.MakeButton(_local("本次事件不再提醒", "本次事件不再提醒", "Skip this event"), secondary,
                () => { if (current()) content.Mute(); dismiss(); }, light);
            mute.Name = "MuteHangarEvent"; mute.HorizontalAlignment = HorizontalAlignment.Left; mute.Margin = new(-7,0,0,0);
            mute.ToolTip = _local("关闭本次事件的卡片和声音提醒", "關閉本次事件的卡片與聲音提醒", "Skip this event's card and sound reminders");
            AutomationProperties.SetName(mute, mute.Content.ToString()); Children.Add(mute);
        }
        _timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
        _timer.Tick += (_, _) => Update(DateTimeOffset.Now);
        Loaded += (_, _) => { Update(DateTimeOffset.Now); _timer.Start(); };
        Unloaded += (_, _) => _timer.Stop();
        Update(DateTimeOffset.Now);
    }
    internal void Update(DateTimeOffset now)
    {
        var happened = now >= _content.Boundary;
        _title.Text = happened
            ? _content.Opening ? _local("行政机库已开启", "行政機庫已開啟", "Executive hangar is open") : _local("行政机库已关闭", "行政機庫已關閉", "Executive hangar is closed")
            : _content.Opening ? _local("等待行政机库开启", "等待行政機庫開啟", "Waiting for hangar opening") : _local("等待行政机库关闭", "等待行政機庫關閉", "Waiting for hangar closure");
        var target = _content.Boundary;
        ExecHangarPhase? phase = null;
        if (_content.Config is {} config) {
            var schedule = new ExecHangarSchedule(config);
            phase = schedule.Phases(now).First(p => p.Start <= now && now < p.End);
            if (happened) {
                var windows = schedule.Windows(now);
                target = phase.Open ? windows[0].Close : windows[1].Open;
            }
        }
        _phase.Text = phase is null ? _local("指示灯未获取", "指示燈未取得", "Lights unavailable") :
            phase.Open && phase.GreenLights == 0 && phase.RedLights == 0 ? _local("即将关闭", "即將關閉", "Closing soon") :
            phase.Open ? _local("开启中", "開啟中", "Open") : _local("关闭中", "關閉中", "Closed");
        if (!happened && (_content.LeaveWarning || phase is { Open: true, GreenLights: 0, RedLights: 0 }))
            _title.Text = _compact ? _local("行政机库即将关闭 · 请离场", "行政機庫即將關閉 · 請離場", "Executive hangar · Leave now")
                : _local("行政机库即将消杀，请立即离开机库", "行政機庫即將消殺，請立即離開機庫", "Hangar clearance imminent. Leave the hangar now.");
        if (_content.Test) _title.Text += _local(" · 测试", " · 測試", " · Test");
        _title.Foreground = new SolidColorBrush((Color)ColorConverter.ConvertFromString(
            !happened && (_content.LeaveWarning || phase is { Open: true, GreenLights: 0, RedLights: 0 })
                ? (_light ? "#B62F43" : "#F26D75") : (_light ? "#182E3A" : "#EAF2F6")));
        if (phase is not null) AutomationProperties.SetName(_phase, _local(
            $"{_phase.Text}，{phase.GreenLights} 盏绿灯，{phase.RedLights} 盏红灯",
            $"{_phase.Text}，{phase.GreenLights} 盞綠燈，{phase.RedLights} 盞紅燈",
            $"{_phase.Text}, {phase.GreenLights} green lights, {phase.RedLights} red lights"));
        for (var i = 0; i < 5; i++) _lights[i].Fill = new SolidColorBrush((Color)ColorConverter.ConvertFromString(
            phase is not null && i < phase.GreenLights ? (_light ? "#197844" : "#42CF7C") :
            phase is not null && i < phase.GreenLights + phase.RedLights ? (_light ? "#B62F43" : "#F26D75") : (_light ? "#B8C2C8" : "#47606E")));
        var opening = happened && phase is not null ? !phase.Open : _content.Opening;
        var duration = Duration(target - now, _local);
        _remaining.Text = happened && _content.Config is null ? _phase.Text : opening
            ? _local($"还有 {duration} 开启", $"還有 {duration} 開啟", $"Opens in {duration}")
            : _local($"还有 {duration} 关闭", $"還有 {duration} 關閉", $"Closes in {duration}");
        var clock = target.ToLocalTime().ToString("HH:mm:ss");
        _time.Text = opening ? _local($"{clock} 开启", $"{clock} 開啟", $"Opens at {clock}") : _local($"{clock} 关闭", $"{clock} 關閉", $"Closes at {clock}");
        AutomationProperties.SetName(this, $"{_title.Text}. {_phase.Text}. {_remaining.Text}. {_time.Text}");
    }
    private static string Duration(TimeSpan value, Func<string,string,string,string> local)
    {
        var seconds = Math.Max(0, (int)Math.Ceiling(value.TotalSeconds));
        if (seconds < 60) return local($"{seconds} 秒", $"{seconds} 秒", $"{seconds}s");
        var minutes = (int)Math.Ceiling(seconds / 60d); var hours = minutes / 60; var remainder = minutes % 60;
        return hours == 0 ? local($"{minutes} 分钟", $"{minutes} 分鐘", $"{minutes}m") : remainder == 0
            ? local($"{hours} 小时", $"{hours} 小時", $"{hours}h") : local($"{hours} 小时 {remainder} 分钟", $"{hours} 小時 {remainder} 分鐘", $"{hours}h {remainder}m");
    }
}
