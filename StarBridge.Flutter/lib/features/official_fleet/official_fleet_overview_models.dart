import 'package:flutter/foundation.dart';

enum OfficialFleetOverviewAvailability { idle, loading, available, unavailable }

enum OfficialFleetOverviewTaskDestination {
  operations,
  members,
  ships,
  broadcasts,
}

@immutable
final class OfficialFleetOverviewAnnouncement {
  const OfficialFleetOverviewAnnouncement({
    required this.id,
    required this.title,
    required this.summary,
    required this.authorLabel,
    required this.publishedAtUtc,
    required this.unread,
  });

  final String id;
  final String title;
  final String summary;
  final String authorLabel;
  final DateTime publishedAtUtc;
  final bool unread;
}

@immutable
final class OfficialFleetOverviewMetrics {
  const OfficialFleetOverviewMetrics({
    required this.officialMemberCount,
    required this.visibleOnlineCount,
    required this.visibleInGameCount,
    required this.sharedRequestableShipCount,
  });

  final int officialMemberCount;
  final int visibleOnlineCount;
  final int visibleInGameCount;
  final int sharedRequestableShipCount;
}

@immutable
final class OfficialFleetOverviewTask {
  const OfficialFleetOverviewTask({
    required this.id,
    required this.title,
    required this.detail,
    required this.destination,
    this.dueAtUtc,
  });

  final String id;
  final String title;
  final String detail;
  final OfficialFleetOverviewTaskDestination destination;
  final DateTime? dueAtUtc;
}

@immutable
final class OfficialFleetOverviewSnapshot {
  const OfficialFleetOverviewSnapshot.available({
    required this.announcement,
    required this.metrics,
    required this.tasks,
    required this.observedAtUtc,
  }) : availability = OfficialFleetOverviewAvailability.available,
       failureKey = null;

  const OfficialFleetOverviewSnapshot.unavailable({required this.failureKey})
    : availability = OfficialFleetOverviewAvailability.unavailable,
      announcement = null,
      metrics = null,
      tasks = const <OfficialFleetOverviewTask>[],
      observedAtUtc = null;

  final OfficialFleetOverviewAvailability availability;
  final OfficialFleetOverviewAnnouncement? announcement;
  final OfficialFleetOverviewMetrics? metrics;
  final List<OfficialFleetOverviewTask> tasks;
  final DateTime? observedAtUtc;
  final String? failureKey;
}

@immutable
final class OfficialFleetOverviewProjection {
  const OfficialFleetOverviewProjection.idle()
    : availability = OfficialFleetOverviewAvailability.idle,
      announcement = null,
      metrics = null,
      tasks = const <OfficialFleetOverviewTask>[],
      observedAtUtc = null,
      failureKey = null;

  const OfficialFleetOverviewProjection.loading()
    : availability = OfficialFleetOverviewAvailability.loading,
      announcement = null,
      metrics = null,
      tasks = const <OfficialFleetOverviewTask>[],
      observedAtUtc = null,
      failureKey = null;

  const OfficialFleetOverviewProjection._({
    required this.availability,
    required this.announcement,
    required this.metrics,
    required this.tasks,
    required this.observedAtUtc,
    required this.failureKey,
  });

  factory OfficialFleetOverviewProjection.fromSnapshot(
    OfficialFleetOverviewSnapshot snapshot,
  ) => OfficialFleetOverviewProjection._(
    availability: snapshot.availability,
    announcement: snapshot.announcement,
    metrics: snapshot.metrics,
    tasks: List<OfficialFleetOverviewTask>.unmodifiable(snapshot.tasks),
    observedAtUtc: snapshot.observedAtUtc,
    failureKey: snapshot.failureKey,
  );

  final OfficialFleetOverviewAvailability availability;
  final OfficialFleetOverviewAnnouncement? announcement;
  final OfficialFleetOverviewMetrics? metrics;
  final List<OfficialFleetOverviewTask> tasks;
  final DateTime? observedAtUtc;
  final String? failureKey;
}
