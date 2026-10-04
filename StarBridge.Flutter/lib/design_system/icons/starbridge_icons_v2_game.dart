import 'starbridge_icons_v2_pen.dart';
import 'starbridge_icons_v2_spec.dart';

final List<IconSpec> gameIconsV2 = [
  // 游戏与识别 -------------------------------------------------------------
  IconSpec(
    'gamepad',
    '游戏状态',
    iconGroups[3],
    ['SB.statusGame', 'Std.sportsEsports'],
    (g) {
      g.p([
        6.5,
        6.5,
        17.5,
        6.5,
        21,
        16,
        19.5,
        18.5,
        16.5,
        18.5,
        14.5,
        15,
        9.5,
        15,
        7.5,
        18.5,
        4.5,
        18.5,
        3,
        16,
      ], close: true);
      g.l(8, 9, 8, 13);
      g.l(6, 11, 10, 11);
      if (g.fine) {
        g.dot(15.6, 9.8, 1.15);
        g.dot(17.6, 12.1, 1.15);
      }
    },
  ),
  IconSpec('identity', '游戏身份', iconGroups[3], ['SB.statusIdentity'], (g) {
    g.p([
      7.5,
      3.5,
      16.5,
      3.5,
      19,
      6,
      19,
      18,
      16.5,
      20.5,
      7.5,
      20.5,
      5,
      18,
      5,
      6,
    ], close: true);
    g.circle(12, 7, 1.3);
    g.l(8.5, 12, 15.5, 12);
    if (g.fine) g.l(8.5, 15.5, 13.5, 15.5);
  }, note: '身份铭牌，与资料卡区分'),
  IconSpec('location', '位置', iconGroups[3], ['Menu.location'], (g) {
    g.p([
      12,
      21,
      5.5,
      11.8,
      5.5,
      7.2,
      8.8,
      3.5,
      15.2,
      3.5,
      18.5,
      7.2,
      18.5,
      11.8,
    ], close: true);
    g.node(12, 8.6, 2.6);
  }, note: '多面定位 + 星系星芒'),
  IconSpec('server', '服务器', iconGroups[3], ['Menu.server'], (g) {
    g.cut(3.5, 3.5, 20.5, 10.5, 2.4);
    g.cut(3.5, 13.5, 20.5, 20.5, 2.4);
    g.dia(7.2, 7, 1.4, filled: true);
    g.dia(7.2, 17, 1.4, filled: true);
    if (g.fine) {
      g.l(11, 7, 16.5, 7);
      g.l(11, 17, 16.5, 17);
    }
  }),
  IconSpec('desktop', '本机', iconGroups[3], ['Menu.desktop'], paintIconMonitor),
  IconSpec('host', '本机服务', iconGroups[3], ['SB.statusHost'], (g) {
    paintIconMonitor(g);
    g.node(12, 10, 2.9);
  }),
  IconSpec('network', '网络', iconGroups[3], ['SB.statusNetwork'], (g) {
    g.dia(12, 5, 2.4);
    g.dia(5.5, 18.5, 2.4);
    g.dia(18.5, 18.5, 2.4);
    g.l(12, 7.4, 12, 12);
    g.l(5.5, 12, 18.5, 12);
    g.l(5.5, 12, 5.5, 16.1);
    g.l(18.5, 12, 18.5, 16.1);
  }),
  IconSpec('crosshair', '准星', iconGroups[3], [], (g) {
    g.l(12, 3, 12, 7.2);
    g.l(12, 16.8, 12, 21);
    g.l(3, 12, 7.2, 12);
    g.l(16.8, 12, 21, 12);
    g.dia(12, 12, 3.6);
    if (g.fine) g.dot(12, 12, 0.9);
  }, note: '新增：浮层准星模块'),
  IconSpec('scene', '场景预设', iconGroups[3], ['SB.scene'], (g) {
    g.brackets();
    g.node(12, 12, 3.4);
  }),
  IconSpec('appearance', '外观', iconGroups[3], ['Std.layers'], (g) {
    g.p([12, 3.5, 20.5, 8, 12, 12.5, 3.5, 8], close: true);
    g.p([3.5, 12, 12, 16.5, 20.5, 12]);
    g.p([3.5, 16, 12, 20.5, 20.5, 16]);
  }),
  IconSpec('microphone', '麦克风', iconGroups[3], ['Menu.microphone'], (g) {
    g.p([
      10.5,
      3,
      13.5,
      3,
      15,
      4.5,
      15,
      11.5,
      13.5,
      13,
      10.5,
      13,
      9,
      11.5,
      9,
      4.5,
    ], close: true);
    g.p([6, 10, 6, 12, 8.8, 16, 15.2, 16, 18, 12, 18, 10]);
    g.l(12, 16, 12, 20.5);
    g.l(8.5, 20.5, 15.5, 20.5);
  }),
  IconSpec('headphones', '耳机', iconGroups[3], ['Menu.headphones'], (g) {
    g.p([4.5, 13.5, 4.5, 10, 8, 4.5, 16, 4.5, 19.5, 10, 19.5, 13.5]);
    g.p([3, 13.5, 7.5, 13.5, 7.5, 20.5, 4.5, 20.5, 3, 19], close: true);
    g.p([21, 13.5, 16.5, 13.5, 16.5, 20.5, 19.5, 20.5, 21, 19], close: true);
  }),
  IconSpec('camera', '截屏', iconGroups[3], ['Menu.camera'], (g) {
    g.cut(3, 7, 21, 20);
    g.p([8, 7, 9.5, 4, 14.5, 4, 16, 7]);
    g.oct(12, 13.5, 3.8);
  }),
  IconSpec('image', '图片', iconGroups[3], ['Std.image', 'Menu.image'], (g) {
    g.cut(3, 4, 21, 20);
    g.p([3, 17.5, 9, 11.5, 13, 15.5, 15.5, 13, 21, 18.5]);
    g.node(15.8, 8.4, 2.2);
  }),
  IconSpec('brokenImage', '图片失效', iconGroups[3], ['Std.brokenImage'], (g) {
    g.p([
      12.5,
      4,
      3,
      4,
      3,
      20,
      10.5,
      20,
      10.5,
      17,
      13,
      13,
      10.5,
      9,
    ], close: true);
    g.p([
      15,
      4,
      18,
      4,
      21,
      7,
      21,
      20,
      13,
      20,
      13,
      17,
      15.5,
      13,
      13,
      9,
    ], close: true);
  }),
  IconSpec('browser', '浏览器', iconGroups[3], ['Menu.browser'], (g) {
    g.cut(3, 4, 21, 20);
    g.l(3, 8.5, 21, 8.5);
    if (g.fine) {
      g.dot(6, 6.25, 0.85);
      g.dot(8.5, 6.25, 0.85);
    }
    g.node(12, 14.3, 3.0);
  }),
  IconSpec('globe', '网站 / 公开', iconGroups[3], ['Std.public', 'Std.language'], (
    g,
  ) {
    g.oct(12, 12, 9);
    g.p([
      12,
      3.7,
      15.6,
      7.6,
      15.6,
      16.4,
      12,
      20.3,
      8.4,
      16.4,
      8.4,
      7.6,
    ], close: true);
    g.l(3.7, 12, 20.3, 12);
  }),
];
