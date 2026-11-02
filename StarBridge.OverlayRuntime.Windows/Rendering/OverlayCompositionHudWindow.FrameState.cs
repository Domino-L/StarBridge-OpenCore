using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Diagnostics;
using System.Numerics;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using StarBridge.Core.Presence;
using SharpGen.Runtime;
using Vortice;
using Vortice.DCommon;
using Vortice.Direct2D1;
using Vortice.Direct3D;
using Vortice.Direct3D11;
using Vortice.DirectComposition;
using Vortice.DirectWrite;
using Vortice.DXGI;
using Vortice.Mathematics;
using D2DFactoryType = Vortice.Direct2D1.FactoryType;
using D2DTextAntialiasMode = Vortice.Direct2D1.TextAntialiasMode;
using D3DFeatureLevel = Vortice.Direct3D.FeatureLevel;
using D3D11Api = Vortice.Direct3D11.D3D11;
using DCompApi = Vortice.DirectComposition.DComp;
using DWriteFontStretch = Vortice.DirectWrite.FontStretch;
using DWriteFontStyle = Vortice.DirectWrite.FontStyle;
using DWriteFontWeight = Vortice.DirectWrite.FontWeight;
using DWriteFactoryType = Vortice.DirectWrite.FactoryType;
using DWriteTextAlignment = Vortice.DirectWrite.TextAlignment;
using DxgiAlphaMode = Vortice.DXGI.AlphaMode;
using DxgiFormat = Vortice.DXGI.Format;
using WpfRect = System.Windows.Rect;
using WpfVisibility = System.Windows.Visibility;

namespace StarBridge.Desktop;

/// <summary>Builds the immutable frame state from the view model and publishes it to the render thread.</summary>
internal sealed partial class OverlayCompositionHudWindow
{
    private void PublishStateToRenderer(bool forceEventPulse)
    {
        var state = BuildFrameState();
        var announcement = state.ShowNotice ? _viewModel.AnnouncementAwaitingScreen(state.FleetNoticeTitle, state.FleetNotice) : null;
        var viewport = CaptureCompositionViewport();
        var calmLevels = OverlayCalmDisplayLevels.Resolve(_settings);
        var calmPeekHotkey = _settings.CalmPeekHotkey;
        var appearanceFrame = state;
        if (_deferEventNotificationsUntilContentRevealCompletes && !forceEventPulse)
        {
            state = state with
            {
                ShowEvents = false,
                EventRows = Array.Empty<OverlayCompositionEventRow>()
            };
        }

        var dispatcher = _renderDispatcher;
        if (dispatcher is null || dispatcher.HasShutdownStarted || dispatcher.HasShutdownFinished)
        {
            _state = state;
            return;
        }

        dispatcher.BeginInvoke(() =>
        {
            if (_disposed || _renderThreadDisposed)
            {
                return;
            }

            ApplyCompositionViewport(viewport);
            var pulseChanged = forceEventPulse || state.EventPulse != _lastEventPulse;
            var previousState = _state;
            if (state.ShowNotice)
            {
                _fleetNoticeExitState = null;
                _fleetNoticeExitStartedAtUtc = DateTimeOffset.MinValue;
            }
            else if (previousState is { ShowNotice: true } &&
                     (previousState.NightShadowStyle || previousState.VerdictStyle))
            {
                _fleetNoticeExitState = previousState;
                _fleetNoticeExitStartedAtUtc = DateTimeOffset.UtcNow;
            }

            _state = state;
            _announcementOnScreen = announcement;
            ObserveMemberFlip(previousState, state);
            ObserveCalm(previousState, state, calmLevels, calmPeekHotkey);
            ObserveExtendedAppearanceFrame(appearanceFrame);
            if (pulseChanged && state.EventRows.Count > 0)
            {
                _lastEventPulse = state.EventPulse;
                _eventSlideStartedAtUtc = DateTimeOffset.UtcNow;
            }

            var appearanceAnimation = ReadAppearanceAnimationState();
            if ((pulseChanged && state.EventRows.Count > 0) ||
                IsContentRevealActive() ||
                appearanceAnimation.StartupActive ||
                appearanceAnimation.EventFlowActive ||
                appearanceAnimation.AmbientFlowActive ||
                IsChatBarrageActive() ||
                IsFleetNoticeExitActive() ||
                IsMemberMotionActive() ||
                IsCalmMotionActive())
            {
                var requestedFramesPerSecond = IsContentRevealActive() || appearanceAnimation.StartupActive
                    ? ResolveStartupTransitionFramesPerSecond(state.StartupTransitionFrameRate)
                    : ResolveMotionFramesPerSecond(state.AnimationFrameRate);
                var framesPerSecond = _adaptiveFramePacer.Resolve(requestedFramesPerSecond, Environment.TickCount64);
                _frameScheduler?.Start(framesPerSecond);
            }

            DrawFrame();
        }, DispatcherPriority.Render);
    }

    private OverlayCompositionFrameState BuildFrameState()
    {
        var width = Math.Max(1, _surfaceBounds.Width);
        var height = Math.Max(1, _surfaceBounds.Height);
        var resolvedItems = OverlaySurfaceLayout.ResolveItems(_layout, width, height);
        var noticeRect = ResolveItemRect("Notice", resolvedItems);
        var squadsRect = ResolveItemRect("Squads", resolvedItems);
        var membersRect = ResolveItemRect("Members", resolvedItems);
        var chatRect = ResolveItemRect("Chat", resolvedItems);
        var noticeStyle = ResolveModuleStyle("Notice");
        var squadsStyle = ResolveModuleStyle("Squads");
        var membersStyle = ResolveModuleStyle("Members");
        var chatStyle = ResolveModuleStyle("Chat");
        var eventRect = ResolveEventNotificationRect(width, height);
        var eventStyle = new OverlayCompositionModuleStyle(
            OverlayLayoutItem.NormalizeTextOpacity(_settings.EventNotificationTextOpacity),
            OverlayLayoutItem.NormalizeBackgroundOpacity(_settings.EventNotificationBackgroundOpacity),
            OverlayLayoutItem.NormalizeDecorationOpacity(_settings.EventNotificationDecorationOpacity));
        var overviewTopLocations = _viewModel.OverviewTopLocations.Take(2).ToArray();
        var overviewLocationLayout = OverlayOverviewLocationLayout.Resolve(
            squadsRect.Width,
            squadsRect.Height,
            overviewTopLocations);
        var visibility = InformationOverlayRuntimeProjection.ResolveVisibility(
            _settings,
            new InformationOverlayContentState(
                _viewModel.NotificationVisibility == WpfVisibility.Visible,
                _viewModel.ChatVisibility == WpfVisibility.Visible,
                _viewModel.EventNotificationVisibility == WpfVisibility.Visible));

        var sourceLabels = _viewModel.ModuleSourceLabels;
        return ApplyDirectMessages(ApplyNoticeSlot(new OverlayCompositionFrameState(
            width,
            height,
            1.0,
            BuildPalette(),
            OverlaySkinCatalog.Get(_settings.Skin).RenderKind,
            visibility.ShowNotice,
            visibility.ShowSquads,
            visibility.ShowMembers,
            visibility.ShowChat,
            visibility.ShowCrosshair,
            visibility.ShowEventNotifications,
            noticeRect,
            squadsRect,
            membersRect,
            chatRect,
            eventRect,
            eventStyle,
            noticeStyle,
            squadsStyle,
            membersStyle,
            chatStyle,
            ResolveModuleDrawOrder(),
            _settings.EventNotificationSide,
            _settings.NightShadowBloom,
            _viewModel.FleetNoticeTitle,
            _viewModel.FleetNotice,
            _viewModel.NoticeTimerLabel,
            _viewModel.SquadsTitle,
            _viewModel.SquadStatusPrimaryName,
            _viewModel.SquadStatusSummary,
            _viewModel.SquadStatusServerSummary,
            _viewModel.SquadStatusFocusLine,
            _viewModel.OverviewLocationPlaceholder,
            _viewModel.OverviewLocationPlaceholderMetric,
            overviewTopLocations,
            overviewLocationLayout,
            _viewModel.MembersTitle,
            SnapshotMembers(_viewModel.Members),
            _viewModel.ChatTitle,
            _viewModel.ChatDisplayMode,
            _viewModel.ChatSide,
            OverlayDisplaySettings.NormalizeChatBarrageFontSize(_settings.ChatBarrageFontSize),
            OverlayDisplaySettings.NormalizeChatBarrageRegion(_settings.ChatBarrageRegion),
            OverlayDisplaySettings.NormalizeChatBarrageDensity(_settings.ChatBarrageDensity),
            _settings.ChatBarrageAvoidCenter,
            OverlayDisplaySettings.NormalizeChatTextEdgeStrength(_settings.ChatTextEdgeStrength),
            SnapshotEvents(_viewModel.ChatMessages, _viewModel.ChatDisplayMode == OverlayChatDisplayMode.FullScreenBarrage
                ? sourceLabels.RowPrefix(OverlayModuleFlags.Chat, sourceLabels.Chat) : null),
            _viewModel.ChatPulse,
            _viewModel.PreserveBarrageMotion || _settings.AnimationFrameRate != OverlayAnimationFrameRate.Off,
            _settings.EffectiveHideMemberOnlineStatus,
            OverlayDisplaySettings.NormalizeMemberNameColumnRatio(_settings.MemberNameColumnRatio),
            _viewModel.HotkeyToggleLabel,
            _settings.CrosshairMode,
            OverlayDisplaySettings.NormalizeCrosshairSize(_settings.CrosshairSize),
            Math.Clamp(_settings.CrosshairThickness, 1, 8),
            Math.Clamp(_settings.CrosshairOpacity, 0.2, 1.0),
            _settings.CrosshairShowCenterMark,
            OverlayDisplaySettings.NormalizeCrosshairCenterMarkSize(_settings.CrosshairCenterMarkSize),
            OverlayDisplaySettings.NormalizeCrosshairGap(_settings.CrosshairGap),
            OverlayDisplaySettings.NormalizeCrosshairOutlineOpacity(_settings.CrosshairOutlineOpacity),
            OverlayDisplaySettings.ResolveEventNotificationAnimationScale(_settings.EventNotificationAnimationSpeed),
            SnapshotEvents(_viewModel.EventNotifications, sourceLabels.RowPrefix(OverlayModuleFlags.Events, sourceLabels.Events)),
            _viewModel.EventNotificationPulse,
            _settings.StartupTransitionFrameRate,
            _settings.AnimationFrameRate)
        { AppearanceEpoch = _appearanceEpoch, AppearanceSkin = _settings.Skin, AppearanceOptions = _settings.AppearanceOptions,
          CommunicationAppearanceActivities = _viewModel.CommunicationAppearanceActivities,
          BarrageFrameRate = _viewModel.PreserveBarrageMotion ? _viewModel.PreviewBarrageFrameRate : _settings.AnimationFrameRate,
          SourceLabels = sourceLabels, EmptyStates = _viewModel.ModuleEmptyStates, MemberPaging = _viewModel.MemberPaging,
          OverviewFacts = _viewModel.OverviewFacts,
          EmptyNoticeTitle = _language.StartsWith("zh", StringComparison.OrdinalIgnoreCase) ? "公告" : "NOTICE",
          EmptyEventsTitle = _language.StartsWith("zh", StringComparison.OrdinalIgnoreCase) ? "事件通知" : "EVENTS" }));
    }

    private static bool IsNightShadowStyle(OverlayDisplaySettings settings)
    {
        return settings.Skin == OverlaySkin.NightShadow ||
               settings.Theme == OverlayVisualTheme.NightShadow;
    }

    private void ApplyLayoutDependentViewModelState()
    {
        var resolvedItems = OverlaySurfaceLayout.ResolveItems(
            _layout,
            Math.Max(1, _surfaceBounds.Width),
            Math.Max(1, _surfaceBounds.Height));
        var membersRect = ResolveItemRect("Members", resolvedItems);
        _viewModel.ApplyMemberViewport(membersRect.Height);
        _viewModel.ApplyChatBarrageViewportWidth(Math.Max(1, _surfaceBounds.Width));
    }

    private static WpfRect ResolveItemRect(
        string key,
        IReadOnlyDictionary<string, WpfRect> resolvedItems)
    {
        return resolvedItems.TryGetValue(key, out var rect)
            ? rect
            : new WpfRect(0, 0, 1, 1);
    }

    private WpfRect ResolveEventNotificationRect(double width, double height)
    {
        // Reserve enough vertical space for wrapped title/detail rows before DirectWrite measures them.
        var eventHeight = Math.Max(72, _viewModel.EventNotifications.Count * 90);
        return OverlaySurfaceLayout.ResolveEventNotificationRect(
            width,
            height,
            _settings.EventNotificationSide,
            _settings.EventNotificationY,
            eventHeight);
    }

    private OverlayCompositionHudWindow.OverlayCompositionModuleStyle ResolveModuleStyle(string key)
    {
        var item = _layout.FirstOrDefault(layoutItem =>
            layoutItem.Key.Equals(key, StringComparison.OrdinalIgnoreCase));
        return item is null
            ? OverlayCompositionModuleStyle.Default
            : new OverlayCompositionModuleStyle(
                OverlayLayoutItem.NormalizeTextOpacity(item.TextOpacity),
                OverlayLayoutItem.NormalizeBackgroundOpacity(item.BackgroundOpacity),
                OverlayLayoutItem.NormalizeDecorationOpacity(item.DecorationOpacity));
    }

    private IReadOnlyList<string> ResolveModuleDrawOrder()
    {
        var keys = _layout
            .Select(item => item.Key)
            .Where(IsCompositionOverlayModuleKey)
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToList();
        foreach (var key in new[] { "Notice", "Squads", "Members", "Chat" })
        {
            if (!keys.Contains(key, StringComparer.OrdinalIgnoreCase))
            {
                keys.Add(key);
            }
        }

        return keys;
    }

    private static bool IsCompositionOverlayModuleKey(string key)
    {
        return key.Equals("Notice", StringComparison.OrdinalIgnoreCase) ||
               key.Equals("Squads", StringComparison.OrdinalIgnoreCase) ||
               key.Equals("Members", StringComparison.OrdinalIgnoreCase) ||
               key.Equals("Chat", StringComparison.OrdinalIgnoreCase);
    }
}
