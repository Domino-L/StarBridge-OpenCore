import 'package:flutter_test/flutter_test.dart';
import 'package:starbridge_flutter/app/localization/general_settings_strings.dart';

// 读取自己的血量：三种语言都有完整说明，最后一句是风险提示（用户 11-09 要求加）。
void main() {
  const keys = [
    'settings.screenReading',
    'settings.screenReading.description',
    'settings.general.ownHealth.title',
    'settings.general.ownHealth.summary.off',
    'settings.general.ownHealth.summary.on',
    'settings.general.ownHealth.viewNotes',
    'settings.general.ownHealth.dialog.title',
    'settings.general.ownHealth.what.title',
    'settings.general.ownHealth.what',
    'settings.general.ownHealth.how.title',
    'settings.general.ownHealth.how',
    'settings.general.ownHealth.never.title',
    'settings.general.ownHealth.never',
    'settings.general.ownHealth.note.title',
    'settings.general.ownHealth.note',
    'settings.general.ownHealth.risk.title',
    'settings.general.ownHealth.risk',
    'settings.general.ownHealth.dialog.agree',
    'settings.general.ownHealth.dialog.cancel',
    'settings.general.ownHealth.dialog.confirm',
    'settings.general.ownHealth.dialog.close',
    'settings.general.ownHealth.background.title',
    'settings.general.ownHealth.background.what',
  ];

  test('every language has the full own-health copy', () {
    for (final map in [
      simplifiedGeneralSettingsStrings,
      traditionalGeneralSettingsStrings,
      englishGeneralSettingsStrings,
    ]) {
      for (final key in keys) {
        expect(map[key], isNotNull, reason: key);
        expect(map[key]!.trim(), isNotEmpty, reason: key);
      }
    }
  });

  test('the technology line names Windows graphics capture of the game window only', () {
    expect(
      simplifiedGeneralSettingsStrings['settings.general.ownHealth.how'],
      startsWith('用 Windows 图形捕获，只读游戏窗口本身的画面'),
    );
    for (final map in [
      simplifiedGeneralSettingsStrings,
      traditionalGeneralSettingsStrings,
      englishGeneralSettingsStrings,
    ]) {
      expect(map['settings.general.ownHealth.how'], isNot(contains('DXGI')));
    }
    expect(simplifiedGeneralSettingsStrings['settings.screenReading'], '屏幕读取');
  });

  test('the switch is marked experimental in every language (user 11-12)', () {
    expect(simplifiedGeneralSettingsStrings['settings.general.ownHealth.title'], '读取自己的血量（实验版）');
    expect(traditionalGeneralSettingsStrings['settings.general.ownHealth.title'], '讀取自己的血量（實驗版）');
    expect(englishGeneralSettingsStrings['settings.general.ownHealth.title'], 'Read my own health (experimental)');
  });

  // 用户 11-13：子开关"游戏在后台时也读取"默认关；主开关说明是批准过的，不改（"游戏窗口在最前面时"照样成立）。
  test('the background sub-switch has its own title and note; the main note is unchanged', () {
    expect(simplifiedGeneralSettingsStrings['settings.general.ownHealth.background.title'], '游戏在后台时也读取');
    expect(traditionalGeneralSettingsStrings['settings.general.ownHealth.background.title'], '遊戲在背景時也讀取');
    expect(
      englishGeneralSettingsStrings['settings.general.ownHealth.background.title'],
      'Also read while the game is in the background',
    );
    expect(
      simplifiedGeneralSettingsStrings['settings.general.ownHealth.background.what'],
      contains('游戏最小化后没有画面，读不到，圆环会隐藏'),
    );
    expect(
      simplifiedGeneralSettingsStrings['settings.general.ownHealth.what'],
      contains('并且游戏窗口在最前面时'),
    );
  });

  // 用户 11-13（"一起吧"）：满血时格子收起，主开关说明末尾补一句；复审第十二轮后按实际做法改写：
  // 满血只由画面读到，游戏日志只会取消它。
  test('the main note says full health is kept from the screen and the game log only drops it', () {
    expect(
      simplifiedGeneralSettingsStrings['settings.general.ownHealth.what'],
      endsWith('满血时游戏会收起血量格子，圆环继续显示满血；游戏日志显示阵亡、倒地或换服务器时取消。'),
    );
    expect(traditionalGeneralSettingsStrings['settings.general.ownHealth.what'], contains('遊戲日誌'));
    expect(englishGeneralSettingsStrings['settings.general.ownHealth.what'], contains('when the game log shows a death'));
    for (final map in [
      simplifiedGeneralSettingsStrings,
      traditionalGeneralSettingsStrings,
      englishGeneralSettingsStrings,
    ]) {
      expect(map['settings.general.ownHealth.what'], isNot(contains('补成满血')));
      expect(map['settings.general.ownHealth.what'], isNot(contains('補成滿血')));
      expect(map['settings.general.ownHealth.what'], isNot(contains('to show the ring as full')));
    }
  });

  test('the risk line says what the user decided', () {
    expect(
      simplifiedGeneralSettingsStrings['settings.general.ownHealth.risk'],
      '自动读取游戏画面可能不符合游戏的使用条款，请自行判断是否开启。',
    );
    expect(
      traditionalGeneralSettingsStrings['settings.general.ownHealth.risk'],
      contains('使用條款'),
    );
    expect(
      englishGeneralSettingsStrings['settings.general.ownHealth.risk'],
      contains('terms of use'),
    );
  });

  // 用户 11-14：打开开关先弹确认框（完整说明 + 风险说明），开关旁只留一句话；两个问题都选甲
  // （开着的人升级不补弹；每次打开都弹，没有"不再提示"）。三种语言逐句核对。
  test('the consent dialog and the short switch line in every language (user 11-14)', () {
    const zhCn = simplifiedGeneralSettingsStrings;
    const zhTw = traditionalGeneralSettingsStrings;
    const en = englishGeneralSettingsStrings;
    expect(zhCn['settings.general.ownHealth.dialog.title'], '开启“读取自己的血量（实验版）”');
    expect(zhTw['settings.general.ownHealth.dialog.title'], '開啟“讀取自己的血量（實驗版）”');
    expect(en['settings.general.ownHealth.dialog.title'], 'Turn on “Read my own health (experimental)”');
    expect(
      [for (final k in ['what', 'how', 'never', 'note', 'risk']) zhCn['settings.general.ownHealth.$k.title']],
      ['会读什么', '怎么读', '不做的事', '还要知道', '风险说明'],
    );
    expect(
      [for (final k in ['what', 'how', 'never', 'note', 'risk']) zhTw['settings.general.ownHealth.$k.title']],
      ['會讀什麼', '怎麼讀', '不做的事', '還要知道', '風險說明'],
    );
    expect(
      [for (final k in ['what', 'how', 'never', 'note', 'risk']) en['settings.general.ownHealth.$k.title']],
      ['What it reads', 'How it reads', 'What it never does', 'Also good to know', 'Risk'],
    );
    expect(zhCn['settings.general.ownHealth.dialog.agree'], '点“同意并开启”，表示你已经看过上面的说明，了解可能的风险，自己决定开启。');
    expect(zhTw['settings.general.ownHealth.dialog.agree'], '點“同意並開啟”，表示你已經看過上面的說明，了解可能的風險，自己決定開啟。');
    expect(en['settings.general.ownHealth.dialog.agree'], startsWith('By choosing “Agree and turn on”'));
    expect(
      [zhCn, zhTw, en].map((m) => m['settings.general.ownHealth.dialog.confirm']),
      ['同意并开启', '同意並開啟', 'Agree and turn on'],
    );
    expect(
      [zhCn, zhTw, en].map((m) => m['settings.general.ownHealth.dialog.cancel']),
      ['取消', '取消', 'Cancel'],
    );
    expect(
      [zhCn, zhTw, en].map((m) => m['settings.general.ownHealth.viewNotes']),
      ['查看说明', '查看說明', 'View notes'],
    );
    expect(zhCn['settings.general.ownHealth.summary.off'], '读取画面左下角自己的血量，显示在面罩里。开启前需要阅读并同意风险说明。');
    // 复审 P2、用户 11-14 选甲：开着时只说当前状态，不说"你已同意"（开着不能证明点过确认框）。
    expect(zhCn['settings.general.ownHealth.summary.on'], '正在读取画面左下角自己的血量，显示在面罩里。关掉开关会立刻停止读取。');
    expect(zhTw['settings.general.ownHealth.summary.off'], endsWith('開啟前需要閱讀並同意風險說明。'));
    expect(zhTw['settings.general.ownHealth.summary.on'], '正在讀取畫面左下角自己的血量，顯示在面罩裡。關掉開關會立刻停止讀取。');
    expect(en['settings.general.ownHealth.summary.off'], endsWith('you need to read and agree to the risk notes.'));
    expect(en['settings.general.ownHealth.summary.on'], 'Reading your own health from the bottom left of the screen and showing it in the visor. Turning it off stops reading immediately.');
    for (final map in [zhCn, zhTw, en]) {
      expect(map['settings.general.ownHealth.summary.on'], isNot(anyOf(contains('已同意'), contains('agreed'))));
    }
    // 整理时只改了笔记里列的几处；"默认关闭"和"没打开时不显示圆环"仍在说明里，"显卡上裁切"去掉了。
    expect(zhCn['settings.general.ownHealth.note'], contains('默认关闭，没打开时面罩里不显示你的血量圆环'));
    expect(zhTw['settings.general.ownHealth.note'], contains('預設關閉，沒打開時面罩裡不顯示你的血量圓環'));
    expect(en['settings.general.ownHealth.note'], contains('It is off by default'));
    for (final map in [zhCn, zhTw, en]) {
      expect(map['settings.general.ownHealth.how'], isNot(contains('CPU')));
      expect(map.keys.where((k) => k.contains('dontAsk') || k.contains('remember')), isEmpty);
    }
    expect(zhCn['settings.general.ownHealth.how'], contains('在这台电脑上识别'));
    expect(zhTw['settings.general.ownHealth.how'], contains('在這台電腦上辨識'));
    expect(en['settings.general.ownHealth.how'], contains('reads it on this computer'));
  });
}
