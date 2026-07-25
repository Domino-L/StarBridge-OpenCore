using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Threading;
using MessageBox = System.Windows.MessageBox;
using WinForms = System.Windows.Forms;

namespace StarBridge.Desktop;

public partial class App : System.Windows.Application
{
    private const string SingleInstanceMutexName = @"Local\StarBridge.Desktop.SingleInstance.9D5E2B18";
    private const string SingleInstanceActivationEventName = @"Local\StarBridge.Desktop.Activate.9D5E2B18";
    private const int ShowWindowRestore = 9;

    private Mutex? _singleInstanceMutex;
    private bool _ownsSingleInstanceMutex;
    private EventWaitHandle? _singleInstanceActivationEvent;
    private RegisteredWaitHandle? _singleInstanceActivationRegistration;
    private WinForms.NotifyIcon? _trayIcon;
    private TrayQuickPanel? _trayQuickPanel;
    private bool _exitRequested;
    private bool _updateRestartRequested;

    internal ApplicationBehaviorSettings BehaviorSettings { get; private set; } =
        ApplicationBehaviorSettings.Default;

    internal string? ApplicationBehaviorError { get; private set; }

    internal bool ExitRequested => _exitRequested;

    internal bool IsUpdateRestartRequested => _updateRestartRequested;

    internal bool ShouldKeepRunningInBackground =>
        BehaviorSettings.KeepRunningInBackground && !_exitRequested;

    protected override void OnStartup(StartupEventArgs e)
    {
        DispatcherUnhandledException += App_DispatcherUnhandledException;
        AppDomain.CurrentDomain.UnhandledException += (_, args) =>
        {
            if (args.ExceptionObject is Exception exception)
            {
                WriteCrashLog(exception);
            }
        };


        if (!TryAcquireSingleInstance())
        {
            SignalExistingInstance();
            Shutdown();
            return;
        }

        RegisterSingleInstanceActivation();
        BehaviorSettings = ApplicationBehaviorSettingsStore.Load().Normalize();
        if (!WindowsStartupRegistration.TrySetEnabled(BehaviorSettings.LaunchAtStartup, out var startupError))
        {
            ApplicationBehaviorError = startupError;
        }

        base.OnStartup(e);
        ShutdownMode = ShutdownMode.OnMainWindowClose;

        var mainWindow = new MainWindow();
        MainWindow = mainWindow;
        PortableUpdateStartupSignal.Attach(mainWindow);
        UpdateTrayIconVisibility();

        if (WindowsStartupRegistration.ShouldStartInBackground(e.Args, BehaviorSettings))
        {
            mainWindow.ShowActivated = false;
            mainWindow.ShowInTaskbar = false;
            mainWindow.WindowState = WindowState.Minimized;
            mainWindow.Show();
            Dispatcher.BeginInvoke(
                DispatcherPriority.ApplicationIdle,
                new Action(() => HideMainWindowToBackground(showHint: false, force: true)));
        }
        else
        {
            mainWindow.Show();
        }
    }

    protected override void OnExit(ExitEventArgs e)
    {
        DisposeTrayIcon();
        _singleInstanceActivationRegistration?.Unregister(null);
        _singleInstanceActivationEvent?.Dispose();

        if (_ownsSingleInstanceMutex)
        {
            try
            {
                _singleInstanceMutex?.ReleaseMutex();
            }
            catch (ApplicationException)
            {
                // The mutex may already be released during abnormal shutdown.
            }
        }

        _singleInstanceMutex?.Dispose();
        base.OnExit(e);
    }

    protected override void OnSessionEnding(SessionEndingCancelEventArgs e)
    {
        _exitRequested = true;
        base.OnSessionEnding(e);
    }

    internal ApplicationBehaviorApplyResult TryApplyBehaviorSettings(ApplicationBehaviorSettings requested)
    {
        var normalized = requested.Normalize();
        var previous = BehaviorSettings;
        if (!WindowsStartupRegistration.TrySetEnabled(normalized.LaunchAtStartup, out var startupError))
        {
            ApplicationBehaviorError = startupError;
            return new ApplicationBehaviorApplyResult(false, previous, startupError);
        }

        if (!ApplicationBehaviorSettingsStore.TrySave(normalized, out var saveError))
        {
            WindowsStartupRegistration.TrySetEnabled(previous.LaunchAtStartup, out _);
            ApplicationBehaviorError = saveError;
            return new ApplicationBehaviorApplyResult(false, previous, saveError);
        }

        BehaviorSettings = normalized;
        ApplicationBehaviorError = null;
        UpdateTrayIconVisibility();
        return new ApplicationBehaviorApplyResult(true, normalized);
    }

    internal void HideMainWindowToBackground(bool showHint = true, bool force = false)
    {
        if ((!BehaviorSettings.KeepRunningInBackground && !force) || MainWindow is null)
        {
            return;
        }

        EnsureTrayIcon();
        if (_trayIcon is not null)
        {
            _trayIcon.Visible = true;
        }
        MainWindow.Hide();
        MainWindow.ShowInTaskbar = false;
        if (showHint && !BehaviorSettings.BackgroundHintShown && _trayIcon is not null)
        {
            _trayIcon.ShowBalloonTip(
                3500,
                "星海舰桥仍在运行",
                "应用已进入系统托盘。需要停止后台运行时，请选择“完全退出”。",
                WinForms.ToolTipIcon.Info);
            var acknowledged = BehaviorSettings with { BackgroundHintShown = true };
            if (ApplicationBehaviorSettingsStore.TrySave(acknowledged, out _))
            {
                BehaviorSettings = acknowledged;
            }
        }
    }

    internal void ShowMainWindowFromBackground()
    {
        CloseTrayQuickPanel();
        if (MainWindow is null)
        {
            return;
        }

        MainWindow.ShowInTaskbar = true;
        if (!MainWindow.IsVisible)
        {
            MainWindow.Show();
        }

        if (MainWindow.WindowState == WindowState.Minimized)
        {
            MainWindow.WindowState = WindowState.Normal;
        }

        ActivateExistingMainWindow();
        UpdateTrayIconVisibility();
    }

    internal TrayQuickPanelState GetTrayQuickPanelState()
    {
        return MainWindow is StarBridge.Desktop.MainWindow mainWindow
            ? mainWindow.BuildTrayQuickPanelState()
            : TrayQuickPanelState.Unavailable;
    }

    internal void ToggleOverlayFromTray()
    {
        if (MainWindow is StarBridge.Desktop.MainWindow mainWindow)
        {
            mainWindow.ToggleOverlayFromTray();
        }
    }

    internal void OpenOverlaySettingsFromTray()
    {
        ShowMainWindowFromBackground();
        if (MainWindow is StarBridge.Desktop.MainWindow mainWindow)
        {
            mainWindow.OpenOverlaySettingsFromTray();
        }
    }

    internal void RequestExit()
    {
        _updateRestartRequested = false;
        RequestExitCore();
    }

    internal void RequestExitForUpdate()
    {
        _updateRestartRequested = true;
        RequestExitCore();
    }

    private void RequestExitCore()
    {
        _exitRequested = true;
        CloseTrayQuickPanel();
        if (_trayIcon is not null)
        {
            _trayIcon.Visible = false;
        }

        if (MainWindow is null)
        {
            Shutdown();
            return;
        }

        MainWindow.Close();
    }

    internal void CancelExitRequest()
    {
        _exitRequested = false;
        _updateRestartRequested = false;
        UpdateTrayIconVisibility();
    }

    private bool TryAcquireSingleInstance()
    {
        _singleInstanceMutex = new Mutex(initiallyOwned: true, SingleInstanceMutexName, out _ownsSingleInstanceMutex);
        return _ownsSingleInstanceMutex;
    }

    private void RegisterSingleInstanceActivation()
    {
        _singleInstanceActivationEvent = new EventWaitHandle(
            initialState: false,
            EventResetMode.AutoReset,
            SingleInstanceActivationEventName);
        _singleInstanceActivationRegistration = ThreadPool.RegisterWaitForSingleObject(
            _singleInstanceActivationEvent,
            (_, _) => Dispatcher.BeginInvoke(ActivateExistingMainWindow),
            state: null,
            millisecondsTimeOutInterval: -1,
            executeOnlyOnce: false);
    }

    private static void SignalExistingInstance()
    {
        try
        {
            using var activationEvent = EventWaitHandle.OpenExisting(SingleInstanceActivationEventName);
            activationEvent.Set();
        }
        catch (WaitHandleCannotBeOpenedException)
        {
            TryFocusExistingProcessWindow();
        }
        catch (UnauthorizedAccessException)
        {
            TryFocusExistingProcessWindow();
        }
    }

    private void ActivateExistingMainWindow()
    {
        if (MainWindow is null)
        {
            return;
        }

        MainWindow.ShowInTaskbar = true;
        if (!MainWindow.IsVisible)
        {
            MainWindow.Show();
        }

        if (MainWindow.WindowState == WindowState.Minimized)
        {
            MainWindow.WindowState = WindowState.Normal;
        }

        MainWindowPlacementService.EnsureVisible(MainWindow);
        MainWindow.Activate();
        var handle = new WindowInteropHelper(MainWindow).Handle;
        if (handle != IntPtr.Zero)
        {
            ShowWindow(handle, ShowWindowRestore);
            SetForegroundWindow(handle);
        }

        MainWindow.Topmost = true;
        MainWindow.Topmost = false;
        MainWindow.Focus();
    }

    private void UpdateTrayIconVisibility()
    {
        if (!BehaviorSettings.KeepRunningInBackground)
        {
            CloseTrayQuickPanel();
            if (_trayIcon is not null)
            {
                _trayIcon.Visible = false;
            }

            return;
        }

        EnsureTrayIcon();
        if (_trayIcon is not null)
        {
            _trayIcon.Visible = true;
        }
    }

    private void EnsureTrayIcon()
    {
        if (_trayIcon is not null)
        {
            return;
        }

        _trayIcon = new WinForms.NotifyIcon
        {
            Text = "星海舰桥",
            Icon = System.Drawing.Icon.ExtractAssociatedIcon(Environment.ProcessPath ?? ""),
            Visible = false
        };
        _trayIcon.MouseUp += (_, args) =>
        {
            if (args.Button is WinForms.MouseButtons.Left or WinForms.MouseButtons.Right)
            {
                Dispatcher.BeginInvoke(ShowTrayQuickPanel);
            }
        };
    }

    private void ShowTrayQuickPanel()
    {
        if (_trayQuickPanel is null)
        {
            var panel = new TrayQuickPanel();
            panel.Closed += (_, _) =>
            {
                if (ReferenceEquals(_trayQuickPanel, panel))
                {
                    _trayQuickPanel = null;
                }
            };
            _trayQuickPanel = panel;
        }

        _trayQuickPanel.ShowNearTrayIcon();
    }

    private void CloseTrayQuickPanel()
    {
        var panel = _trayQuickPanel;
        _trayQuickPanel = null;
        panel?.Close();
    }

    private void DisposeTrayIcon()
    {
        CloseTrayQuickPanel();
        if (_trayIcon is null)
        {
            return;
        }

        _trayIcon.Visible = false;
        _trayIcon.Icon?.Dispose();
        _trayIcon.Dispose();
        _trayIcon = null;
    }

    private static void TryFocusExistingProcessWindow()
    {
        try
        {
            using var current = Process.GetCurrentProcess();
            foreach (var process in Process.GetProcessesByName(current.ProcessName))
            {
                using (process)
                {
                    if (process.Id == current.Id || process.MainWindowHandle == IntPtr.Zero)
                    {
                        continue;
                    }

                    ShowWindow(process.MainWindowHandle, ShowWindowRestore);
                    SetForegroundWindow(process.MainWindowHandle);
                    return;
                }
            }
        }
        catch
        {
            // Best-effort focus only. The second instance still exits.
        }
    }

    private static void App_DispatcherUnhandledException(object sender, DispatcherUnhandledExceptionEventArgs e)
    {
        WriteCrashLog(e.Exception);
        StarBridgeMessageBox.Show(
            $"应用遇到问题，已保存诊断记录：\n{GetCrashLogPath()}\n\n请重新打开应用；如果问题再次发生，可在“帮助与反馈”中提交诊断记录。",
            "星海舰桥",
            MessageBoxButton.OK,
            MessageBoxImage.Error);
        e.Handled = true;
    }

    public static void WriteCrashLog(Exception exception)
    {
        try
        {
            File.AppendAllText(
                GetCrashLogPath(),
                $"[{DateTime.Now:yyyy-MM-dd HH:mm:ss}]\n{exception}\n\n");
        }
        catch
        {
            // Last-resort logging must never become another crash source.
        }
    }

    public static void WriteDiagnosticLog(string message)
    {
        try
        {
            File.AppendAllText(
                GetDiagnosticLogPath(),
                $"[{DateTime.Now:yyyy-MM-dd HH:mm:ss.fff}] {message}{Environment.NewLine}");
        }
        catch
        {
            // Diagnostics must never interfere with the app or overlay.
        }
    }

    private static string GetCrashLogPath()
    {
        var directory = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "StarBridge");
        Directory.CreateDirectory(directory);
        return Path.Combine(directory, "desktop-crash.log");
    }

    private static string GetDiagnosticLogPath()
    {
        var directory = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "StarBridge");
        Directory.CreateDirectory(directory);
        return Path.Combine(directory, "desktop-overlay-diagnostics.log");
    }

    [DllImport("user32.dll")]
    private static extern bool ShowWindow(IntPtr handle, int command);

    [DllImport("user32.dll")]
    private static extern bool SetForegroundWindow(IntPtr handle);
}
