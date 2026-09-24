using System;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Media;
using StarBridge.HostRuntime.Auth;

namespace StarBridge.Desktop;

public sealed record LoginWindowAuthRequest(
    string Email,
    string Password);

public sealed record LoginWindowAuthResult(
    bool Success,
    string Message);

public sealed record LoginWindowPasswordResetRequest(
    string Email,
    string VerificationCode,
    string NewPassword);

public sealed record LoginWindowScmAuthResult(
    bool Success,
    string Message,
    ScmOAuthSession? Session = null);

public partial class LoginWindow : Window
{
    private bool _isBusy;
    private bool _isRecoveryMode;
    private bool _isClosed;
    private CancellationTokenSource? _scmLoginCancellation;

    public Func<string, Task<string>>? SendPasswordResetCodeAsync { get; set; }

    public Func<LoginWindowAuthRequest, Task<LoginWindowAuthResult>>? AuthenticateAsync { get; set; }

    public Func<LoginWindowPasswordResetRequest, Task<LoginWindowAuthResult>>? ResetPasswordAsync { get; set; }

    public Func<CancellationToken, Task<LoginWindowScmAuthResult>>? AuthenticateWithScmAsync { get; set; }

    public LoginWindow(string? loginEmail)
    {
        InitializeComponent();
        LoginEmailBox.Text = loginEmail ?? "";
        RecoveryEmailBox.Text = loginEmail ?? "";
        SetLoginMode();
        LoginEmailBox.Focus();
    }

    protected override void OnSourceInitialized(EventArgs e)
    {
        base.OnSourceInitialized(e);
        MainWindowPlacementService.FitInitialWindow(this);
    }

    protected override void OnClosed(EventArgs e)
    {
        _isClosed = true;
        _scmLoginCancellation?.Cancel();
        base.OnClosed(e);
    }

    public bool IsSkipped { get; private set; }

    public ScmOAuthSession? ScmSession { get; private set; }

    public string LoginEmail => LoginEmailBox.Text.Trim();

    public string LoginPassword => LoginPasswordBox.Password;

    public string RecoveryEmail => RecoveryEmailBox.Text.Trim();

    public string RecoveryVerificationCode => RecoveryVerificationCodeBox.Text.Trim();

    public void ReportScmLoginProgress(string message)
    {
        if (!_isClosed && _scmLoginCancellation is not null)
        {
            SetStatus(message);
            Activate();
        }
    }

    private void SetLoginMode()
    {
        _isRecoveryMode = false;
        LoginPanel.Visibility = Visibility.Visible;
        RecoveryPanel.Visibility = Visibility.Collapsed;
        AccountSecurityPanel.Visibility = Visibility.Collapsed;
        ConfirmButton.Content = "登录";
        SetStatus("推荐使用 SCM 统一账号登录；没有账号可在授权页面完成 SCM 注册。");
    }

    private async void ScmLoginButton_Click(object sender, RoutedEventArgs e)
    {
        if (_scmLoginCancellation is not null)
        {
            _scmLoginCancellation.Cancel();
            return;
        }

        if (_isBusy || AuthenticateWithScmAsync is null)
        {
            SetStatus("当前未连接 SCM 登录服务。", isError: true);
            return;
        }

        var operationCancellation = new CancellationTokenSource();
        _scmLoginCancellation = operationCancellation;
        SetBusy(true, "SCM 授权");
        ScmLoginButton.Content = "取消 SCM 授权";
        SetStatus("系统浏览器已打开。请在 SCM 页面完成登录和授权，等待期间可取消。");
        try
        {
            var result = await AuthenticateWithScmAsync(operationCancellation.Token);
            if (_isClosed)
            {
                return;
            }
            SetStatus(result.Message, !result.Success);
            if (result.Success && result.Session is not null)
            {
                ScmSession = result.Session;
                DialogResult = true;
            }
        }
        catch (OperationCanceledException)
        {
            if (!_isClosed)
            {
                SetStatus("已取消 SCM 授权，可重新发起。");
            }
        }
        catch (Exception exception)
        {
            if (!_isClosed)
            {
                SetStatus(UserFacingError.Describe(exception, "SCM 登录未完成，请稍后重试。"), isError: true);
            }
        }
        finally
        {
            if (ReferenceEquals(_scmLoginCancellation, operationCancellation))
            {
                _scmLoginCancellation = null;
            }
            operationCancellation.Dispose();
            if (!_isClosed && DialogResult != true)
            {
                SetBusy(false);
                ScmLoginButton.Content = "使用 SCM 账号登录";
            }
        }
    }

    private void ForgotPasswordButton_Click(object sender, RoutedEventArgs e)
    {
        if (_isBusy)
        {
            return;
        }

        RecoveryEmailBox.Text = LoginEmail;
        SetRecoveryMode();
        RecoveryEmailBox.Focus();
    }

    private void SetRecoveryMode()
    {
        _isRecoveryMode = true;
        LoginPanel.Visibility = Visibility.Collapsed;
        RecoveryPanel.Visibility = Visibility.Visible;
        AccountSecurityPanel.Visibility = Visibility.Collapsed;
        ConfirmButton.Content = "重置密码";
        SetStatus("验证旧账号邮箱后即可设置新密码。验证码 10 分钟内有效。");
    }

    private void SecurityMeasuresButton_Click(object sender, RoutedEventArgs e)
    {
        StarBridgeMessageBox.Show(
            this,
            "登录 StarBridge 不需要 RSI 账户，也不会要求你提供 RSI 密码、验证码或登录凭据。\n\n" +
            "登录信息只通过加密连接传输。服务器不会保存明文密码，而是为每个密码使用独立盐值和 Argon2id 单向哈希保护。\n\n" +
            "邮箱验证码在 10 分钟内有效、仅可使用一次，并限制错误尝试次数。会话令牌为随机生成，服务器仅保存摘要；本机登录凭证由 Windows 当前用户加密保护。\n\n" +
            "密码、验证码和访问令牌不会写入应用日志。StarBridge 不会通过邮件、短信或客服向你索取密码。",
            "账户安全措施",
            MessageBoxButton.OK,
            MessageBoxImage.Information);
    }

    private void PrivacyDataUseButton_Click(object sender, RoutedEventArgs e)
    {
        StarBridgeMessageBox.Show(
            this,
            "旧 StarBridge 账号邮箱仅用于登录验证、密码找回和必要的账户安全通知，不会向组织成员公开。\n\n" +
            "呼号、游戏 ID、公开资料和协作状态只会按你选择的可见范围显示。在“同步与隐私”中可以单独管理在线、飞船、地点、服务器、事件、机库和游玩统计。\n\n" +
            "好友私信、组织聊天和房间聊天会保存于 StarBridge 服务，仅对应会话或组织的可见成员可以查看。\n\n" +
            "主动提交举报或申诉时，相关内容、对象快照和处理记录会保存在 StarBridge 服务；证据仅授权审核账号可见。\n\n" +
            "Game.log 在你的电脑上以只读方式处理，原始日志不会作为状态同步上传。诊断记录只在你主动提交反馈时离开设备。\n\n" +
            "RSI 官网登录凭据不属于 StarBridge 的数据范围：应用不会要求、读取或保存这些凭据。",
            "隐私与数据使用",
            MessageBoxButton.OK,
            MessageBoxImage.Information);
    }

    private async void ConfirmButton_Click(object sender, RoutedEventArgs e)
    {
        if (_isBusy)
        {
            return;
        }

        if (_isRecoveryMode)
        {
            await ConfirmPasswordResetAsync();
            return;
        }

        var request = BuildAuthRequest();
        if (request is null)
        {
            return;
        }

        if (AuthenticateAsync is null)
        {
            SetStatus("当前未连接登录服务。", isError: true);
            return;
        }

        SetBusy(true, "登录中...");
        try
        {
            var result = await AuthenticateAsync(request);
            SetStatus(result.Message, !result.Success);
            if (result.Success)
            {
                DialogResult = true;
            }
        }
        catch (Exception ex)
        {
            SetStatus(UserFacingError.Describe(ex, "暂时无法登录，请稍后重试。"), isError: true);
        }
        finally
        {
            if (DialogResult != true)
            {
                SetBusy(false);
            }
        }
    }

    private async Task ConfirmPasswordResetAsync()
    {
        var email = RecoveryEmail;
        var verificationCode = RecoveryVerificationCode;
        var password = RecoveryPasswordBox.Password;
        var confirmPassword = RecoveryConfirmPasswordBox.Password;
        if (string.IsNullOrWhiteSpace(email) || !LooksLikeEmail(email))
        {
            SetStatus("请输入有效的旧账号邮箱。", isError: true);
            return;
        }

        if (string.IsNullOrWhiteSpace(verificationCode))
        {
            SetStatus("请输入邮箱验证码。", isError: true);
            return;
        }

        if (!StarBridge.Core.Identity.AccountPasswordPolicy.IsValidLength(password))
        {
            SetStatus("新密码需要 8 到 128 个字符。", isError: true);
            return;
        }

        if (!string.Equals(password, confirmPassword, StringComparison.Ordinal))
        {
            SetStatus("两次输入的密码不一致。", isError: true);
            return;
        }

        if (ResetPasswordAsync is null)
        {
            SetStatus("当前未连接密码重置服务。", isError: true);
            return;
        }

        SetBusy(true, "重置中...");
        try
        {
            var result = await ResetPasswordAsync(new LoginWindowPasswordResetRequest(email, verificationCode, password));
            if (!result.Success)
            {
                SetStatus(result.Message, isError: true);
                return;
            }

            LoginEmailBox.Text = email;
            LoginPasswordBox.Clear();
            RecoveryVerificationCodeBox.Clear();
            RecoveryPasswordBox.Clear();
            RecoveryConfirmPasswordBox.Clear();
            SetLoginMode();
            SetStatus("密码已重置，请使用新密码登录。");
            LoginPasswordBox.Focus();
        }
        catch (Exception ex)
        {
            SetStatus(UserFacingError.Describe(ex, "暂时无法重置密码，请稍后重试。"), isError: true);
        }
        finally
        {
            SetBusy(false);
        }
    }

    private LoginWindowAuthRequest? BuildAuthRequest()
    {
        var email = LoginEmail;
        var password = LoginPassword;
        if (string.IsNullOrWhiteSpace(email) || string.IsNullOrWhiteSpace(password))
        {
            SetStatus("请输入登录邮箱和密码。", isError: true);
            return null;
        }

        if (!LooksLikeEmail(email))
        {
            SetStatus("请输入有效的邮箱地址。", isError: true);
            return null;
        }

        return new LoginWindowAuthRequest(email, password);
    }

    private async void RecoverySendCodeButton_Click(object sender, RoutedEventArgs e)
    {
        if (_isBusy)
        {
            return;
        }

        if (SendPasswordResetCodeAsync is null)
        {
            SetStatus("当前未连接密码重置服务。", isError: true);
            return;
        }

        var email = RecoveryEmail;
        if (string.IsNullOrWhiteSpace(email) || !LooksLikeEmail(email))
        {
            SetStatus("请输入有效的旧账号邮箱。", isError: true);
            return;
        }

        RecoverySendCodeButton.IsEnabled = false;
        RecoverySendCodeButton.Content = "发送中...";
        SetStatus("正在申请密码重置验证码...");
        try
        {
            var message = await SendPasswordResetCodeAsync(email);
            var isError = message.Contains("失败", StringComparison.OrdinalIgnoreCase) ||
                          message.Contains("错误", StringComparison.OrdinalIgnoreCase) ||
                          message.Contains("不可用", StringComparison.OrdinalIgnoreCase);
            SetStatus(message, isError);
            if (!isError)
            {
                await RunSendCodeCooldownAsync(RecoverySendCodeButton);
                return;
            }
        }
        catch (Exception ex)
        {
            SetStatus(UserFacingError.Describe(ex, "验证码未发送，请稍后重试。"), isError: true);
        }
        finally
        {
            RecoverySendCodeButton.Content = "发送验证码";
            RecoverySendCodeButton.IsEnabled = true;
        }
    }

    private static async Task RunSendCodeCooldownAsync(System.Windows.Controls.Button button)
    {
        for (var remaining = 60; remaining > 0; remaining--)
        {
            button.Content = $"{remaining}s";
            await Task.Delay(1000);
        }
    }

    private void SkipButton_Click(object sender, RoutedEventArgs e)
    {
        if (_isBusy)
        {
            return;
        }

        IsSkipped = true;
        DialogResult = true;
    }

    private void CloseButton_Click(object sender, RoutedEventArgs e)
    {
        if (_scmLoginCancellation is not null)
        {
            _scmLoginCancellation.Cancel();
            DialogResult = false;
            return;
        }

        if (!_isBusy)
        {
            DialogResult = false;
        }
    }

    private void SetBusy(bool isBusy, string? buttonText = null)
    {
        _isBusy = isBusy;
        SkipButton.IsEnabled = !isBusy;
        CloseDialogButton.IsEnabled = !isBusy || _scmLoginCancellation is not null;
        ConfirmButton.IsEnabled = !isBusy;
        RecoverySendCodeButton.IsEnabled = !isBusy && _isRecoveryMode;
        ConfirmButton.Content = buttonText ?? (_isRecoveryMode ? "重置密码" : "登录");
    }

    private void SetStatus(string message, bool isError = false)
    {
        HintText.Text = message;
        HintText.Foreground = (System.Windows.Media.Brush)FindResource(isError ? "DangerBrush" : "MutedTextBrush");
    }

    private static bool LooksLikeEmail(string value)
    {
        var trimmed = value.Trim();
        var atIndex = trimmed.IndexOf('@');
        return atIndex > 0 &&
               atIndex < trimmed.Length - 3 &&
               trimmed.LastIndexOf('.') > atIndex + 1;
    }
}
