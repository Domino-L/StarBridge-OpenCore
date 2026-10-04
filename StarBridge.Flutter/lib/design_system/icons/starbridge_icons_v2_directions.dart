import 'starbridge_icons_v2_spec.dart';

final List<IconSpec> directionsIconsV2 = [
  // 方向与窗口 -------------------------------------------------------------
  IconSpec('chevronRight', '前进', iconGroups[7], [
    'SB.forward',
    'Std.chevronRight',
    'Menu.next',
  ], (g) => g.p([9, 5, 16, 12, 9, 19])),
  IconSpec('chevronLeft', '后退', iconGroups[7], [
    'Std.chevronLeft',
  ], (g) => g.p([15, 5, 8, 12, 15, 19])),
  IconSpec('chevronDown', '展开', iconGroups[7], [
    'SB.menuDown',
    'Std.expandMore',
    'Menu.down',
  ], (g) => g.p([5, 9, 12, 16, 19, 9])),
  IconSpec('chevronUp', '收起', iconGroups[7], [
    'Std.expandLess',
  ], (g) => g.p([5, 15, 12, 8, 19, 15])),
  IconSpec('arrowForward', '向前', iconGroups[7], [
    'Std.arrowForward',
  ], (g) => g.arrow(3.5, 12, 20.5, 12)),
  IconSpec('arrowBack', '返回', iconGroups[7], [
    'Std.arrowBack',
  ], (g) => g.arrow(20.5, 12, 3.5, 12)),
  IconSpec('arrowUp', '升序', iconGroups[7], [
    'Std.north',
  ], (g) => g.arrow(12, 20.5, 12, 3.5)),
  IconSpec('arrowDown', '降序', iconGroups[7], [
    'Std.south',
  ], (g) => g.arrow(12, 3.5, 12, 20.5)),
  IconSpec('jumpLatest', '跳到最新', iconGroups[7], ['Std.arrowDownward'], (g) {
    g.arrow(12, 3.5, 12, 16.5);
    g.l(5, 20.5, 19, 20.5);
  }),
  IconSpec('unfoldMore', '展开全部', iconGroups[7], ['Std.unfoldMore'], (g) {
    g.p([7, 9, 12, 4.5, 17, 9]);
    g.p([7, 15, 12, 19.5, 17, 15]);
  }),
  IconSpec('unfoldLess', '收起全部', iconGroups[7], ['Std.unfoldLess'], (g) {
    g.p([7, 4.5, 12, 9, 17, 4.5]);
    g.p([7, 19.5, 12, 15, 17, 19.5]);
  }),
  IconSpec(
    'close',
    '关闭',
    iconGroups[7],
    ['SB.windowClose', 'Std.close', 'Menu.close', 'Window.close'],
    (g) {
      g.l(5.5, 5.5, 18.5, 18.5);
      g.l(18.5, 5.5, 5.5, 18.5);
    },
  ),
  IconSpec('minimize', '最小化', iconGroups[7], [
    'SB.windowMinimize',
    'Window.minimize',
  ], (g) => g.l(6, 12.5, 18, 12.5)),
  IconSpec('maximize', '最大化', iconGroups[7], [
    'SB.windowMaximize',
    'Window.maximize',
  ], (g) => g.rect(6, 6, 18, 18)),
  IconSpec(
    'restore',
    '还原',
    iconGroups[7],
    ['SB.windowRestore', 'Window.restore'],
    (g) {
      g.rect(5.5, 8.5, 15.5, 18.5);
      g.p([8.5, 8.5, 8.5, 5.5, 18.5, 5.5, 18.5, 15.5, 15.5, 15.5]);
    },
  ),
];
