namespace StarBridge.Desktop;

using StarBridge.Core.Profiles;
using StarBridge.HostRuntime.Auth;
using System.IO;
using System.Net.Http;
using System.Windows;

public partial class MainWindow
{
    private void LoadCachedScmProfileForActiveRoute()
    {
        if (_scmProfile is not null)
        {
            return;
        }

        var route = CurrentAccountRouteIdentity;
        var cached = _scmProfileCacheStore.Load(route);
        if (cached is null)
        {
            return;
        }

        _scmProfile = cached.ToOfflineProfile();
        _scmProfileLoadedFromCache = true;
    }

    private void PublishScmProfile(
        ScmSelfProfileContract profile,
        bool loadedFromCache,
        bool persist)
    {
        var normalized = profile.Normalize();
        var route = CurrentAccountRouteIdentity;
        if (!route.IsAuthenticated ||
            !string.Equals(route.Subject, normalized.Subject, StringComparison.Ordinal))
        {
            throw new InvalidOperationException("SCM 资料与当前账号路由不一致，已拒绝发布。");
        }

        _scmProfile = normalized;
        _scmProfileLoadedFromCache = loadedFromCache;
        if (persist)
        {
            try
            {
                _scmProfileCacheStore.Save(route, normalized, DateTimeOffset.UtcNow);
            }
            catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
            {
                ScmAuthDiagnostics.Write(
                    _scmOAuthSession?.CorrelationId ?? "profile-cache",
                    "profile-cache-save",
                    "degraded",
                    $"exceptionType={exception.GetType().Name}");
            }
        }

        RefreshPersonalIdentityConsole();
    }

    private async Task<bool> RefreshScmProfileAsync(
        ScmOAuthSession session,
        CancellationToken cancellationToken,
        ScmRuntimeRecoveryLease? recoveryLease = null)
    {
        try
        {
            var result = await _scmOAuthClient.LoadProfileAsync(session, cancellationToken);
            if (!CanPublishScmRuntimeRecovery(result.ActiveSession, recoveryLease))
            {
                return false;
            }

            ApplyScmOAuthSession(result.ActiveSession);
            PublishScmProfile(result.Profile, loadedFromCache: false, persist: true);
            return true;
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception exception) when (exception is HttpRequestException or InvalidOperationException)
        {
            ScmAuthDiagnostics.Write(
                session.CorrelationId ?? "profile-read",
                "profile-read",
                "degraded",
                $"exceptionType={exception.GetType().Name} cached={_scmProfile is not null}");
            return false;
        }
    }

    private void RefreshScmProfilePresentation()
    {
        if (PersonalScmProfileEditButton is null)
        {
            return;
        }

        var scmAuthenticated = AccountState.ScmAuthenticated;
        PersonalScmProfileEditButton.Visibility = scmAuthenticated
            ? Visibility.Visible
            : Visibility.Collapsed;
        PersonalScmProfileEditButton.IsEnabled = scmAuthenticated &&
                                                  _scmProfile is not null &&
                                                  !_scmProfileWriteInProgress;
        PersonalScmProfileEditButton.Content = _scmProfileWriteInProgress
            ? "正在保存…"
            : "资料偏好";
        PersonalScmProfileClearCacheButton.Visibility = scmAuthenticated
            ? Visibility.Visible
            : Visibility.Collapsed;
        PersonalScmProfileClearCacheButton.IsEnabled = !_scmProfileWriteInProgress;

        PersonalDisplayNameEditButton.Visibility = scmAuthenticated
            ? Visibility.Collapsed
            : AccountState.HasRelaySession ? Visibility.Visible : Visibility.Collapsed;
        if (scmAuthenticated)
        {
            PersonalDisplayNameEditBox.Visibility = Visibility.Collapsed;
            PersonalDisplayNameReadText.Visibility = Visibility.Visible;
        }

        var cacheSuffix = _scmProfileLoadedFromCache ? " · 离线缓存" : string.Empty;
        PersonalScmLocaleText.Text = _scmProfile?.Locale is { Length: > 0 } locale
            ? locale + cacheSuffix
            : "未设置" + cacheSuffix;
        PersonalScmTimeZoneText.Text = _scmProfile?.TimeZone is { Length: > 0 } timeZone
            ? timeZone + cacheSuffix
            : "未设置" + cacheSuffix;
    }

    private async void PersonalScmProfileEditButton_Click(object sender, RoutedEventArgs e)
    {
        var session = _scmOAuthSession;
        var profile = _scmProfile;
        if (session is null || profile is null || _scmProfileWriteInProgress)
        {
            return;
        }

        IReadOnlyList<ScmTimeZoneDirectoryEntry> timeZoneDirectory;
        try
        {
            timeZoneDirectory = await _scmOAuthClient.LoadTimeZoneDirectoryAsync(CancellationToken.None);
        }
        catch (Exception exception) when (exception is HttpRequestException or InvalidOperationException)
        {
            await ShowAppNoticeAsync(
                "SCM 资料偏好",
                "暂时无法读取 SCM 时区目录。",
                "资料没有被修改，请检查网络后重试。" + Environment.NewLine + exception.Message);
            return;
        }

        if (!IsCurrentScmSessionIdentity(session))
        {
            return;
        }

        var editor = new ScmProfilePreferencesWindow(
            profile.Locale,
            profile.TimeZone,
            timeZoneDirectory)
        {
            Owner = this
        };
        if (editor.ShowDialog() != true)
        {
            return;
        }

        _scmProfileWriteInProgress = true;
        RefreshScmProfilePresentation();
        try
        {
            var writeSession = await _scmOAuthClient.AuthorizeProfileWriteAsync(
                session,
                CancellationToken.None,
                progress => Dispatcher.BeginInvoke(() =>
                    _accountOperationStatusText = progress));
            if (!IsCurrentScmSessionIdentity(session) ||
                !string.Equals(writeSession.Subject, session.Subject, StringComparison.Ordinal))
            {
                throw new InvalidOperationException("账号已切换，已取消本次资料修改。");
            }

            var patch = new ScmProfilePatchContract(
                editor.LocaleChanged
                    ? ScmProfilePatchField.Set(editor.SelectedLocale)
                    : ScmProfilePatchField.Unspecified,
                editor.TimeZoneChanged
                    ? ScmProfilePatchField.Set(editor.SelectedTimeZone)
                    : ScmProfilePatchField.Unspecified);
            var result = await _scmOAuthClient.UpdateProfileAsync(
                writeSession,
                patch,
                CancellationToken.None);
            if (!IsCurrentScmSessionIdentity(session))
            {
                return;
            }

            PublishScmProfile(result.Profile, loadedFromCache: false, persist: true);
            await RefreshScmAvatarAsync(session, result.Profile.AvatarUrl, CancellationToken.None);
            await ShowAppNoticeAsync(
                "SCM 资料偏好",
                "账号资料偏好已保存。",
                "语言与时区已写入 SCM。浮层、设备和 Game.log 设置仍只保存在本机。");
        }
        catch (OperationCanceledException)
        {
            _accountOperationStatusText = "已取消 SCM 资料授权";
        }
        catch (ScmApiForbiddenException)
        {
            await ShowAppNoticeAsync(
                "SCM 资料偏好",
                "当前账号未授予资料修改权限。",
                "请重新操作并在 SCM 授权页确认 profile.write 权限；主登录凭据不会因此扩大权限。");
        }
        catch (Exception exception) when (exception is HttpRequestException or InvalidOperationException)
        {
            await ShowAppNoticeAsync(
                "SCM 资料偏好",
                "资料偏好暂时无法保存。",
                exception.Message);
        }
        finally
        {
            _scmProfileWriteInProgress = false;
            RefreshPersonalIdentityConsole();
        }
    }

    private async void PersonalScmProfileClearCacheButton_Click(object sender, RoutedEventArgs e)
    {
        var route = CurrentAccountRouteIdentity;
        var cleared = _scmProfileCacheStore.Clear(route);
        _scmProfileLoadedFromCache = false;
        RefreshScmProfilePresentation();
        await ShowAppNoticeAsync(
            "SCM 资料缓存",
            cleared ? "当前账号的离线资料缓存已清除。" : "当前账号没有可清除的离线资料缓存。",
            "当前会话已经读取的资料会继续显示；Game.log、浮层布局、设备设置和其他本机数据均未删除。");
    }
}
