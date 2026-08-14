using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Threading;
using StarBridge.Desktop.Theming;
using MediaBrush = System.Windows.Media.Brush;

namespace StarBridge.Desktop;

public sealed record ApplicationLayerWorkspaceAction(
    string Label,
    Action Invoke,
    bool IsSelected = false);

public partial class ApplicationLayerHost : System.Windows.Controls.UserControl
{
    private const double WorkspaceWidthRatio = 0.64;
    private const double WorkspaceHeightRatio = 0.72;
    private const double WorkspaceMinimumWidth = 720;
    private const double WorkspaceMinimumHeight = 480;
    private const double WorkspaceMaximumWidth = 1120;
    private const double WorkspaceMaximumHeight = 700;
    private const double WorkspaceHorizontalSafeArea = 96;
    private const double WorkspaceVerticalSafeArea = 72;

    private Action? _workspaceClosed;
    private Action? _dismissModal;
    private FrameworkElement? _workspaceContent;
    private object? _modalToken;
    private IInputElement? _focusBeforeLayer;
    private bool _dismissWorkspaceOnBackdrop;
    private bool _dismissModalOnBackdrop;

    public ApplicationLayerHost()
    {
        InitializeComponent();
    }

    public bool IsWorkspaceOpen => WorkspaceLayer.Visibility == Visibility.Visible;

    public bool IsShowing(FrameworkElement content) =>
        IsWorkspaceOpen && ReferenceEquals(_workspaceContent, content);

    public void ShowWorkspace(
        string title,
        string subtitle,
        FrameworkElement content,
        Action? closed = null,
        bool dismissOnBackdrop = false,
        IReadOnlyList<ApplicationLayerWorkspaceAction>? actions = null)
    {
        ArgumentNullException.ThrowIfNull(content);

        if (_focusBeforeLayer is null)
        {
            _focusBeforeLayer = Keyboard.FocusedElement;
        }

        CloseModal();
        if (_workspaceContent is not null && !ReferenceEquals(_workspaceContent, content))
        {
            var previousClosed = _workspaceClosed;
            _workspaceClosed = null;
            previousClosed?.Invoke();
        }

        ApplyContentScene(content, WorkspaceFrame);
        _workspaceContent = content;
        _workspaceClosed = closed;
        _dismissWorkspaceOnBackdrop = dismissOnBackdrop;
        WorkspaceTitleText.Text = title;
        WorkspaceSubtitleText.Text = subtitle;
        ConfigureWorkspaceActions(actions);
        WorkspaceContentPresenter.Content = content;
        WorkspaceLayer.Visibility = Visibility.Visible;
        Visibility = Visibility.Visible;
        UpdateWorkspaceFrameSize();

        Dispatcher.BeginInvoke(
            DispatcherPriority.Loaded,
            new Action(UpdateWorkspaceFrameSize));
        Dispatcher.BeginInvoke(
            DispatcherPriority.Input,
            new Action(() => MoveFocusInto(content)));
    }

    public Task<TResult?> ShowModalAsync<TResult>(
        string title,
        string subtitle,
        Func<Action<TResult?>, FrameworkElement> contentFactory,
        double maxWidth,
        double maxHeight,
        bool dismissOnBackdrop = false)
    {
        ArgumentNullException.ThrowIfNull(contentFactory);

        CloseModal();
        if (_focusBeforeLayer is null)
        {
            _focusBeforeLayer = Keyboard.FocusedElement;
        }

        var completion = new TaskCompletionSource<TResult?>(TaskCreationOptions.RunContinuationsAsynchronously);
        var token = new object();
        _modalToken = token;

        void Complete(TResult? result)
        {
            if (!ReferenceEquals(_modalToken, token))
            {
                return;
            }

            HideModalCore();
            completion.TrySetResult(result);
        }

        var content = contentFactory(Complete);
        ApplyContentScene(content, ModalFrame);
        ModalTitleText.Text = title;
        ModalSubtitleText.Text = subtitle;
        ModalFrame.MaxWidth = Math.Max(460, maxWidth);
        ModalFrame.MaxHeight = Math.Max(340, maxHeight);
        ModalContentPresenter.Content = content;
        _dismissModal = () => Complete(default);
        _dismissModalOnBackdrop = dismissOnBackdrop;
        ModalLayer.Visibility = Visibility.Visible;
        Visibility = Visibility.Visible;

        Dispatcher.BeginInvoke(
            DispatcherPriority.Input,
            new Action(() => MoveFocusInto(content)));
        return completion.Task;
    }

    public void CloseWorkspace()
    {
        CloseModal();
        if (!IsWorkspaceOpen)
        {
            return;
        }

        WorkspaceLayer.Visibility = Visibility.Collapsed;
        WorkspaceContentPresenter.Content = null;
        ClearContentScene(WorkspaceFrame);
        ConfigureWorkspaceActions(null);
        _workspaceContent = null;
        _dismissWorkspaceOnBackdrop = false;
        var closed = _workspaceClosed;
        _workspaceClosed = null;
        closed?.Invoke();
        UpdateHostVisibilityAndFocus();
    }

    public void CloseActiveLayer()
    {
        if (ModalLayer.Visibility == Visibility.Visible)
        {
            CloseModal();
            return;
        }

        CloseWorkspace();
    }

    private void CloseModal()
    {
        var dismiss = _dismissModal;
        if (dismiss is null)
        {
            return;
        }

        _dismissModal = null;
        dismiss();
    }

    private void HideModalCore()
    {
        _dismissModal = null;
        _modalToken = null;
        _dismissModalOnBackdrop = false;
        ModalLayer.Visibility = Visibility.Collapsed;
        ModalContentPresenter.Content = null;
        ClearContentScene(ModalFrame);
        UpdateHostVisibilityAndFocus();
    }

    private void UpdateHostVisibilityAndFocus()
    {
        if (WorkspaceLayer.Visibility == Visibility.Visible || ModalLayer.Visibility == Visibility.Visible)
        {
            Visibility = Visibility.Visible;
            return;
        }

        Visibility = Visibility.Collapsed;
        var focus = _focusBeforeLayer;
        _focusBeforeLayer = null;
        if (focus is not null)
        {
            Dispatcher.BeginInvoke(DispatcherPriority.Input, new Action(() => Keyboard.Focus(focus)));
        }
    }

    private static void MoveFocusInto(FrameworkElement content)
    {
        content.Focus();
        content.MoveFocus(new TraversalRequest(FocusNavigationDirection.First));
    }

    private void ConfigureWorkspaceActions(
        IReadOnlyList<ApplicationLayerWorkspaceAction>? actions)
    {
        WorkspaceActionButtonsPanel.Children.Clear();
        if (actions is null)
        {
            WorkspaceCloseButton.Margin = new Thickness(0);
            return;
        }

        foreach (var action in actions)
        {
            var button = new System.Windows.Controls.Button
            {
                Content = action.Label,
                Height = 34,
                MinWidth = 92,
                Margin = new Thickness(0, 0, 8, 0)
            };
            button.SetResourceReference(
                FrameworkElement.StyleProperty,
                action.IsSelected
                    ? "BridgeDirectoryPrimaryButtonStyle"
                    : "BridgeDirectorySecondaryButtonStyle");
            if (!action.IsSelected)
            {
                button.Click += (_, _) => action.Invoke();
            }
            WorkspaceActionButtonsPanel.Children.Add(button);
        }

        WorkspaceCloseButton.Margin = new Thickness(0);
    }

    private void UpdateWorkspaceFrameSize()
    {
        var availableWidth = Math.Max(0, ActualWidth - WorkspaceHorizontalSafeArea);
        var availableHeight = Math.Max(0, ActualHeight - WorkspaceVerticalSafeArea);
        if (availableWidth <= 0 || availableHeight <= 0)
        {
            return;
        }

        var targetWidth = Math.Clamp(
            ActualWidth * WorkspaceWidthRatio,
            WorkspaceMinimumWidth,
            WorkspaceMaximumWidth);
        var targetHeight = Math.Clamp(
            ActualHeight * WorkspaceHeightRatio,
            WorkspaceMinimumHeight,
            WorkspaceMaximumHeight);

        WorkspaceFrame.Width = Math.Min(availableWidth, targetWidth);
        WorkspaceFrame.Height = Math.Min(availableHeight, targetHeight);
    }

    private void WorkspaceBackButton_Click(object sender, RoutedEventArgs e) => CloseWorkspace();

    private void WorkspaceCloseButton_Click(object sender, RoutedEventArgs e) => CloseWorkspace();

    private void WorkspaceLayer_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (_dismissWorkspaceOnBackdrop &&
            ReferenceEquals(e.OriginalSource, WorkspaceLayer))
        {
            e.Handled = true;
            CloseWorkspace();
        }
    }

    private void ModalCloseButton_Click(object sender, RoutedEventArgs e) => CloseModal();

    private void ModalLayer_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (_dismissModalOnBackdrop &&
            ReferenceEquals(e.OriginalSource, ModalLayer))
        {
            e.Handled = true;
            CloseModal();
        }
    }

    private static void ApplyContentScene(FrameworkElement content, DependencyObject frame)
    {
        ApplyLocalSceneBrush(
            content,
            frame,
            BridgeSceneContext.AccentBrushProperty,
            BridgeSceneContext.GetAccentBrush,
            BridgeSceneContext.SetAccentBrush);
        ApplyLocalSceneBrush(
            content,
            frame,
            BridgeSceneContext.AmbientBrushProperty,
            BridgeSceneContext.GetAmbientBrush,
            BridgeSceneContext.SetAmbientBrush);
    }

    private static void ApplyLocalSceneBrush(
        FrameworkElement content,
        DependencyObject frame,
        DependencyProperty property,
        Func<DependencyObject, MediaBrush?> resolve,
        Action<DependencyObject, MediaBrush?> apply)
    {
        if (content.ReadLocalValue(property) == DependencyProperty.UnsetValue)
        {
            frame.ClearValue(property);
            return;
        }

        var brush = resolve(content);
        if (brush is null)
        {
            frame.ClearValue(property);
            return;
        }

        apply(frame, brush);
    }

    private static void ClearContentScene(DependencyObject frame)
    {
        frame.ClearValue(BridgeSceneContext.AccentBrushProperty);
        frame.ClearValue(BridgeSceneContext.AmbientBrushProperty);
    }

    private void ApplicationLayerHost_PreviewKeyDown(object sender, System.Windows.Input.KeyEventArgs e)
    {
        if (e.Key != Key.Escape)
        {
            return;
        }

        e.Handled = true;
        CloseActiveLayer();
    }

    private void ApplicationLayerHost_SizeChanged(object sender, SizeChangedEventArgs e) =>
        UpdateWorkspaceFrameSize();
}
