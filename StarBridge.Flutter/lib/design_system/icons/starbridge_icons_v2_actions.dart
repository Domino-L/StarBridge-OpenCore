import 'starbridge_icons_v2_pen.dart';
import 'starbridge_icons_v2_spec.dart';

final List<IconSpec> actionsIconsV2 = [
  // 操作 -------------------------------------------------------------------
  IconSpec('edit', '编辑', iconGroups[5], ['SB.edit', 'Std.edit'], (g) {
    g.rot(135, () {
      g.p([3.5, 9, 16, 9, 21.5, 12, 16, 15, 3.5, 15], close: true);
      if (g.fine) g.l(7.5, 9, 7.5, 15);
    });
  }),
  IconSpec('add', '添加', iconGroups[5], ['SB.add', 'Std.add', 'Menu.add'], (g) {
    g.l(12, 4, 12, 20);
    g.l(4, 12, 20, 12);
  }),
  IconSpec('remove', '移除', iconGroups[5], ['SB.remove'], (g) {
    g.oct(12, 12, 9);
    g.l(7.5, 12, 16.5, 12);
  }),
  IconSpec('delete', '删除', iconGroups[5], ['Std.delete'], (g) {
    paintIconBin(g);
    g.l(10, 10, 10, 17);
    g.l(14, 10, 14, 17);
  }),
  IconSpec('deleteForever', '永久删除', iconGroups[5], ['Std.deleteForever'], (g) {
    paintIconBin(g);
    g.l(9.5, 10.5, 14.5, 16.5);
    g.l(14.5, 10.5, 9.5, 16.5);
  }),
  IconSpec('search', '搜索', iconGroups[5], ['Std.search', 'Menu.search'], (g) {
    g.oct(10.5, 10.5, 6.6);
    g.l(15.4, 15.4, 20.5, 20.5);
  }),
  IconSpec(
    'refresh',
    '刷新',
    iconGroups[5],
    ['SB.refresh', 'Std.refresh', 'Menu.refresh'],
    (g) {
      g.arcArrow(12, 12, 7.6, -40, 300, len: 5, width: 6);
    },
  ),
  IconSpec('undo', '撤销', iconGroups[5], ['SB.undo'], (g) {
    g.arcArrow(12, 13, 7, 20, -200);
  }),
  IconSpec('redo', '重做', iconGroups[5], ['SB.redo'], (g) {
    g.arcArrow(12, 13, 7, 160, 200);
  }),
  IconSpec('login', '登录', iconGroups[5], ['SB.login'], (g) {
    g.p([13, 3.5, 17.5, 3.5, 20.5, 6.5, 20.5, 20.5, 13, 20.5]);
    g.arrow(3, 12, 15.5, 12);
  }),
  IconSpec('logout', '退出登录', iconGroups[5], ['SB.logout', 'Std.logout'], (g) {
    g.p([11, 3.5, 3.5, 3.5, 3.5, 20.5, 11, 20.5]);
    g.arrow(8.5, 12, 21, 12);
  }),
  IconSpec('adjust', '调整', iconGroups[5], [], (g) {
    void slider(double y, double x) {
      const k = 2.6;
      g.l(3.5, y, x - k - 0.6, y);
      g.l(x + k + 0.6, y, 20.5, y);
      g.dia(x, y, k);
    }

    if (g.fine) {
      slider(5.5, 15);
      slider(12, 8.5);
      slider(18.5, 13.5);
    } else {
      slider(7, 14.5);
      slider(17, 9);
    }
  }, note: '新增：显示设置 / 筛选'),
  IconSpec('dragHandle', '拖动', iconGroups[5], ['SB.dragHandle'], (g) {
    for (final y in [6.0, 12.0, 18.0]) {
      g.dia(9, y, 1.7, filled: true);
      g.dia(15, y, 1.7, filled: true);
    }
  }),
  IconSpec('resize', '调整大小', iconGroups[5], ['SB.resize'], (g) {
    g.arrow(12, 12, 4, 20);
    g.arrow(12, 12, 20, 4);
  }),
  IconSpec('moreHoriz', '更多', iconGroups[5], ['Std.moreHoriz'], (g) {
    for (final x in [5.5, 12.0, 18.5]) {
      g.dia(x, 12, 2.0, filled: true);
    }
  }),
];
