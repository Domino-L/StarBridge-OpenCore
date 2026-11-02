import 'starbridge_icons_v2_spec.dart';

// StarBridge graphic-design award-cup geometry, selected by the user.
// Retains the delivered 24-unit coordinates and compact-detail rule.
final List<IconSpec> achievementIconsV2 = [
  IconSpec('achievement', '成就中心', iconGroups[0], ['SB.achievement'], (g) {
    g.p([6.83, 5.7, 3, 5.7, 3, 8.6, 5.2, 10.8, 7.6, 10.8]);
    g.p([17.17, 5.7, 21, 5.7, 21, 8.6, 18.8, 10.8, 16.4, 10.8]);
    g.p([
      6.5,
      3.5,
      17.5,
      3.5,
      16.4,
      10.8,
      13.8,
      13.5,
      10.2,
      13.5,
      7.6,
      10.8,
    ], close: true);
    g.l(12, 13.5, 12, 18.8);
    g.fp([9.5, 18, 14.5, 18, 16.5, 21, 7.5, 21]);
    if (g.fine) g.spark(12, 8.1, 2.45, ry: 2.65, waist: 0.6);
  }, note: '星芒奖杯；小尺寸省略杯内星芒'),
];
