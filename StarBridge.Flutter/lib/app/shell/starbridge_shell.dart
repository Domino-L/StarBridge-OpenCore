import 'dart:async';

import '../routing/user_page_navigation.dart';

import '../tray/tray_application_binding.dart';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import '../composition/app_composition.dart';
import '../feature_registry.dart';
import '../runtime/example_scene_control.dart';
import '../routing/open_destination_intent.dart';
import '../../platform/host/desktop_notification_port.dart';
import '../localization/app_strings.dart';
import 'shell_layout_mode.dart';
import 'shell_focus_traversal.dart';
import 'shell_navigation_controller.dart';
import 'widgets/navigation_pane.dart';
import 'widgets/connection_status_notice.dart';
import 'widgets/sharing_status_notice.dart';
import 'widgets/example_scene_notice.dart';
import 'widgets/shell_top_bar.dart';
import 'widgets/shell_workspace.dart';

class StarBridgeShell extends StatefulWidget {
  const StarBridgeShell({
    required this.composition,
    required this.exampleSceneControl,
    this.onRetryConnection,
    this.navigationRequests,
    this.userNavigation,
    super.key,
  });

  final AppComposition composition;
  final ExampleSceneControl exampleSceneControl;
  final Future<void> Function()? onRetryConnection;
  final ValueListenable<OpenDestinationIntent?>? navigationRequests;
  final UserPageNavigation? userNavigation;

  @override
  State<StarBridgeShell> createState() => _StarBridgeShellState();
}

class _StarBridgeShellState extends State<StarBridgeShell> {
  late final ShellNavigationController _navigation;
  TrayApplicationBinding? _tray;
  StreamSubscription<DesktopReminderActivation>? _notificationClicks;
  final _userNavigator = GlobalKey<NavigatorState>();
  String? _userTitle;
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
    if (_selecting || !await _leaveAvatarDialog(source) || !mounted) return;
    final guard = _navigation.selected.confirmLeave;
    if (guard != null && !await guard(context)) return;
    if (!mounted) return;
    await _pushUserPage(builder, title);
  }

  Future<void> _pushUserPage(WidgetBuilder builder, String title) async {
    final previousTitle = _userTitle;
    final leave = UserPageLeaveGuard();
    _userLeaves.add(leave);
    setState(() => _userTitle = title);
    await _userNavigator.currentState!.push<void>(
      MaterialPageRoute(
        settings: RouteSettings(
          name: title == 'navigation.profile'
              ? '/profile/visitor'
              : '/friends/message',
        ),
        builder: (pageContext) {
          final page = builder(pageContext);
          return UserPageLeaveScope(
            guard: leave,
            child: ColoredBox(
              color: pageContext.tokens.surfaces.ground.fill,
              child: Column(
                children: [
                  if (page is! SelfNavigatingUserPage)
                    Row(
                      children: [
                        BackButton(
                          onPressed: () async {
                            if (leave.confirm != null &&
                                !await leave.confirm!()) {
                              return;
                            }
                            if (pageContext.mounted) {
                              Navigator.of(pageContext).pop();
                            }
                          },
                        ),
                        Text(AppStrings.of(pageContext).text(title)),
                      ],
                    ),
                  Expanded(child: page),
                ],
              ),
            ),
          );
        },
      ),
    );
    _userLeaves.remove(leave);
    if (mounted) {
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
      NavigationInteraction.pointer,
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
    _listenToNotifications();
    _bindTray();
    widget.navigationRequests?.addListener(_openRequestedDestination);
  }

  void _openRequestedDestination() {
    final request = widget.navigationRequests?.value;
    if (!mounted || request == null) return;
    unawaited(
      _select(
        widget.composition.features.byRoute(request.route),
        NavigationInteraction.pointer,
      ),
    );
  }

  void _bindTray() {
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
    if (oldWidget.navigationRequests != widget.navigationRequests) {
      oldWidget.navigationRequests?.removeListener(_openRequestedDestination);
      widget.navigationRequests?.addListener(_openRequestedDestination);
    }
    if (oldWidget.composition != widget.composition) {
      _bindTray();
    }
    if (oldWidget.composition.desktopNotifications !=
        widget.composition.desktopNotifications) {
      unawaited(_notificationClicks?.cancel());
      _notificationClicks = null;
      _listenToNotifications();
    }
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
      final destination = port is DesktopNotificationDestinationPort
          ? await (port as DesktopNotificationDestinationPort)
                .consumeDestination(activation)
          : await port.consume(activation)
          ? 'roomReminders'
          : null;
      if (destination == null) {
        _reminderUnavailable();
        return;
      }
      if (!current()) return;
      if (destination == 'directMessages') {
        _userNavigator.currentState?.popUntil((route) => route.isFirst);
        widget.composition.directMessageRequests?.value++;
        _navigation.select(
          widget.composition.features.byRoute('/friends'),
          interaction: NavigationInteraction.pointer,
        );
        return;
      }
      if (destination == 'communities') {
        _userNavigator.currentState?.popUntil((route) => route.isFirst);
        _navigation.select(
          widget.composition.features.byRoute('/communities'),
          interaction: NavigationInteraction.pointer,
        );
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          AppStrings.of(context)
              .text('settings.notification.activationUnavailable'),
        ),
      ),
    );
  }

  @override
  void dispose() {
    widget.userNavigation?.open = null;
    widget.userNavigation?.openSelf = null;
    widget.navigationRequests?.removeListener(_openRequestedDestination);
    unawaited(_notificationClicks?.cancel());
    _tray?.dispose();
    _navigation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Actions(
      actions: {
        OpenDestinationIntent: CallbackAction<OpenDestinationIntent>(
          onInvoke: (intent) {
            unawaited(
              _select(
                widget.composition.features.byRoute(intent.route),
                NavigationInteraction.pointer,
              ),
            );
            return null;
          },
        ),
      },
      child: Scaffold(
        body: DecoratedBox(
          key: const Key('application-window-frame'),
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            border: Border.all(
              color: tokens.surfaces.windowFrame,
              width: tokens.stroke.hairline,
            ),
          ),
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
                            onActivate: (descriptor) async {
                              await _select(
                                descriptor,
                                NavigationInteraction.pointer,
                              );
                              return mounted &&
                                  identical(_navigation.selected, descriptor);
                            },
                            mode: mode,
                            selected: _navigation.selected,
                            onSelect: (descriptor, interaction) =>
                                unawaited(_select(descriptor, interaction)),
                          ),
                        ),
                        Expanded(
                          child: FocusTraversalOrder(
                            order: const NumericFocusOrder(1),
                            child: Column(
                              children: [
                                ShellTopBar(
                                  selected: _userTitle == null
                                      ? _navigation.selected
                                      : widget.composition.features.byRoute(
                                          _userTitle == 'navigation.profile'
                                              ? '/profile'
                                              : '/friends',
                                        ),
                                  topBarDestinations: widget
                                      .composition
                                      .features
                                      .inRegion(NavigationRegion.topBar),
                                  accountMenuDestinations: widget
                                      .composition
                                      .features
                                      .inRegion(NavigationRegion.accountMenu),
                                  projection: projection,
                                  shellChrome: widget.composition.shellChrome,
                                  mode: mode,
                                  onSelect: (descriptor) => unawaited(
                                    _select(
                                      descriptor,
                                      NavigationInteraction.pointer,
                                    ),
                                  ),
                                  onAccountLogin: () => unawaited(
                                    _select(
                                      widget.composition.features.byRoute(
                                        '/settings/account',
                                      ),
                                      NavigationInteraction.pointer,
                                    ),
                                  ),
                                  onAccountLogout: () => unawaited(
                                    widget.composition.account.logout(),
                                  ),
                                  onAccountIssueAction: () => unawaited(
                                    widget.composition.resolveAccountIssue(),
                                  ),
                                  windowChrome: widget.composition.windowChrome,
                                ),
                                if (widget.exampleSceneControl.active)
                                  ExampleSceneNotice(
                                    control: widget.exampleSceneControl,
                                  ),
                                if (projection.connectionIssue
                                    case final issue?)
                                  ConnectionStatusNotice(
                                    issue: issue,
                                    retrying:
                                        projection
                                            .connectionIssueUsesAccountAction &&
                                        projection.accountBusy,
                                    onRetry:
                                        projection
                                            .connectionIssueUsesAccountAction
                                        ? () async {
                                            await widget.composition
                                                .resolveAccountIssue();
                                          }
                                        : widget.onRetryConnection,
                                  ),
                                if (!widget.exampleSceneControl.active &&
                                    widget.composition.localPrivacy != null)
                                  SharingStatusNotice(
                                    status: widget.composition.sharingStatus!,
                                    onOpenSettings: () => unawaited(
                                      _select(
                                        widget.composition.features.byRoute(
                                          '/settings/privacy',
                                        ),
                                        NavigationInteraction.pointer,
                                      ),
                                    ),
                                  ),
                                Expanded(
                                  child: Navigator(
                                    key: _userNavigator,
                                    onGenerateRoute: (_) =>
                                        MaterialPageRoute<void>(
                                          builder: (_) => ListenableBuilder(
                                            listenable: _navigation,
                                            builder: (_, _) => ShellWorkspace(
                                              selected: _navigation.selected,
                                              interaction:
                                                  _navigation.lastInteraction,
                                            ),
                                          ),
                                        ),
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
    );
  }

  bool _selecting = false;

  Future<void> _select(
    FeatureDescriptor descriptor,
    NavigationInteraction interaction,
  ) async {
    if (_selecting) return;
    _selecting = true;
    try {
      if (!await _confirmUserLeaves() || !mounted) return;
      if (identical(_navigation.selected, descriptor)) {
        _userNavigator.currentState?.popUntil((route) => route.isFirst);
        return;
      }
      final guard = _navigation.selected.confirmLeave;
      if (guard != null && !await guard(context)) return;
      if (!mounted) return;
      _userNavigator.currentState?.popUntil((route) => route.isFirst);
      _navigation.select(descriptor, interaction: interaction);
    } finally {
      _selecting = false;
    }
  }
}
