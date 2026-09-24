using StarBridge.HostRuntime.Auth;
using System.Windows;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Threading;
using WpfBrush = System.Windows.Media.Brush;
using WpfBrushes = System.Windows.Media.Brushes;
using WpfKeyEventArgs = System.Windows.Input.KeyEventArgs;

namespace StarBridge.Desktop;

public partial class GameIdentityVerificationWindow : Window
{
    private readonly OAuthPkceClient _client;
    private readonly ScmOAuthSession _session;
    private readonly ScmGameIdentityVerificationCoordinator _verificationCoordinator;
    private readonly CancellationTokenSource _lifetimeCancellation = new();
    private readonly DispatcherTimer _expirationTimer = new() { Interval = TimeSpan.FromSeconds(1) };
    private DateTimeOffset _expiresAt;
    private bool _isVerifyStep;
    private bool _isBusy;
    private bool _isClosed;

    public GameIdentityVerificationWindow(OAuthPkceClient client, ScmOAuthSession session)
    {
        _client = client;
        _session = session;
        _verificationCoordinator = new ScmGameIdentityVerificationCoordinator(client);
        InitializeComponent();
        _expirationTimer.Tick += ExpirationTimer_Tick;
        Loaded += (_, _) => GameNameBox.Focus();
    }

    protected override void OnSourceInitialized(EventArgs e)
    {
        base.OnSourceInitialized(e);
        MainWindowPlacementService.FitInitialWindow(this);
    }

    protected override void OnClosed(EventArgs e)
    {
        _isClosed = true;
        _lifetimeCancellation.Cancel();
        _expirationTimer.Stop();
        base.OnClosed(e);
        _lifetimeCancellation.Dispose();
    }

    private async void PrimaryButton_Click(object sender, RoutedEventArgs e)
    {
        if (_isBusy)
        {
            return;
        }

        if (_isVerifyStep)
        {
            await VerifyAsync();
        }
        else
        {
            await RequestCodeAsync();
        }
    }

    private async Task RequestCodeAsync()
    {
        var gameName = GameNameBox.Text.Trim();
        if (gameName.Length < 3)
        {
            SetStatus("RSI Handle 至少需要 3 个字符。", isError: true);
            GameNameBox.Focus();
            return;
        }

        SetBusy(true, "获取中...");
        SetStatus("正在向 SCM 申请一次性验证码...");
        try
        {
            using var requestCancellation =
                CancellationTokenSource.CreateLinkedTokenSource(_lifetimeCancellation.Token);
            requestCancellation.CancelAfter(TimeSpan.FromSeconds(30));
            var result = await _client.GetGameIdentityVerificationCodeAsync(
                _session, gameName, requestCancellation.Token);
            if (_isClosed)
            {
                return;
            }
            if (!result.Available || !result.Success || string.IsNullOrWhiteSpace(result.VerificationCode))
            {
                SetStatus(result.Message ?? "SCM 暂时无法生成验证码，请稍后重试。", isError: true);
                return;
            }

            VerificationCodeText.Text = result.VerificationCode;
            _expiresAt = DateTimeOffset.UtcNow.AddSeconds(Math.Max(1, result.ExpireTime));
            _expirationTimer.Start();
            ShowVerifyStep();
            var copied = await CopyVerificationCodeAsync(showStatus: false);
            SetStatus(
                copied
                    ? "验证码已复制。写入 RSI Short Bio 并保存后，在此提交验证。"
                    : "验证码已生成，但自动复制失败。请点击复制按钮后再继续。",
                isError: !copied,
                isSuccess: copied);
            ContactBox.Focus();
        }
        catch (OperationCanceledException) when (_lifetimeCancellation.IsCancellationRequested)
        {
        }
        catch (OperationCanceledException)
        {
            if (!_isClosed)
            {
                SetStatus("获取验证码超时，入口已解锁，请重试。", isError: true);
            }
        }
        catch (Exception exception)
        {
            if (!_isClosed)
            {
                SetStatus(UserFacingError.Describe(exception, "无法获取 SCM 验证码，请稍后重试。"), isError: true);
            }
        }
        finally
        {
            if (!_isClosed)
            {
                SetBusy(false);
            }
        }
    }

    private async Task VerifyAsync()
    {
        if (DateTimeOffset.UtcNow >= _expiresAt)
        {
            SetStatus("验证码已过期，请返回上一步重新获取。", isError: true);
            PrimaryButton.IsEnabled = false;
            return;
        }

        var contact = ContactBox.Text.Trim();
        if (contact.Length < 7)
        {
            SetStatus("联系方式至少需要 7 个字符。", isError: true);
            ContactBox.Focus();
            return;
        }

        SetBusy(true, "验证中...");
        SetStatus("正在读取公开 RSI 个人资料并核对验证码...");
        try
        {
            var attempt = await _verificationCoordinator.VerifyAsync(
                _session,
                GameNameBox.Text.Trim(),
                contact,
                _lifetimeCancellation.Token);
            if (_isClosed)
            {
                return;
            }

            if (!attempt.Accepted)
            {
                SetStatus(attempt.Message ?? "SCM 未能完成游戏身份验证。", isError: true);
                return;
            }

            VerifiedSession = attempt.ActiveSession;
            _expirationTimer.Stop();
            DialogResult = true;
        }
        catch (OperationCanceledException) when (_lifetimeCancellation.IsCancellationRequested)
        {
        }
        catch (Exception exception)
        {
            if (!_isClosed)
            {
                SetStatus(UserFacingError.Describe(
                    exception,
                    "SCM 游戏身份验证状态暂时无法确认，入口已解锁，请重试。"), isError: true);
            }
        }
        finally
        {
            if (!_isClosed && DialogResult != true)
            {
                SetBusy(false);
            }
        }
    }

    private void ShowVerifyStep()
    {
        _isVerifyStep = true;
        HandleStepPanel.Visibility = Visibility.Collapsed;
        VerifyStepPanel.Visibility = Visibility.Visible;
        BackButton.Visibility = Visibility.Visible;
        PrimaryButton.Content = "提交验证";
        HandleStepMarker.BorderBrush = FindBrush("StatusSuccessBrush", WpfBrushes.SpringGreen);
        VerifyStepMarker.BorderBrush = FindBrush("AccentBrush", WpfBrushes.DeepSkyBlue);
        if (VerifyStepMarker.Child is System.Windows.Controls.TextBlock label)
        {
            label.Foreground = FindBrush("PrimaryTextBrush", WpfBrushes.White);
        }
        UpdateExpirationText();
    }

    private void BackButton_Click(object sender, RoutedEventArgs e)
    {
        if (_isBusy)
        {
            return;
        }

        _isVerifyStep = false;
        _expirationTimer.Stop();
        HandleStepPanel.Visibility = Visibility.Visible;
        VerifyStepPanel.Visibility = Visibility.Collapsed;
        BackButton.Visibility = Visibility.Collapsed;
        PrimaryButton.Content = "重新获取验证码";
        PrimaryButton.IsEnabled = true;
        SetStatus("确认 Handle 后重新获取一次性验证码。");
        GameNameBox.Focus();
    }

    private async void CopyCodeButton_Click(object sender, RoutedEventArgs e) =>
        await CopyVerificationCodeAsync(showStatus: true);

    private async Task<bool> CopyVerificationCodeAsync(bool showStatus)
    {
        if (string.IsNullOrWhiteSpace(VerificationCodeText.Text))
        {
            return false;
        }

        var copied = await ClipboardTextCopy.TryWriteAsync(VerificationCodeText.Text);
        if (showStatus)
        {
            SetStatus(
                copied ? "验证码已复制。" : "无法写入剪贴板，请稍后重试。",
                isError: !copied,
                isSuccess: copied);
        }

        return copied;
    }

    private void ExpirationTimer_Tick(object? sender, EventArgs e) => UpdateExpirationText();

    private void UpdateExpirationText()
    {
        var remaining = _expiresAt - DateTimeOffset.UtcNow;
        if (remaining <= TimeSpan.Zero)
        {
            _expirationTimer.Stop();
            ExpirationText.Text = "验证码已过期";
            ExpirationText.Foreground = FindBrush("StatusDangerBrush", WpfBrushes.OrangeRed);
            PrimaryButton.IsEnabled = false;
            SetStatus("验证码已过期，请返回上一步重新获取。", isError: true);
            return;
        }

        ExpirationText.Text = $"有效期 {(int)remaining.TotalMinutes} 分 {remaining.Seconds:00} 秒";
    }

    private void SetBusy(bool isBusy, string? actionText = null)
    {
        _isBusy = isBusy;
        GameNameBox.IsEnabled = !isBusy;
        ContactBox.IsEnabled = !isBusy;
        BackButton.IsEnabled = !isBusy;
        PrimaryButton.IsEnabled = !isBusy;
        PrimaryButton.Content = isBusy
            ? actionText
            : _isVerifyStep ? "提交验证" : "获取验证码";
    }

    private void SetStatus(string message, bool isError = false, bool isSuccess = false)
    {
        StatusText.Text = message;
        StatusText.Foreground = isError
            ? FindBrush("StatusDangerBrush", WpfBrushes.OrangeRed)
            : isSuccess
                ? FindBrush("StatusSuccessBrush", WpfBrushes.SpringGreen)
                : FindBrush("MutedTextBrush", WpfBrushes.LightGray);
    }

    private WpfBrush FindBrush(string key, WpfBrush fallback) =>
        TryFindResource(key) as WpfBrush ?? fallback;

    public ScmOAuthSession? VerifiedSession { get; private set; }

    private void GameNameBox_KeyDown(object sender, WpfKeyEventArgs e)
    {
        if (e.Key == Key.Enter)
        {
            e.Handled = true;
            _ = RequestCodeAsync();
        }
    }

    private void ContactBox_KeyDown(object sender, WpfKeyEventArgs e)
    {
        if (e.Key == Key.Enter)
        {
            e.Handled = true;
            _ = VerifyAsync();
        }
    }

    private void Header_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (e.LeftButton == MouseButtonState.Pressed)
        {
            DragMove();
        }
    }

    private void CloseButton_Click(object sender, RoutedEventArgs e)
    {
        _lifetimeCancellation.Cancel();
        Close();
    }
}
