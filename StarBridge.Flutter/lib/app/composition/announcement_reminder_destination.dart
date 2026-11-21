import 'package:flutter/material.dart';

import 'app_composition.dart';
import '../routing/user_page_navigation.dart';
import '../../features/communities/community_announcements_dialog.dart';
import '../../features/communities/community_announcements_port.dart';
import '../../platform/host/desktop_notification_port.dart';

/// The click holds only a current Host reference. Content is read again by the
/// existing announcement owner, including its account and permission fences.
Future<Widget?> announcementReminderDestination(
  AppComposition composition,
  DesktopNotificationTarget target,
  bool Function() current,
) async {
  final ref = target.ref;
  if (ref == null || !current()) return null;
  if (target.destination == 'officialFleetAnnouncements') {
    final fleet = composition.officialFleet;
    await fleet.refresh();
    if (!current() || fleet.projection.value.fleet?.sourceRef != ref) {
      return null;
    }
    await fleet.communication.refresh(ref);
    if (!current() || !fleet.communication.announcementsAvailable) return null;
    return ListenableBuilder(
      listenable: Listenable.merge([fleet.projection, fleet.communication]),
      builder: (context, _) {
        if (!current() ||
            fleet.projection.value.fleet?.sourceRef != ref ||
            !fleet.communication.announcementsAvailable) {
          return const SizedBox.shrink();
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: fleet.communication.announcement(expanded: true),
        );
      },
    );
  }
  final port = composition.communities.port;
  if (port is! CommunityAnnouncementsPort) return null;
  final announcements = port as CommunityAnnouncementsPort;
  if (!announcements.announcementsAvailable) return null;
  return _CommunityAnnouncementReminder(
    key: ValueKey(('announcement-reminder', ref)),
    port: announcements,
    targetRef: ref,
  );
}

class _CommunityAnnouncementReminder extends StatefulWidget {
  const _CommunityAnnouncementReminder({
    required this.port,
    required this.targetRef,
    super.key,
  });
  final CommunityAnnouncementsPort port;
  final String targetRef;
  @override
  State<_CommunityAnnouncementReminder> createState() =>
      _CommunityAnnouncementReminderState();
}

class _CommunityAnnouncementReminderState
    extends State<_CommunityAnnouncementReminder> {
  final _entry = GlobalKey<CommunityAnnouncementEntryState>();
  UserPageLeaveGuard? _leave;
  Future<bool> _confirm() async =>
      await _entry.currentState?.confirmLeave() ?? true;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final leave = UserPageLeaveScope.maybeOf(context);
    if (identical(leave, _leave)) return;
    _leave?.confirm = null;
    _leave = leave;
    leave?.confirm = _confirm;
  }

  @override
  void dispose() {
    _leave?.confirm = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CommunityAnnouncementEntry(
    key: _entry,
    port: widget.port,
    targetRef: widget.targetRef,
    embedded: true,
  );
}
