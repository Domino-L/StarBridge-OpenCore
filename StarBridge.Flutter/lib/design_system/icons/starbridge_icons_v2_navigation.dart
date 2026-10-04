import 'dart:math' as math;

import 'starbridge_icons_v2_spec.dart';

final List<IconSpec> navigationIconsV2 = [
  // 导航与模块 -------------------------------------------------------------
  IconSpec('home', '主页', iconGroups[0], ['SB.home'], (g) {
    if (!g.fine) return g.spark(12, 12, 9.4, waist: 3.2);
    if (!g.display) return g.spark(12, 12, 9.0, ry: 9.8, waist: 3.0);
    g.spark(12, 12, 6.6, ry: 8.8, waist: 1.15);
    g.trail(8.7, 14.5, 2.6, 17.5, 1.6);
    g.trail(15.3, 9.5, 21.4, 6.5, 1.6);
  }, note: '标志缩影；24px 以上带航迹'),
  IconSpec(
    'community',
    '组织',
    iconGroups[0],
    ['SB.community', 'Std.groups', 'Menu.group'],
    (g) {
      g.l(3, 3.5, 21, 3.5);
      g.p([5.5, 3.5, 5.5, 17, 12, 21, 18.5, 17, 18.5, 3.5]);
      g.node(12, 10.8, 3.6);
    },
    note: '组织旗帜：悬挂旗 + 星芒徽记',
  ),
  IconSpec('officialFleet', '主舰队', iconGroups[0], ['SB.officialFleet'], (g) {
    g.spark(12, 10.5, 3.8, ry: 5.2, waist: 0.9);
    for (final s in [-1.0, 1.0]) {
      double x(double v) => 12 + s * v;
      g.p([x(4.4), 8.4, x(10), 5.6]);
      g.p([x(4.4), 11.2, x(9.4), 10]);
      if (g.fine) g.p([x(4.4), 14, x(8), 14.2]);
    }
    g.p([7, 17, 12, 20.5, 17, 17]);
  }, note: '中队徽章：星芒 + 多面翼'),
  IconSpec(
    'room',
    '房间',
    iconGroups[0],
    ['SB.room', 'Std.meetingRoom', 'Menu.room'],
    (g) {
      g.p([4, 20, 4, 4, 16, 4, 18.5, 6.5, 18.5, 20]);
      g.p([8, 20, 8, 7.25, 16, 5.5, 16, 20]);
      g.node(13.1, 12.8, 2.1);
      g.l(3, 20, 21, 20);
    },
  ),
  IconSpec('operation', '行动', iconGroups[0], ['SB.operation'], (g) {
    g.l(6, 3, 6, 21);
    g.p([6, 4.5, 19, 4.5, 15.5, 8.5, 19, 12.5, 6, 12.5]);
  }, note: '燕尾旗'),
  IconSpec('hangar', '机库', iconGroups[0], ['SB.hangar'], (g) {
    g.p([3, 20.5, 3, 7.5, 6, 4.5, 18, 4.5, 21, 7.5, 21, 20.5]);
    g.p([6.5, 20.5, 6.5, 9.5, 17.5, 9.5, 17.5, 20.5]);
    if (g.fine) {
      g.l(6.5, 13.2, 17.5, 13.2);
      g.l(6.5, 16.9, 17.5, 16.9);
    } else {
      g.l(6.5, 15, 17.5, 15);
    }
    g.l(2, 20.5, 22, 20.5);
  }, note: '方正机库，平顶 + 分段舱门'),
  IconSpec('ship', '舰船', iconGroups[0], ['Std.rocketLaunch', 'Menu.ship'], (g) {
    g.p([
      12,
      2.8,
      13.8,
      7,
      13.8,
      11.2,
      20,
      16,
      20,
      18.6,
      13.8,
      16.8,
      13,
      20.8,
      11,
      20.8,
      10.2,
      16.8,
      4,
      18.6,
      4,
      16,
      10.2,
      11.2,
      10.2,
      7,
    ], close: true);
    if (g.fine) g.l(12, 7.5, 12, 10.5);
  }, note: '俯视舰影，替换火箭'),
  IconSpec('marketplace', '交易', iconGroups[0], ['SB.marketplace'], (g) {
    g.p([
      12,
      3,
      19.8,
      7.5,
      19.8,
      16.5,
      12,
      21,
      4.2,
      16.5,
      4.2,
      7.5,
    ], close: true);
    g.p([4.2, 7.5, 12, 12, 19.8, 7.5]);
    g.l(12, 12, 12, 21);
    if (g.fine) g.l(8.1, 5.25, 15.9, 9.75);
  }, note: '货运箱（SCU）'),
  IconSpec('tools', '工具', iconGroups[0], ['SB.tools'], (g) {
    g.cut(3.5, 8.5, 20.5, 20);
    g.p([9, 8.5, 9, 5, 15, 5, 15, 8.5]);
    if (g.fine) {
      g.l(3.5, 13.5, 10, 13.5);
      g.l(14, 13.5, 20.5, 13.5);
      g.rect(10, 12, 14, 15.5);
    } else {
      g.l(3.5, 13.5, 20.5, 13.5);
    }
  }, note: '工具箱'),
  IconSpec('overlay', '信息浮层', iconGroups[0], ['SB.overlay', 'Menu.overlay'], (
    g,
  ) {
    g.p([3, 17, 7, 13, 21, 13, 17, 17], close: true);
    g.p([3, 9.5, 7, 5.5, 21, 5.5, 17, 9.5], close: true);
    if (g.fine) {
      g.l(12, 9.5, 12, 11.2);
      g.l(12, 14.8, 12, 13);
    }
    g.l(3, 20.5, 17, 20.5);
  }, note: '双层平面：游戏层 + 浮动信息层'),
  IconSpec('dashboard', '概览', iconGroups[0], ['Std.dashboard'], (g) {
    g.rect(3.5, 3.5, 10.5, 12.5);
    g.cut(13.5, 3.5, 20.5, 8.5, 2.2);
    g.rect(13.5, 11.5, 20.5, 20.5);
    g.rect(3.5, 15.5, 10.5, 20.5);
  }),
  IconSpec('settings', '设置', iconGroups[0], ['SB.settings', 'Menu.settings'], (
    g,
  ) {
    final xy = <double>[];
    for (var i = 0; i < 8; i++) {
      final a = i * 45.0 - 90;
      for (final (deg, r) in [
        (a - 15, 6.9),
        (a - 8, 9.2),
        (a + 8, 9.2),
        (a + 15, 6.9),
      ]) {
        final t = deg * math.pi / 180;
        xy
          ..add(12 + r * math.cos(t))
          ..add(12 + r * math.sin(t));
      }
    }
    g.p(xy, close: true);
    g.hex(12, 12, g.fine ? 3.0 : 2.6);
  }, note: '多面齿轮'),
];
