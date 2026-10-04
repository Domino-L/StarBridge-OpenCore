import 'dart:async';

import 'package:flutter/material.dart';

import '../../features/notifications/starbridge_notification_toast.dart';
import '../../features/notifications/local_notification_content.dart';
import '../../features/settings/bridge_notification_settings_adapter.dart';
import '../../features/settings/notification_settings_models.dart';
import '../../features/settings/notification_settings_module.dart';
import '../localization/app_strings.dart';
import '../../platform/host/desktop_notification_port.dart';

class LocalNotificationListener extends StatefulWidget {
  const LocalNotificationListener({
    required this.events,
    required this.settings,
    required this.child,
    this.desktop,
    this.visibleConversationKey,
    this.menuOwnsNotices,
    super.key,
  });
  final Stream<LocalRoomReminder?> events;
  final NotificationSettingsModule settings;
  final Widget child;
  final DesktopNotificationPort? desktop;
  final String? Function()? visibleConversationKey;
  final bool Function()? menuOwnsNotices;
  @override
  State<LocalNotificationListener> createState() =>
      _LocalNotificationListenerState();
}

class _LocalNotificationListenerState extends State<LocalNotificationListener>
    with WidgetsBindingObserver {
  late StreamSubscription<LocalRoomReminder?> _subscription;
  VoidCallback? _dismiss;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _subscribe();
  }

  void _subscribe() {
    _subscription = widget.events.listen(_receive);
    widget.settings.projection.addListener(_clear);
  }

  void _clear() {
    _dismiss?.call();
    _dismiss = null;
    unawaited(widget.desktop?.clear());
  }

  void _receive(LocalRoomReminder? event) {
    _clear();
    final projection = widget.settings.projection.value;
    final value = projection.settings;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (!mounted ||
        event == null ||
        event.overlayHandled ||
        ((event.kind == 'direct' || event.kind == 'friend') &&
            widget.menuOwnsNotices?.call() == true) ||
        !projection.canEdit ||
        value == null ||
        event.revision != projection.revision) {
      return;
    }
    final content = localNotificationContent(
      AppStrings.of(context),
      event,
      value.previewMode,
    );
    final activeKey = widget.visibleConversationKey?.call();
    if (event.kind == 'direct' &&
        activeKey != null &&
        event.conversationKeys.isNotEmpty &&
        event.conversationKeys.every((key) => key == activeKey)) {
      return;
    }
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) {
      if (event.desktopEligible &&
          value.desktopDeliveryAvailable &&
          value.channels.windowsDesktopEnabled) {
        unawaited(
          widget.desktop?.show(
            content.title,
            content.message,
            ticket: event.desktopTicket,
          ),
        );
      }
      return;
    }
    if (!value.channels.inAppEnabled) return;
    _dismiss = showStarBridgeNotificationToast(
      context,
      alignment: switch (value.channels.desktopPosition) {
        DesktopNotificationPosition.topLeft => Alignment.topLeft,
        DesktopNotificationPosition.topRight => Alignment.topRight,
        DesktopNotificationPosition.bottomLeft => Alignment.bottomLeft,
        DesktopNotificationPosition.bottomRight => Alignment.bottomRight,
      },
      title: content.title,
      message: content.message,
    );
  }

  @override
  void didUpdateWidget(covariant LocalNotificationListener oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.events != widget.events ||
        oldWidget.settings != widget.settings ||
        oldWidget.desktop != widget.desktop) {
      unawaited(oldWidget.desktop?.clear());
      _clear();
      unawaited(_subscription.cancel());
      oldWidget.settings.projection.removeListener(_clear);
      _subscribe();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _clear();
  }

  @override
  void dispose() {
    _clear();
    unawaited(_subscription.cancel());
    widget.settings.projection.removeListener(_clear);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
