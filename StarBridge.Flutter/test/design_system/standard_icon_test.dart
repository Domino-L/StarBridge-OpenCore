import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/design_system/icons/standard_icon.dart';

void main() {
  // Pins the pre-migration artwork, not a new icon design.
  const originalGlyphs = {
    StandardIconSemantic.accountCircle: Icons.account_circle_outlined,
    StandardIconSemantic.add: Icons.add,
    StandardIconSemantic.adminPanelSettings: Icons.admin_panel_settings_outlined,
    StandardIconSemantic.alternateEmail: Icons.alternate_email,
    StandardIconSemantic.arrowBack: Icons.arrow_back,
    StandardIconSemantic.arrowDownward: Icons.arrow_downward,
    StandardIconSemantic.arrowForward: Icons.arrow_forward,
    StandardIconSemantic.attachFile: Icons.attach_file,
    StandardIconSemantic.badge: Icons.badge_outlined,
    StandardIconSemantic.brokenImage: Icons.broken_image_outlined,
    StandardIconSemantic.campaign: Icons.campaign_outlined,
    StandardIconSemantic.chatBubble: Icons.chat_bubble_outline,
    StandardIconSemantic.checkCircle: Icons.check_circle,
    StandardIconSemantic.chevronLeft: Icons.chevron_left,
    StandardIconSemantic.chevronRight: Icons.chevron_right,
    StandardIconSemantic.circle: Icons.circle,
    StandardIconSemantic.circleOutline: Icons.circle_outlined,
    StandardIconSemantic.close: Icons.close,
    StandardIconSemantic.copyAll: Icons.copy_all_outlined,
    StandardIconSemantic.copy: Icons.copy_outlined,
    StandardIconSemantic.dashboard: Icons.dashboard_outlined,
    StandardIconSemantic.deleteForever: Icons.delete_forever_outlined,
    StandardIconSemantic.delete: Icons.delete_outline,
    StandardIconSemantic.edit: Icons.edit_outlined,
    StandardIconSemantic.event: Icons.event_outlined,
    StandardIconSemantic.expandLess: Icons.expand_less,
    StandardIconSemantic.expandMore: Icons.expand_more,
    StandardIconSemantic.groupAdd: Icons.group_add_outlined,
    StandardIconSemantic.groups: Icons.groups_outlined,
    StandardIconSemantic.history: Icons.history_outlined,
    StandardIconSemantic.hourglassTop: Icons.hourglass_top,
    StandardIconSemantic.image: Icons.image_outlined,
    StandardIconSemantic.info: Icons.info_outline,
    StandardIconSemantic.language: Icons.language,
    StandardIconSemantic.layers: Icons.layers_outlined,
    StandardIconSemantic.logout: Icons.logout,
    StandardIconSemantic.meetingRoom: Icons.meeting_room_outlined,
    StandardIconSemantic.moreHoriz: Icons.more_horiz,
    StandardIconSemantic.north: Icons.north,
    StandardIconSemantic.outbox: Icons.outbox_outlined,
    StandardIconSemantic.people: Icons.people_outline,
    StandardIconSemantic.personAddAlt: Icons.person_add_alt_outlined,
    StandardIconSemantic.person: Icons.person_outline,
    StandardIconSemantic.personRemove: Icons.person_remove_outlined,
    StandardIconSemantic.public: Icons.public,
    StandardIconSemantic.radioButtonChecked: Icons.radio_button_checked,
    StandardIconSemantic.radioButtonOff: Icons.radio_button_off,
    StandardIconSemantic.radioButtonUnchecked: Icons.radio_button_unchecked,
    StandardIconSemantic.refresh: Icons.refresh,
    StandardIconSemantic.rocketLaunch: Icons.rocket_launch_outlined,
    StandardIconSemantic.schedule: Icons.schedule,
    StandardIconSemantic.search: Icons.search,
    StandardIconSemantic.send: Icons.send_outlined,
    StandardIconSemantic.share: Icons.share_outlined,
    StandardIconSemantic.south: Icons.south,
    StandardIconSemantic.sportsEsports: Icons.sports_esports_outlined,
    StandardIconSemantic.swapHoriz: Icons.swap_horiz,
    StandardIconSemantic.unfoldLess: Icons.unfold_less,
    StandardIconSemantic.unfoldMore: Icons.unfold_more,
    StandardIconSemantic.verifiedUser: Icons.verified_user_outlined,
    StandardIconSemantic.visibility: Icons.visibility_outlined,
    StandardIconSemantic.warningAmber: Icons.warning_amber_outlined,
  };
  testWidgets('all standard semantics preserve the accepted glyphs', (tester) async {
    expect(originalGlyphs.length, StandardIconSemantic.values.length);
    for (final entry in originalGlyphs.entries) {
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.rtl,
        child: StandardIcon(entry.key, size: 18, color: Colors.blue,
          semanticLabel: 'Action', textDirection: TextDirection.rtl),
      ));
      final glyph = tester.widget<Icon>(find.byType(Icon));
      expect(glyph.icon, entry.value);
      expect(glyph.size, 18);
      expect(glyph.color, Colors.blue);
      expect(glyph.semanticLabel, 'Action');
      expect(glyph.textDirection, TextDirection.rtl);
    }
  });
  testWidgets('unset presentation delegates to ambient IconTheme', (tester) async {
    await tester.pumpWidget(const Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: IconTheme(data: IconThemeData(size: 30, color: Colors.green),
        child: StandardIcon(StandardIconSemantic.refresh))),
    ));
    final glyph = tester.widget<Icon>(find.byType(Icon));
    expect(glyph.size, isNull);
    expect(glyph.color, isNull);
    expect(tester.getSize(find.byType(Icon)), const Size(30, 30));
  });
}
