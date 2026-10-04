import 'starbridge_icons_v2_pen.dart';
import 'starbridge_icons_v2_spec.dart';

final List<IconSpec> dataIconsV2 = [
  // 时间与数据 -------------------------------------------------------------
  IconSpec('schedule', '可用时间', iconGroups[4], ['SB.schedule'], (g) {
    paintIconCalendar(g);
    if (g.fine) {
      for (final (x, y) in [
        (8.0, 14.0),
        (12.0, 14.0),
        (16.0, 14.0),
        (8.0, 17.5),
        (12.0, 17.5),
      ]) {
        g.dia(x, y, 1.1, filled: true);
      }
    } else {
      g.l(7.5, 15, 16.5, 15);
    }
  }),
  IconSpec('event', '事件', iconGroups[4], ['Std.event'], (g) {
    paintIconCalendar(g);
    g.node(13.5, 15.5, 3.0);
  }),
  IconSpec('clock', '时间', iconGroups[4], ['Std.schedule'], (g) {
    g.oct(12, 12, 9);
    g.l(12, 12, 12, 7);
    g.l(12, 12, 15.5, 14);
  }),
  IconSpec('playtime', '游戏时长', iconGroups[4], ['SB.playtime'], (g) {
    g.oct(12, 13.5, 7.6);
    g.l(10, 3, 14, 3);
    g.l(12, 3, 12, 5.9);
    g.l(12, 13.5, 14.8, 9.2);
    if (g.fine) g.l(18.2, 6.3, 19.6, 4.9);
  }, note: '秒表，指针沿航向角'),
  IconSpec('history', '历史记录', iconGroups[4], ['Std.history'], (g) {
    g.arcArrow(12, 12, 8.4, 150, -300);
    g.l(12, 12, 12, 7.6);
    g.l(12, 12, 15, 14);
  }),
  IconSpec('activity', '活跃度', iconGroups[4], ['SB.activity'], (g) {
    g.p([3.5, 3.5, 3.5, 20.5, 20.5, 20.5]);
    g.p([7, 16, 10.5, 11.5, 14, 14.5, 18.5, 8]);
    if (g.fine) g.spark(19, 7.2, 2.4);
  }),
  IconSpec('generalData', '通用数据', iconGroups[4], ['SB.generalData'], (g) {
    g.p([5, 3, 14.5, 3, 19, 7.5, 19, 21, 5, 21], close: true);
    if (g.fine) g.p([14.5, 3, 14.5, 7.5, 19, 7.5]);
    g.l(8.5, 11.5, 15.5, 11.5);
    g.l(8.5, 15, 15.5, 15);
    if (g.fine) g.l(8.5, 18.5, 12.5, 18.5);
  }, note: '文档折角 = 切角'),
  IconSpec('cache', '缓存', iconGroups[4], ['SB.cache'], (g) {
    g.p([4, 6, 8, 4, 16, 4, 20, 6, 16, 8, 8, 8], close: true);
    g.l(4, 6, 4, 18);
    g.l(20, 6, 20, 18);
    g.p([4, 18, 8, 20, 16, 20, 20, 18]);
    g.p([4, 12, 8, 14, 16, 14, 20, 12]);
  }, note: '多面数据鼓'),
  IconSpec('save', '保存', iconGroups[4], ['SB.save'], (g) {
    g.p([3.5, 3.5, 16.5, 3.5, 20.5, 7.5, 20.5, 20.5, 3.5, 20.5], close: true);
    g.p([7.5, 3.5, 7.5, 8.5, 15, 8.5, 15, 3.5]);
    if (g.fine) g.rect(7, 13.5, 17, 20.5);
  }),
  IconSpec('diagnostics', '诊断', iconGroups[4], ['SB.diagnostics'], (g) {
    g.oct(12, 12, 9);
    g.p([5.5, 12.5, 8.5, 12.5, 10, 8.5, 13, 16, 14.5, 12.5, 18.5, 12.5]);
  }),
  IconSpec('legal', '法律声明', iconGroups[4], ['SB.legalNotice'], (g) {
    g.l(12, 4, 12, 20);
    g.l(4.5, 7, 19.5, 7);
    g.l(8, 20, 16, 20);
    for (final x in [4.5, 19.5]) {
      g.l(x, 7, x - 1.8, 13.5);
      g.l(x, 7, x + 1.8, 13.5);
      g.p([
        x - 2.2,
        13.5,
        x + 2.2,
        13.5,
        x + 1.2,
        15.6,
        x - 1.2,
        15.6,
      ], close: true);
    }
  }, note: '天平'),
];
