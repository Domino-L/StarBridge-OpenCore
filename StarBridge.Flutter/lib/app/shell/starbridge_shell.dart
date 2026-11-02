import 'dart:async';

import '../diagnostics/loading_diagnostics.dart';
import '../diagnostics/loading_tour.dart';

import '../routing/user_page_navigation.dart';

import '../tray/tray_application_binding.dart';
import '../../platform/window/taskbar_attention_binding.dart';
import '../friends_window/friends_window_binding.dart';
import '../social_windows/social_window_binding.dart';
import '../composition/social_window_actions.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/interaction/starbridge_page_route.dart';
import '../composition/app_composition.dart';
import '../feature_registry.dart';
import '../runtime/example_scene_control.dart';
import '../runtime/online_restore_flow.dart';
import '../routing/open_destination_intent.dart';
import '../../platform/host/desktop_notification_port.dart';
import '../composition/room_invitation_navigation.dart';
import '../routing/room_invitation_destination.dart';
import '../routing/destination_section.dart';
import 'shell_layout_mode.dart';
import 'trade_reminder_destination.dart';
import 'shell_focus_traversal.dart';
import 'shell_navigation_controller.dart';
import 'widgets/navigation_pane.dart';
import '../composition/shell_top_bar_composition.dart';
import 'widgets/shell_workspace_frame.dart';
import 'widgets/shell_runtime_notices.dart';
import 'widgets/shell_user_page_frame.dart';

class StarBridgeShell extends StatefulWidget {
  const StarBridgeShell({
    required this.composition,
    required this.exampleSceneControl,
    this.taskbarAttentionScope,
    this.onRetryConnection,
    this.onHandleMismatch,
    this.navigationRequests,
    this.userNavigation,
    super.key,
  });

  final AppComposition composition;
  final TaskbarAttentionScope? taskbarAttentionScope;
  final ExampleSceneControl exampleSceneControl;
  final Future<void> Function()? onRetryConnection;
  final Future<void> Function()? onHandleMismatch;
  final ValueListenable<OpenDestinationIntent?>? navigationRequests;
  final UserPageNavigation? userNavigation;

  @override
  State<StarBridgeShell> createState() => _StarBridgeShellState();
}

class _StarBridgeShellState extends State<StarBridgeShell> {
  late final ShellNavigationController _navigation;
  TrayApplicationBinding? _tray;
  OnlineRestoreFlow? _onlineRestore;
  TaskbarAttentionBinding? _taskbar;
  late final _taskbarScope =
      widget.taskbarAttentionScope ?? TaskbarAttentionScope();
  FriendsWindowBinding? _friendsWindow;
  SocialWindowBinding? _messagesWindow, _notificationsWindow;
  VoidCallback? _unbindLoadingTour;

  void _bindSocialWindows() {
    _messagesWindow?.dispose();
    _notificationsWindow?.dispose();
    final composition = widget.composition;
    Future<void> navigate(String route) async {
      if (!mounted) return;
      await _openDestination(route);
    }

    _messagesWindow = composeSocialWindow(
      kind: 'messages',
      composition: composition,
      context: context,
      navigate: navigate,
      openProfile: (builder) async {
        if (mounted) {
          await _openUserPage(context, builder, 'navigation.profile');
        }
      },
    );
    _notificationsWindow = composeSocialWindow(
      kind: 'notifications',
      composition: composition,
      context: context,
      navigate: navigate,
      openProfile: (_) async {},
    );
    composition.friends.detachedVisibleConversation = () =>
        _messagesWindow?.visibleConversationKey;
  }

  StreamSubscription<DesktopReminderActivation>? _notificationClicks;
  final _userNavigator = GlobalKey<NavigatorState>();
  String? _userTitle;
  NavigationInteraction _titleInteraction = NavigationInteraction.keyboard;
  int _titleNavigationSerial = 0;

  // Presentation metadata only. Navigation remains owned by the existing
  // controller and leave guards; denied commands never change the title.
  void _recordTitleNavigation() {
    _titleNavigationSerial++;
    _titleInteraction = _navigation.lastInteraction;
  }

  final _userLeaves = <UserPageLeaveGuard>[];
  Future<bool> _confirmUserLeaves() async {
    for (final guard in _userLeaves.reversed.toList()) {
      if (guard.confirm != null && !await guard.confirm!()) return false;
      if (!mounted) return false;
    }
    return true;
  }

  Future<bool> _leaveAvatarDialog(BuildContext source) async {
    final root = Navigator.of(source, rootNavigator: true);
    if (root.canPop()) {
      final route = ModalRoute.of(source);
      if (route is PopupRoute) {
        await root.maybePop();
        if (route.isActive) return false;
      }
    }
    return mounted;
  }

  Future<void> _openUserPage(
    BuildContext source,
    WidgetBuilder builder,
    String title,
  ) async {
    final owner = widget.composition,
        selected = _navigation.selected,
        depth = _userLeaves.length;
    bool current() =>
        mounted &&
        identical(owner, widget.composition) &&
        identical(selected, _navigation.selected) &&
        depth == _userLeaves.length;
    if (_selecting || !await _leaveAvatarDialog(source) || !mounted) return;
    if (!current()) return;
    final guard = _navigation.selected.confirmLeave;
    if (guard != null && !await guard(context)) return;
    if (!current()) return;
    await _pushUserPage(builder, title);
  }

  Future<void> _pushUserPage(WidgetBuilder builder, String title) async {
    final previousTitle = _userTitle;
    final navigationSerial = _titleNavigationSerial;
    var handledBack = false;
    final leave = UserPageLeaveGuard();
    _userLeaves.add(leave);
    setState(() {
      _userTitle = title;
      _titleInteraction = currentNavigationInteraction;
    });
    late StarBridgePageRoute<void> pageRoute;
    var returning = false;
    Future<void> back(BuildContext pageContext, InteractionSource source) =>
        runStarBridgeActivation<void>(source, () async {
          if (returning || !mounted || !pageRoute.isCurrent) return;
          returning = true;
          try {
            if (leave.confirm != null && !await leave.confirm!()) return;
            if (pageContext.mounted && pageRoute.isCurrent) {
              handledBack = true;
              _titleInteraction = currentNavigationInteraction;
              Navigator.of(pageContext).pop();
            }
          } finally {
            returning = false;
          }
        });
    pageRoute = StarBridgePageRoute<void>.fromContext(
      context,
      settings: RouteSettings(
        name: title == 'navigation.profile'
            ? '/profile/visitor'
            : '/friends/message',
      ),
      builder: (pageContext) => buildShellUserPageFrame(
        pageContext,
        builder: builder,
        title: title,
        leave: leave,
        back: (source) => back(pageContext, source),
      ),
    );
    await _userNavigator.currentState!.push<void>(pageRoute);
    _userLeaves.remove(leave);
    if (mounted) {
      // A pop bypassing the explicit back command has no proved pointer source.
      // Main navigation may have supplied a newer source; do not overwrite it.
      if (!handledBack && navigationSerial == _titleNavigationSerial) {
        _titleInteraction = NavigationInteraction.keyboard;
      }
      setState(
        () => _userTitle = _userNavigator.currentState?.canPop() == true
            ? previousTitle
            : null,
      );
    }
  }

  Future<void> _openOwnPage(BuildContext source) async {
    if (!await _leaveAvatarDialog(source) || !mounted) return;
    await _select(
      widget.composition.features.byRoute('/profile'),
      currentStarBridgeActivationSource == InteractionSource.keyboard
          ? NavigationInteraction.keyboard
          : NavigationInteraction.pointer,
    );
  }

  @override
  void initState() {
    super.initState();
    widget.userNavigation?.open = _openUserPage;
    widget.userNavigation?.openSelf = _openOwnPage;
    _navigation = ShellNavigationController(
      initial: widget.composition.features.home,
    );
    _navigation.addListener(_recordTitleNavigation);
    _listenToNotifications();
    _bindTray();
    _bindSocialWindows();
    _bindFriendsWindow();
    widget.navigationRequests?.addListener(_openRequestedDestination);
    _unbindLoadingTour = LoadingDiagnostics.bindTour((route) async {
      if (!mounted || ModalRoute.of(context)?.isCurrent == false) {
        return LoadingTourSelection.blocked;
      }
      final destination = widget.composition.features.byRoute(route);
      var selected = false;
      await _select(
        destination,
        NavigationInteraction.pointer,
        onSelected: () => selected = true,
      );
      if (!mounted || !selected) return LoadingTourSelection.blocked;
      // Match the primary item's normal landing action after all leave guards.
      await destination.onPrimaryNavigation?.call();
      return LoadingTourSelection.workspace;
    });
  }

  void _openRequestedDestination() {
    final request = widget.navigationRequests?.value;
    if (!mounted || request == null) return;
    unawaited(_openDestination(request.route));
  }

  bool _openingRoomInvitation = false;
  Future<void> _openDestination(String route) async {
    final invitations = isRoomInvitationDestination(route);
    if (invitations && _openingRoomInvitation) return;
    if (invitations) _openingRoomInvitation = true;
    try {
      final (path, section) = invitations ? ('/rooms', null) : destinationSection(route);
      final destination = widget.composition.features.byRoute(path);
      if (section != null) destination.openSection?.call(section);
      var selected = false;
      await _select(
        destination,
        NavigationInteraction.pointer,
        onSelected: () => selected = true,
      );
      if (!mounted ||
          !selected ||
          !invitations ||
          !identical(_navigation.selected, destination)) {
        return;
      }
      if (!await openRoomInvitationDestination(
        context,
        widget.composition,
        route,
        isCurrent: () =>
            mounted && identical(_navigation.selected, destination),
      )) {
        if (mounted) _reminderUnavailable();
      }
    } finally {
      if (invitations) _openingRoomInvitation = false;
    }
  }

  void _bindTray() {
    _onlineRestore?.dispose();
    final composition = widget.composition,
        connection = widget.composition.manualPresence;
    _onlineRestore = connection == null
        ? null
        : OnlineRestoreFlow(
            connection: connection,
            account: composition.account,
            context: () => mounted ? context : null,
            current: () =>
                mounted &&
                identical(widget.composition, composition) &&
                !widget.exampleSceneControl.active,
          );
    _taskbar?.dispose();
    _taskbar = widget.composition.createTaskbarAttention(_taskbarScope);
    _tray?.dispose();
    _tray = TrayApplicationBinding(
      preferences: widget.composition.preferences.projection,
      chrome: widget.composition.shellChrome.projection,
      overlay: widget.composition.overlaySettings,
      presence: widget.composition.manualPresence,
      openOverlaySettings: () async {
        if (!mounted) return;
        final destination = widget.composition.features.byRoute('/overlay');
        await _select(destination, NavigationInteraction.pointer);
        if (!mounted || !identical(_navigation.selected, destination)) {
          throw StateError('Navigation cancelled');
        }
      },
    );
  }

  void _bindFriendsWindow() {
    _friendsWindow?.dispose();
    final composition = widget.composition;
    _friendsWindow = FriendsWindowBinding(
      preferences: composition.preferences,
      create: composition.createFriendsWindowSession,
      openMessages: (current) async {
        if (current() && mounted) {
          await _select(
            composition.features.byRoute('/messages'),
            NavigationInteraction.pointer,
          );
        }
      },
      openChat: (target, current) async {
        if (!current() || !mounted) return;
        final conversation = friendWindowConversation(
          reference: target.reference,
          name: target.name,
          avatar: target.avatar,
          stableKey: target.stableKey,
          presence: target.presence,
          gameId: target.gameId,
        );
        if (!kIsWeb &&
            defaultTargetPlatform == TargetPlatform.windows &&
            await _messagesWindow!.open(target: conversation)) {
          return;
        }
        await _select(
          composition.features.byRoute('/messages'),
          NavigationInteraction.pointer,
        );
        if (!current() ||
            !mounted ||
            _navigation.selected.route != '/messages') {
          return;
        }
        composition.friends.requestConversation(conversation);
      },
      openProfile: (target) async {
        if (!mounted ||
            !target.isCurrent() ||
            composition.userInteractions == null) {
          return;
        }
        if (!await _confirmUserLeaves() || !mounted || !target.isCurrent()) {
          return;
        }
        final guard = _navigation.selected.confirmLeave;
        if (guard != null && !await guard(context)) return;
        if (!mounted || !target.isCurrent()) return;
        unawaited(
          _pushUserPage(
            (_) => socialUserProfile(
              composition,
              source: target.source,
              reference: target.reference,
              query: target.query,
              avatar: target.avatar,
            ),
            'navigation.profile',
          ),
        );
      },
    );
  }

  void _listenToNotifications() {
    final Object? port = widget.composition.desktopNotifications;
    if (port is DesktopNotificationActivationPort) {
      _notificationClicks = port.activations.listen(
        (activation) => unawaited(_openReminder(port, activation)),
      );
    }
  }

  @override
  void didUpdateWidget(covariant StarBridgeShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userNavigation != widget.userNavigation) {
      if (oldWidget.userNavigation?.open == _openUserPage) {
        oldWidget.userNavigation?.open = null;
      }
      if (oldWidget.userNavigation?.openSelf == _openOwnPage) {
        oldWidget.userNavigation?.openSelf = null;
      }
      widget.userNavigation?.open = _openUserPage;
      widget.userNavigation?.openSelf = _openOwnPage;
    }
    if (oldWidget.navigationRequests != widget.navigationRequests) {
      oldWidget.navigationRequests?.removeListener(_openRequestedDestination);
      widget.navigationRequests?.addListener(_openRequestedDestination);
    }
    if (oldWidget.composition != widget.composition) {
      _bindTray();
      _bindSocialWindows();
      _bindFriendsWindow();
    }
    if (oldWidget.composition.desktopNotifications !=
        widget.composition.desktopNotifications) {
      unawaited(_notificationClicks?.cancel());
      _notificationClicks = null;
      _listenToNotifications();
    }
  }

  // A reminder click lands on the workspace root of one destination.
  void _openFromReminder(FeatureDescriptor destination) {
    _userNavigator.currentState?.popUntil((route) => route.isFirst);
    _navigation.select(destination, interaction: NavigationInteraction.pointer);
  }

  Future<void> _openReminder(
    DesktopNotificationActivationPort port,
    DesktopReminderActivation activation,
  ) async {
    bool current() =>
        mounted &&
        identical(port, widget.composition.desktopNotifications) &&
        port.isCurrent(activation);
    if (_selecting || !current()) return;
    _selecting = true;
    try {
      if (!await _confirmUserLeaves() || !mounted) return;
      final guard = _navigation.selected.confirmLeave;
      if (guard != null && !await guard(context)) return;
      if (!current()) return;
      final target = await consumeReminderTarget(port, activation);
      final destination = target?.destination;
      if (destination == null) {
        _reminderUnavailable();
        return;
      }
      if (!current()) return;
      final trade = tradeReminderDestination(
        widget.composition.features,
        destination,
        target,
      );
      if (trade != null) {
        _openFromReminder(trade);
        return;
      }
      if (destination == 'execHangar') {
        _openFromReminder(widget.composition.features.byRoute('/tools/exec-hangar'));
        return;
      }
      if (destination == 'gameIdentity') {
        if (widget.composition.handleMismatch.notice == null ||
            widget.onHandleMismatch == null) {
          _reminderUnavailable();
        } else {
          unawaited(widget.onHandleMismatch!());
        }
        return;
      }
      if (destination == 'notificationInbox') {
        if (!kIsWeb &&
            defaultTargetPlatform == TargetPlatform.windows &&
            await _notificationsWindow!.open()) {
          return;
        }
        _userNavigator.currentState?.popUntil((route) => route.isFirst);
        _navigation.select(
          widget.composition.features.byRoute('/notifications'),
          interaction: NavigationInteraction.pointer,
        );
        return;
      }
      if (destination == 'directMessages') {
        if (!kIsWeb &&
            defaultTargetPlatform == TargetPlatform.windows &&
            await _messagesWindow!.open()) {
          return;
        }
        _userNavigator.currentState?.popUntil((route) => route.isFirst);
        widget.composition.directMessageRequests?.value++;
        _navigation.select(
          widget.composition.features.byRoute('/messages'),
          interaction: NavigationInteraction.pointer,
        );
        return;
      }
      if (destination == 'officialFleet') {
        _openFromReminder(widget.composition.features.byRoute('/fleet'));
        return;
      }
      if (destination == 'communities') {
        _openFromReminder(widget.composition.features.byRoute('/communities'));
        return;
      }
      final rooms = widget.composition.partyRooms;
      final ready = await rooms.refreshForNotification();
      if (!current()) return;
      if (!ready) {
        _reminderUnavailable();
        return;
      }
      _userNavigator.currentState?.popUntil((route) => route.isFirst);
      _navigation.select(
        widget.composition.features.byRoute('/notifications'),
        interaction: NavigationInteraction.pointer,
      );
    } finally {
      _selecting = false;
    }
  }

  void _reminderUnavailable() {
    if (!mounted) return;
    showShellReminderUnavailable(context);
  }

  @override
  void dispose() {
    _unbindLoadingTour?.call();
    _messagesWindow?.dispose();
    _notificationsWindow?.dispose();
    _friendsWindow?.dispose();
    if (widget.userNavigation?.open == _openUserPage) {
      widget.userNavigation?.open = null;
    }
    if (widget.userNavigation?.openSelf == _openOwnPage) {
      widget.userNavigation?.openSelf = null;
    }
    widget.navigationRequests?.removeListener(_openRequestedDestination);
    unawaited(_notificationClicks?.cancel());
    _tray?.dispose();
    _navigation.dispose();
    _onlineRestore?.dispose();
    _taskbar?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(
          LogicalKeyboardKey.keyK,
          control: true,
        ): () async {
          if (ModalRoute.of(context)?.isCurrent == false) return;
          final destination = widget.composition.features.byRoute(
            '/marketplace',
          );
          var selected = false;
          await _select(
            destination,
            NavigationInteraction.keyboard,
            onSelected: () => selected = true,
          );
          if (mounted && selected) {
            await (destination.onSearchShortcut ??
                    destination.onPrimaryNavigation)
                ?.call();
          }
        },
      },
      child: Actions(
        actions: {
          OpenDestinationIntent: CallbackAction<OpenDestinationIntent>(
            onInvoke: (intent) {
              unawaited(_openDestination(intent.route));
              return null;
            },
          ),
        },
        child: Scaffold(
          body: ShellWindowFrame(
            child: ListenableBuilder(
              listenable: Listenable.merge([
                _navigation,
                widget.composition.shellChrome.projection,
              ]),
              builder: (context, _) {
                return LayoutBuilder(
                  builder: (context, constraints) {
                    final mode = ShellLayoutResolver.resolve(
                      constraints.maxWidth,
                    );
                    final projection =
                        widget.composition.shellChrome.projection.value;
                    return FocusTraversalGroup(
                      policy: ShellFocusTraversalPolicy(),
                      child: Row(
                        textDirection: TextDirection.ltr,
                        children: [
                          FocusTraversalOrder(
                            order: const NumericFocusOrder(0),
                            child: StarBridgeNavigationPane(
                              registry: widget.composition.features,
                              onActivateWithSource:
                                  (descriptor, interaction) async {
                                    await _select(descriptor, interaction);
                                    return mounted &&
                                        identical(
                                          _navigation.selected,
                                          descriptor,
                                        );
                                  },
                              mode: mode,
                              onPrimaryInteractionFinished:
                                  (descriptor, interaction) {
                                    if (mounted &&
                                        identical(
                                          _navigation.selected,
                                          descriptor,
                                        )) {
                                      setState(
                                        () => _navigation.recordInteraction(
                                          interaction,
                                        ),
                                      );
                                    }
                                  },
                              selected: _navigation.selected,
                              interaction: _navigation.lastInteraction,
                              onSelect: (descriptor, interaction) =>
                                  unawaited(_select(descriptor, interaction)),
                            ),
                          ),
                          Expanded(
                            child: FocusTraversalOrder(
                              order: const NumericFocusOrder(1),
                              child: Column(
                                children: [
                                  composeShellTopBar(
                                    composition: widget.composition,
                                    interaction: _titleInteraction,
                                    selected: _userTitle == null
                                        ? _navigation.selected
                                        : widget.composition.features.byRoute(
                                            _userTitle == 'navigation.profile'
                                                ? '/profile'
                                                : '/friends',
                                          ),
                                    projection: projection,
                                    mode: mode,
                                    onSelect: (descriptor) => unawaited(
                                      _select(
                                        descriptor,
                                        currentNavigationInteraction,
                                      ),
                                    ),
                                    onPrivacy: () => unawaited(
                                      _select(
                                        widget.composition.features.byRoute(
                                          '/settings/privacy',
                                        ),
                                        NavigationInteraction.pointer,
                                      ),
                                    ),
                                  ),
                                  ...shellRuntimeNotices(
                                    composition: widget.composition,
                                    projection: projection,
                                    exampleSceneControl:
                                        widget.exampleSceneControl,
                                    onRetryConnection: widget.onRetryConnection,
                                    onHandleMismatch: widget.onHandleMismatch,
                                    onOpenPrivacy: () => unawaited(
                                      _select(
                                        widget.composition.features.byRoute(
                                          '/settings/privacy',
                                        ),
                                        NavigationInteraction.pointer,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: ShellWorkspaceNavigator(
                                      navigatorKey: _userNavigator,
                                      navigation: _navigation,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  bool _selecting = false;

  Future<void> _select(
    FeatureDescriptor descriptor,
    NavigationInteraction interaction, {
    VoidCallback? onSelected,
  }) => runStarBridgeActivation(
    interaction == NavigationInteraction.keyboard ||
            currentStarBridgeActivationSource == InteractionSource.keyboard
        ? InteractionSource.keyboard
        : InteractionSource.pointer,
    () => _selectWithOrigin(descriptor, interaction, onSelected: onSelected),
  );

  Future<void> _selectWithOrigin(
    FeatureDescriptor descriptor,
    NavigationInteraction interaction, {
    VoidCallback? onSelected,
  }) async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      final window = descriptor.route == '/messages'
          ? _messagesWindow
          : descriptor.route == '/notifications'
          ? _notificationsWindow
          : null;
      if (window != null && (await window.open() || !mounted)) return;
    }
    if (!kIsWeb &&
        defaultTargetPlatform == TargetPlatform.windows &&
        descriptor.id == 'friends' &&
        _friendsWindow != null) {
      if (await _friendsWindow!.open() || !mounted) return;
      // Keep the existing page available if a native secondary view cannot open.
    }
    if (_selecting) return;
    _selecting = true;
    try {
      if (!await _confirmUserLeaves() || !mounted) return;
      if (identical(_navigation.selected, descriptor)) {
        setState(() {
          _navigation.recordInteraction(
            currentStarBridgeActivationSource == InteractionSource.keyboard
                ? NavigationInteraction.keyboard
                : NavigationInteraction.pointer,
          );
          _recordTitleNavigation();
        });
        _userNavigator.currentState?.popUntil((route) => route.isFirst);
        onSelected?.call();
        return;
      }
      final guard = _navigation.selected.confirmLeave;
      if (guard != null && !await guard(context)) return;
      if (!mounted) return;
      _userNavigator.currentState?.popUntil((route) => route.isFirst);
      _navigation.select(
        descriptor,
        interaction:
            currentStarBridgeActivationSource == InteractionSource.keyboard
            ? NavigationInteraction.keyboard
            : NavigationInteraction.pointer,
      );
      onSelected?.call();
    } finally {
      _selecting = false;
    }
  }
}
