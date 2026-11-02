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
       transientFailure = false,
       failureKey = null;

  const OfficialFleetOverviewSnapshot.unavailable({
    required this.failureKey,
    this.transientFailure = false,
  }) : availability = OfficialFleetOverviewAvailability.unavailable,
       announcement = null,
       metrics = null,
       tasks = const <OfficialFleetOverviewTask>[],
       observedAtUtc = null;

  final OfficialFleetOverviewAvailability availability;
  final bool transientFailure;
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
      isRefreshing = false,
      announcement = null,
      metrics = null,
      tasks = const <OfficialFleetOverviewTask>[],
      observedAtUtc = null,
      failureKey = null;

  const OfficialFleetOverviewProjection.loading()
    : availability = OfficialFleetOverviewAvailability.loading,
      isRefreshing = false,
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
  }) : isRefreshing = false;

  OfficialFleetOverviewProjection.refreshing(
    OfficialFleetOverviewProjection value,
  ) : this.retained(value, failureKey: value.failureKey, isRefreshing: true);

  OfficialFleetOverviewProjection.retained(
    OfficialFleetOverviewProjection value, {
    required this.failureKey,
    this.isRefreshing = false,
  }) : availability = value.availability,
       announcement = value.announcement,
       metrics = value.metrics,
       tasks = value.tasks,
       observedAtUtc = value.observedAtUtc;

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
  final bool isRefreshing;
  bool get refreshFailed =>
      availability == OfficialFleetOverviewAvailability.available &&
      failureKey != null;
  final OfficialFleetOverviewAnnouncement? announcement;
  final OfficialFleetOverviewMetrics? metrics;
  final List<OfficialFleetOverviewTask> tasks;
  final DateTime? observedAtUtc;
  final String? failureKey;
}
