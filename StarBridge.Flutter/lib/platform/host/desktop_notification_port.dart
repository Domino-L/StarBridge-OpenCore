import 'package:flutter/services.dart';

import '../bridge/bridge_client_session.dart';

/// Submission is not proof that Windows displayed it.
abstract interface class DesktopNotificationPort {
  Future<bool> show(
    String title,
    String message, {
    bool test = false,
    String? ticket,
  });
  Future<void> clear();
}

final class DesktopNotificationTestResult {
  const DesktopNotificationTestResult(this.submitted, this.reason);
  final bool submitted;
  final String reason;
  static const reasons = {
    'submitted',
    'disabled',
    'throttled',
    'doNotDisturb',
    'systemBusy',
    'fullScreen',
    'inactiveDesktop',
    'quietTime',
    'unsupported',
    'gameActiveOrUnknown',
    'appActiveOrUnknown',
    'queueFull',
    'expired',
    'unavailable',
  };
}

abstract interface class DesktopNotificationDiagnostics {
  Future<DesktopNotificationTestResult> testDesktop();
}

final class DesktopReminderActivation {
  const DesktopReminderActivation(this.id, this.generation);
  final String id;
  final int generation;
}

abstract interface class DesktopNotificationDestinationPort {
  Future<String?> consumeDestination(DesktopReminderActivation activation);
}

/// A destination with its opaque Host reference: `trade` (a transaction ref)
/// and `tradeChat` (a trade conversation ref); other destinations have none.
typedef DesktopNotificationTarget = ({String destination, String? ref});

abstract interface class DesktopNotificationTargetPort {
  Future<DesktopNotificationTarget?> consumeTarget(
    DesktopReminderActivation activation,
  );
}

abstract interface class DesktopNotificationActivationPort {
  Stream<DesktopReminderActivation> get activations;
  bool isCurrent(DesktopReminderActivation activation);
  Future<bool> consume(DesktopReminderActivation activation);
}

final class RunnerDesktopNotificationPort implements DesktopNotificationPort {
  const RunnerDesktopNotificationPort();
  static const _channel = MethodChannel('starbridge/application-lifecycle');
  @override
  Future<bool> show(
    String title,
    String message, {
    bool test = false,
    String? ticket,
  }) async {
    try {
      return await _channel.invokeMethod<bool>('showDesktopNotification', {
            'title': title,
            'message': message,
            'test': test,
          }) ==
          true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<void> clear() async {
    try {
      await _channel.invokeMethod<void>('clearDesktopNotification');
    } on PlatformException {
      /* Native output unavailable; no retry queue. */
    } on MissingPluginException {
      /* Older runner. */
    }
  }
}

/// Only asks the Host to redeem its short-lived ticket. No client-supplied content
/// or fallback tray popup can bypass native privacy/system suppression.
final class BridgeDesktopNotificationPort
    implements
        DesktopNotificationPort,
        DesktopNotificationDiagnostics,
        DesktopNotificationActivationPort,
        DesktopNotificationDestinationPort,
        DesktopNotificationTargetPort {
  const BridgeDesktopNotificationPort(this.session);
  final BridgeClientSession session;
  @override
  Stream<DesktopReminderActivation> get activations => session.events
      .where(
        (event) =>
            event.name == 'notificationSettings.activated' &&
            event.sessionGeneration == session.activeGeneration &&
            event.payload['schemaVersion'] == 1 &&
            event.payload['activationId'] is String &&
            RegExp(r'^[a-f0-9]{32}$')
                .hasMatch(event.payload['activationId'] as String),
      )
      .map(
        (event) => DesktopReminderActivation(
          event.payload['activationId'] as String,
          event.sessionGeneration,
        ),
      );
  @override
  bool isCurrent(DesktopReminderActivation activation) =>
      activation.generation == session.activeGeneration;
  @override
  Future<bool> consume(DesktopReminderActivation activation) async =>
      await consumeDestination(activation) == 'roomReminders';
  @override
  Future<String?> consumeDestination(
    DesktopReminderActivation activation,
  ) async => (await consumeTarget(activation))?.destination;

  static final _ref = RegExp(r'^[a-f0-9]{32}$');

  @override
  Future<DesktopNotificationTarget?> consumeTarget(
    DesktopReminderActivation activation,
  ) async {
    const name = 'notificationSettings.consumeActivation';
    if (!isCurrent(activation) || !session.hostCapabilities.contains(name)) {
      return null;
    }
    try {
      final response = await session.request(
        name,
        payload: {'schemaVersion': 1, 'activationId': activation.id},
      );
      final destination = response.payload['destination'];
      final ref = response.payload['ref'];
      if (!isCurrent(activation) || response.payload['schemaVersion'] != 1) {
        return null;
      }
      if (destination == 'trade' || destination == 'tradeChat') {
        // A trade or chat card without a usable ref still opens 我的交易.
        return ref is String && _ref.hasMatch(ref)
            ? (destination: destination as String, ref: ref)
            : (destination: 'myTrades', ref: null);
      }
      return destination == 'roomReminders' ||
              destination == 'notificationInbox' ||
              destination == 'directMessages' ||
              destination == 'communities' ||
              destination == 'officialFleet' ||
              destination == 'gameIdentity' ||
              destination == 'execHangar' ||
              destination == 'myTrades'
          ? (destination: destination as String, ref: null)
          : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<DesktopNotificationTestResult> testDesktop() async {
    const unavailable = DesktopNotificationTestResult(false, 'unavailable');
    const name = 'notificationSettings.testDesktop';
    if (!session.hostCapabilities.contains(name)) return unavailable;
    try {
      final response = await session.request(
        name,
        payload: {'schemaVersion': 1},
      );
      if (response.payload['schemaVersion'] != 1 ||
          response.payload['submitted'] is! bool) {
        return unavailable;
      }
      final submitted = response.payload['submitted'] == true;
      final reason = response.payload['reason'];
      return DesktopNotificationTestResult(
        submitted,
        submitted
            ? 'submitted'
            : reason is String &&
                  reason != 'submitted' &&
                  DesktopNotificationTestResult.reasons.contains(reason)
            ? reason
            : 'unavailable',
      );
    } catch (_) {
      return unavailable;
    }
  }

  @override
  Future<bool> show(
    String title,
    String message, {
    bool test = false,
    String? ticket,
  }) async {
    final name =
        'notificationSettings.${test ? 'testDesktop' : 'presentDesktop'}';
    if (!session.hostCapabilities.contains(name) || (!test && ticket == null)) {
      return false;
    }
    try {
      final response = await session.request(
        name,
        payload: {'schemaVersion': 1, if (!test) 'ticket': ticket},
      );
      return response.payload['schemaVersion'] == 1 &&
          response.payload['submitted'] == true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> clear() async {
    const name = 'notificationSettings.clearDesktop';
    if (!session.hostCapabilities.contains(name)) return;
    try {
      await session.request(name, payload: {'schemaVersion': 1});
    } catch (_) {
      /* No retry. */
    }
  }
}
