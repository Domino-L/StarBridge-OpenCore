import 'notification_settings_models.dart';
import 'notification_settings_port.dart';

final class InMemoryNotificationSettingsAdapter
    implements NotificationSettingsPort {
  InMemoryNotificationSettingsAdapter({
    required NotificationSettingsSnapshot initial,
  }) : _snapshot = initial;

  factory InMemoryNotificationSettingsAdapter.forReview() =>
      InMemoryNotificationSettingsAdapter(
        initial: NotificationSettingsSnapshot.available(
          revision: 11,
          settings: NotificationSettingsValue.reviewDefaults(
            sourceRules: const [
              NotificationSourceRule(
                sourceRef: 'official-fleet:aster',
                kind: NotificationSourceKind.officialFleet,
                displayName: "Aster's Wing",
                contextLabel: 'RSI · ASTER',
                mode: NotificationSourceMode.normal,
              ),
              NotificationSourceRule(
                sourceRef: 'community:northwind',
                kind: NotificationSourceKind.community,
                displayName: 'Northwind 联合社区',
                contextLabel: '社区组织',
                mode: NotificationSourceMode.importantOnly,
              ),
              NotificationSourceRule(
                sourceRef: 'room:aster-lin',
                kind: NotificationSourceKind.room,
                displayName: 'Aster Lin 的房间',
                contextLabel: '当前房间',
                mode: NotificationSourceMode.normal,
              ),
              NotificationSourceRule(
                sourceRef: 'operation:hurston-haul',
                kind: NotificationSourceKind.operation,
                displayName: 'Hurston 资源运输',
                contextLabel: '当前行动',
                mode: NotificationSourceMode.doNotDisturb,
              ),
            ],
          ),
        ),
      );

  NotificationSettingsSnapshot _snapshot;
  bool failNextUpdate = false;

  NotificationSettingsSnapshot get current => _snapshot;

  @override
  Stream<void> get invalidations => const Stream.empty();

  @override
  Future<NotificationSettingsSnapshot> read() async => _snapshot;

  @override
  Future<NotificationSettingsWriteResult> update(
    NotificationSettingsValue settings, {
    required int expectedRevision,
  }) async {
    if (failNextUpdate) {
      failNextUpdate = false;
      return const NotificationSettingsWriteResult.failed(
        NotificationSettingsFailure.writeFailed,
      );
    }
    final currentRevision = _snapshot.revision;
    if (_snapshot.availability != NotificationSettingsAvailability.available ||
        currentRevision == null ||
        currentRevision != expectedRevision) {
      return const NotificationSettingsWriteResult.failed(
        NotificationSettingsFailure.writeConflict,
      );
    }
    _snapshot = NotificationSettingsSnapshot.available(
      settings: settings,
      revision: currentRevision + 1,
      allowEditing: _snapshot.allowEditing,
    );
    return NotificationSettingsWriteResult.completed(_snapshot);
  }

  @override
  Future<void> close() async {}
}
