import '../feature_registry.dart';
import '../../platform/host/desktop_notification_port.dart';

/// Trade reminders (CX-T23): the hall's 我的交易 (and that transaction's sheet
/// when the card carried a ref) or the trade conversation. Returns the
/// destination to select, after asking it to open the right section; null
/// when [destination] is not a trade destination.
FeatureDescriptor? tradeReminderDestination(
  FeatureRegistry features,
  String destination,
  DesktopNotificationTarget? target,
) {
  if (destination != 'trade' &&
      destination != 'tradeChat' &&
      destination != 'myTrades') {
    return null;
  }
  final feature = features.byRoute(
    destination == 'tradeChat' ? '/messages' : '/marketplace',
  );
  final ref = target?.ref;
  feature.openSection?.call(switch (destination) {
    'trade' || 'tradeChat' when ref != null => 'trade:$ref',
    'tradeChat' => 'trade',
    _ => 'trades',
  });
  return feature;
}

/// One click's destination, with the trade ref when the port carries one.
/// Older ports answer only a destination name, or only room reminders.
Future<DesktopNotificationTarget?> consumeReminderTarget(
  DesktopNotificationActivationPort port,
  DesktopReminderActivation activation,
) async {
  if (port is DesktopNotificationTargetPort) {
    return (port as DesktopNotificationTargetPort).consumeTarget(activation);
  }
  final destination = port is DesktopNotificationDestinationPort
      ? await (port as DesktopNotificationDestinationPort).consumeDestination(
          activation,
        )
      : await port.consume(activation)
      ? 'roomReminders'
      : null;
  return destination == null ? null : (destination: destination, ref: null);
}
