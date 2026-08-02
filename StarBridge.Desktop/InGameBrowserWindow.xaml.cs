using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.Wpf;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Windows;
using System.Windows.Input;
using System.Windows.Threading;

namespace StarBridge.Desktop;

public partial class InGameBrowserWindow : Window
{
    private Uri _homePage;
    private bool _initialized;
    private bool _allowPermanentClose;
    private bool _bringAddButtonIntoView;
    private readonly ObservableCollection<BrowserPageSession> _pages = [];
    private InGameMenuSettings _settings = InGameMenuSettings.Default;

    internal event EventHandler? MenuCloseRequested;
    internal event EventHandler? ToolDeactivated;
    internal event EventHandler? ToolHidden;

    private BrowserPageSession ActivePage =>
        BrowserPageTabs.SelectedItem as BrowserPageSession ??
        _pages.First();

    private WebView2 BrowserView => ActivePage.View;

    internal InGameBrowserWindow(Uri? homePage = null)
    {
        _homePage = homePage ?? InGameBrowserPreferences.ResolveHomePage(null);
        InitializeComponent();
        BrowserPageTabs.ItemsSource = _pages;
        CreateBrowserPage();
        InGameToolWindowBehavior.PreventSnapMaximize(this);
        Loaded += Window_Loaded;
    }

    internal void SetHomePage(Uri homePage)
    {
        ArgumentNullException.ThrowIfNull(homePage);
        _homePage = homePage;
    }

    internal void ApplySettings(InGameMenuSettings settings)
    {
        _settings = settings.Normalize();
        NewBrowserPageButton.IsEnabled =
            _pages.Count < _settings.BrowserTabLimit;
    }

    internal void ShowForMenu()
    {
        if (WindowState == WindowState.Minimized)
        {
            WindowState = WindowState.Normal;
        }

        Show();
        Activate();
        ResumeBrowserPages();
    }

    internal void HideForMenu()
    {
        PersistLastPageIfEnabled();
        if (IsVisible)
        {
            Hide();
        }

        if (_settings.EffectivePauseBrowserWhenHidden)
        {
            _ = SuspendBrowserPagesAsync();
        }
    }

    internal async Task ClearBrowsingDataAsync()
    {
        var profiles = _pages
            .Select(page => page.View.CoreWebView2?.Profile)
            .Where(profile => profile is not null)
            .Distinct()
            .ToArray();
        foreach (var profile in profiles)
        {
            await profile!.ClearBrowsingDataAsync(
                CoreWebView2BrowsingDataKinds.AllProfile);
        }

        BrowserStatusText.Text = profiles.Length == 0
            ? "浏览器尚未启动，没有可清理的数据"
            : "浏览器数据已清理";
    }

    private async Task SuspendBrowserPagesAsync()
    {
        foreach (var page in _pages)
        {
            try
            {
                if (page.View.CoreWebView2 is { } core)
                {
                    await core.TrySuspendAsync();
                }
            }
            catch (Exception exception)
            {
                App.WriteCrashLog(exception);
            }
        }
    }

    private void ResumeBrowserPages()
    {
        foreach (var page in _pages)
        {
            try
            {
                page.View.CoreWebView2?.Resume();
            }
            catch (Exception exception)
            {
                App.WriteCrashLog(exception);
            }
        }
    }

    internal void CloseForApplication()
    {
        _allowPermanentClose = true;
        Close();
    }

    private BrowserPageSession CreateBrowserPage()
    {
        var page = new BrowserPageSession(new WebView2
        {
            DefaultBackgroundColor = System.Drawing.Color.FromArgb(255, 1, 6, 10)
        });
        _pages.Add(page);
        BrowserPageTabs.SelectedItem = page;
        _bringAddButtonIntoView = true;
        ScheduleBrowserTabLayout();
        return page;
    }

    private async Task InitializeBrowserPageAsync(
        BrowserPageSession page,
        Uri initialUri)
    {
        if (page.IsInitialized)
        {
            Navigate(page, initialUri);
            return;
        }

        if (ReferenceEquals(page, ActivePage))
        {
            LoadingOverlay.Visibility = Visibility.Visible;
        }

        try
        {
            await page.View.EnsureCoreWebView2Async();
            ConfigureBrowser(page.View.CoreWebView2);
            page.IsInitialized = true;
            if (ReferenceEquals(page, ActivePage))
            {
                LoadingOverlay.Visibility = Visibility.Collapsed;
            }

            Navigate(page, initialUri);
        }
        catch (Exception exception)
        {
            App.WriteCrashLog(exception);
            page.Title = "浏览器不可用";
            BrowserStatusText.Text = UserFacingError.Describe(
                exception,
                "浏览器未能启动，请确认 WebView2 Runtime 已安装。");
            LoadingOverlay.Visibility = Visibility.Visible;
        }
    }

    private void DisposeBrowserPage(BrowserPageSession page)
    {
        if (page.View.CoreWebView2 is { } core)
        {
            core.NavigationStarting -= Core_NavigationStarting;
            core.NavigationCompleted -= Core_NavigationCompleted;
            core.DocumentTitleChanged -= Core_DocumentTitleChanged;
            core.NewWindowRequested -= Core_NewWindowRequested;
            core.PermissionRequested -= Core_PermissionRequested;
            core.DownloadStarting -= Core_DownloadStarting;
        }

        if (BrowserHost.Children.Contains(page.View))
        {
            BrowserHost.Children.Remove(page.View);
        }

        page.View.Dispose();
    }

    private async void Window_Loaded(object sender, RoutedEventArgs e)
    {
        if (_initialized)
        {
            return;
        }

        _initialized = true;
        var initialPage = _settings.BrowserRestorePreviousPage
            ? InGameBrowserPreferences.LoadLastPage() ?? _homePage
            : _homePage;
        await InitializeBrowserPageAsync(ActivePage, initialPage);
    }

    private void ConfigureBrowser(CoreWebView2 core)
    {
        core.Settings.AreDevToolsEnabled = false;
        core.Settings.AreDefaultScriptDialogsEnabled = true;
        core.Settings.IsPasswordAutosaveEnabled = false;
        core.Settings.IsGeneralAutofillEnabled = false;
        core.NavigationStarting += Core_NavigationStarting;
        core.NavigationCompleted += Core_NavigationCompleted;
        core.DocumentTitleChanged += Core_DocumentTitleChanged;
        core.NewWindowRequested += Core_NewWindowRequested;
        core.PermissionRequested += Core_PermissionRequested;
        core.DownloadStarting += Core_DownloadStarting;
        RefreshButton.IsEnabled = true;
    }

    protected override void OnClosed(EventArgs e)
    {
        PersistLastPageIfEnabled();
        foreach (var page in _pages.ToArray())
        {
            DisposeBrowserPage(page);
        }

        _pages.Clear();
        base.OnClosed(e);
    }

    private void PersistLastPageIfEnabled()
    {
        if (!_settings.BrowserRestorePreviousPage ||
            _pages.Count == 0 ||
            !InGameBrowserAddressPolicy.TryNormalize(
                ActivePage.View.Source?.AbsoluteUri,
                out var page))
        {
            return;
        }

        try
        {
            InGameBrowserPreferences.SaveLastPage(page);
        }
        catch (Exception exception)
        {
            App.WriteCrashLog(exception);
        }
    }

    private void NavigateFromAddressBar()
    {
        if (!InGameBrowserAddressPolicy.TryResolveNavigation(
                AddressBox.Text,
                _homePage,
                out var uri))
        {
            BrowserStatusText.Text = "请输入搜索内容或有效的 HTTP、HTTPS 地址";
            AddressBox.SelectAll();
            AddressBox.Focus();
            return;
        }

        Navigate(uri);
    }

    private void Navigate(Uri uri) =>
        Navigate(ActivePage, uri);

    private void Navigate(BrowserPageSession page, Uri uri)
    {
        if (page.View.CoreWebView2 is null)
        {
            BrowserStatusText.Text = "浏览器仍在启动，请稍候";
            return;
        }

        page.Title = uri.Host;
        if (ReferenceEquals(page, ActivePage))
        {
            AddressBox.Text = uri.AbsoluteUri;
            BrowserStatusText.Text = $"正在打开 {uri.Host}";
        }

        page.View.CoreWebView2.Navigate(uri.AbsoluteUri);
    }

    private void Core_NavigationStarting(
        object? sender,
        CoreWebView2NavigationStartingEventArgs e)
    {
        var page = FindBrowserPage(sender as CoreWebView2);
        if (InGameBrowserAddressPolicy.TryNormalize(e.Uri, out var uri))
        {
            if (page is not null)
            {
                page.Title = uri.Host;
            }

            if (page is null || ReferenceEquals(page, ActivePage))
            {
                AddressBox.Text = uri.AbsoluteUri;
                BrowserStatusText.Text = $"正在打开 {uri.Host}";
            }

            return;
        }

        e.Cancel = true;
        if (page is null || ReferenceEquals(page, ActivePage))
        {
            BrowserStatusText.Text = "已阻止不受支持的网页地址";
        }
    }

    private void Core_NavigationCompleted(
        object? sender,
        CoreWebView2NavigationCompletedEventArgs e)
    {
        var page = FindBrowserPage(sender as CoreWebView2);
        if (page is null || !ReferenceEquals(page, ActivePage))
        {
            return;
        }

        UpdateNavigationControls(page);
        if (InGameBrowserAddressPolicy.TryNormalize(page.View.Source?.AbsoluteUri, out var uri))
        {
            AddressBox.Text = uri.AbsoluteUri;
            BrowserStatusText.Text = e.IsSuccess
                ? uri.Host
                : $"网页打开失败：{e.WebErrorStatus}";
        }
    }

    private void Core_DocumentTitleChanged(object? sender, object e)
    {
        var page = FindBrowserPage(sender as CoreWebView2);
        if (page is null)
        {
            return;
        }

        var title = page.View.CoreWebView2?.DocumentTitle?.Trim();
        page.Title = string.IsNullOrWhiteSpace(title)
            ? page.View.Source?.Host ?? "新页面"
            : title;
    }

    private async void Core_NewWindowRequested(
        object? sender,
        CoreWebView2NewWindowRequestedEventArgs e)
    {
        e.Handled = true;
        if (InGameBrowserAddressPolicy.TryNormalize(e.Uri, out var uri))
        {
            if (_settings.BrowserOpenLinksInNewTab)
            {
                await AddBrowserPageAsync(uri);
            }
            else
            {
                Navigate(uri);
            }
        }
        else
        {
            BrowserStatusText.Text = "已阻止不受支持的新窗口";
        }
    }

    private BrowserPageSession? FindBrowserPage(CoreWebView2? core) =>
        core is null
            ? null
            : _pages.FirstOrDefault(page =>
                ReferenceEquals(page.View.CoreWebView2, core));

    private void Core_PermissionRequested(
        object? sender,
        CoreWebView2PermissionRequestedEventArgs e)
    {
        e.State = CoreWebView2PermissionState.Deny;
        e.Handled = true;
        Dispatcher.BeginInvoke(
            () => BrowserStatusText.Text = "游戏时浏览器不会授予网页设备权限",
            DispatcherPriority.Background);
    }

    private void Core_DownloadStarting(
        object? sender,
        CoreWebView2DownloadStartingEventArgs e)
    {
        e.Cancel = true;
        e.Handled = true;
        Dispatcher.BeginInvoke(
            () => BrowserStatusText.Text = "当前版本暂不支持从游戏时浏览器下载文件",
            DispatcherPriority.Background);
    }

    private void AddressBox_KeyDown(object sender, System.Windows.Input.KeyEventArgs e)
    {
        if (e.Key != Key.Enter)
        {
            return;
        }

        e.Handled = true;
        NavigateFromAddressBar();
    }

    private void GoButton_Click(object sender, RoutedEventArgs e) =>
        NavigateFromAddressBar();

    private async void NewBrowserPageButton_PreviewMouseLeftButtonDown(
        object sender,
        MouseButtonEventArgs e)
    {
        if (e.ChangedButton != MouseButton.Left || !NewBrowserPageButton.IsEnabled)
        {
            return;
        }

        e.Handled = true;
        NewBrowserPageButton.IsEnabled = false;
        try
        {
            await AddBrowserPageAsync(_homePage);
        }
        finally
        {
            NewBrowserPageButton.IsEnabled =
                _pages.Count < _settings.BrowserTabLimit;
        }
    }

    private async Task AddBrowserPageAsync(Uri uri)
    {
        if (_pages.Count >= _settings.BrowserTabLimit)
        {
            BrowserStatusText.Text =
                $"最多同时打开 {_settings.BrowserTabLimit} 个页面";
            return;
        }

        var page = CreateBrowserPage();
        await InitializeBrowserPageAsync(page, uri);
    }

    private void BrowserPageTabs_SelectionChanged(
        object sender,
        System.Windows.Controls.SelectionChangedEventArgs e)
    {
        if (BrowserPageTabs.SelectedItem is not BrowserPageSession page)
        {
            return;
        }

        BrowserHost.Children.Clear();
        BrowserHost.Children.Add(page.View);
        LoadingOverlay.Visibility = page.IsInitialized
            ? Visibility.Collapsed
            : Visibility.Visible;
        UpdateNavigationControls(page);
        ScheduleBrowserTabLayout();
    }

    private void BrowserPageTabs_SizeChanged(object sender, SizeChangedEventArgs e) =>
        ScheduleBrowserTabLayout();

    private void ScheduleBrowserTabLayout()
    {
        Dispatcher.BeginInvoke(
            () =>
            {
                RefreshBrowserTabWidths();
                if (BrowserPageTabs.SelectedItem is { } selected &&
                    BrowserPageTabs.ItemContainerGenerator.ContainerFromItem(selected) is
                        System.Windows.Controls.ListBoxItem selectedTab)
                {
                    selectedTab.BringIntoView();
                }

                if (_bringAddButtonIntoView)
                {
                    _bringAddButtonIntoView = false;
                    NewBrowserPageButton.BringIntoView();
                }
            },
            DispatcherPriority.Loaded);
    }

    private void RefreshBrowserTabWidths()
    {
        if (_pages.Count == 0 || BrowserTabViewport.ActualWidth <= 0)
        {
            return;
        }

        var availableWidth = Math.Max(116d, BrowserTabViewport.ActualWidth - 42d);
        var tabWidth = Math.Clamp(
            Math.Floor(availableWidth / _pages.Count) - 4d,
            116d,
            220d);
        foreach (var page in _pages)
        {
            page.TabWidth = tabWidth;
        }
    }

    private void BrowserTabViewport_PreviewMouseWheel(object sender, MouseWheelEventArgs e)
    {
        if (BrowserTabViewport.ScrollableWidth <= 0)
        {
            return;
        }

        BrowserTabViewport.ScrollToHorizontalOffset(
            Math.Clamp(
                BrowserTabViewport.HorizontalOffset - e.Delta,
                0,
                BrowserTabViewport.ScrollableWidth));
        e.Handled = true;
    }

    private async void CloseBrowserPageButton_Click(object sender, RoutedEventArgs e)
    {
        e.Handled = true;
        if ((sender as FrameworkElement)?.Tag is not BrowserPageSession page)
        {
            return;
        }

        var index = _pages.IndexOf(page);
        var wasActive = ReferenceEquals(page, ActivePage);
        DisposeBrowserPage(page);
        _pages.Remove(page);
        ScheduleBrowserTabLayout();
        if (_pages.Count == 0)
        {
            await AddBrowserPageAsync(_homePage);
            return;
        }

        if (wasActive)
        {
            BrowserPageTabs.SelectedItem = _pages[Math.Clamp(index, 0, _pages.Count - 1)];
        }
    }

    private void UpdateNavigationControls(BrowserPageSession page)
    {
        BackButton.IsEnabled = page.IsInitialized && page.View.CanGoBack;
        ForwardButton.IsEnabled = page.IsInitialized && page.View.CanGoForward;
        RefreshButton.IsEnabled = page.IsInitialized;
        if (InGameBrowserAddressPolicy.TryNormalize(
                page.View.Source?.AbsoluteUri,
                out var uri))
        {
            AddressBox.Text = uri.AbsoluteUri;
            BrowserStatusText.Text = uri.Host;
        }
        else if (!page.IsInitialized)
        {
            AddressBox.Text = _homePage.AbsoluteUri;
            BrowserStatusText.Text = "正在启动浏览器";
        }
    }

    private void BackButton_Click(object sender, RoutedEventArgs e)
    {
        if (BrowserView.CanGoBack)
        {
            BrowserView.GoBack();
        }
    }

    private void ForwardButton_Click(object sender, RoutedEventArgs e)
    {
        if (BrowserView.CanGoForward)
        {
            BrowserView.GoForward();
        }
    }

    private void RefreshButton_Click(object sender, RoutedEventArgs e)
    {
        if (BrowserView.CoreWebView2 is null)
        {
            BrowserStatusText.Text = "浏览器仍在启动，请稍候";
            return;
        }

        BrowserView.Reload();
    }

    private void HomeButton_Click(object sender, RoutedEventArgs e) =>
        Navigate(_homePage);

    private void Window_PreviewKeyDown(object sender, System.Windows.Input.KeyEventArgs e)
    {
        var key = e.Key == Key.System ? e.SystemKey : e.Key;
        if (key != Key.Escape)
        {
            return;
        }

        e.Handled = true;
        MenuCloseRequested?.Invoke(this, EventArgs.Empty);
    }

    private void Window_Deactivated(object? sender, EventArgs e) =>
        ToolDeactivated?.Invoke(this, EventArgs.Empty);

    protected override void OnClosing(CancelEventArgs e)
    {
        if (!_allowPermanentClose)
        {
            e.Cancel = true;
            HideForMenu();
            ToolHidden?.Invoke(this, EventArgs.Empty);
            return;
        }

        base.OnClosing(e);
    }

    private void TitleBar_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (e.LeftButton == MouseButtonState.Pressed)
        {
            DragMove();
        }
    }

    private void MinimizeButton_Click(object sender, RoutedEventArgs e) =>
        WindowState = WindowState.Minimized;

    private void CloseButton_Click(object sender, RoutedEventArgs e) =>
        Close();
}

internal sealed class BrowserPageSession(WebView2 view) : INotifyPropertyChanged
{
    private string _title = "新页面";
    private double _tabWidth = 220d;

    public event PropertyChangedEventHandler? PropertyChanged;

    internal WebView2 View { get; } = view;

    internal bool IsInitialized { get; set; }

    public double TabWidth
    {
        get => _tabWidth;
        internal set
        {
            if (Math.Abs(_tabWidth - value) < 0.1d)
            {
                return;
            }

            _tabWidth = value;
            PropertyChanged?.Invoke(
                this,
                new PropertyChangedEventArgs(nameof(TabWidth)));
        }
    }

    public string Title
    {
        get => _title;
        internal set
        {
            var next = string.IsNullOrWhiteSpace(value) ? "新页面" : value.Trim();
            if (_title.Equals(next, StringComparison.Ordinal))
            {
                return;
            }

            _title = next;
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(Title)));
        }
    }
}
