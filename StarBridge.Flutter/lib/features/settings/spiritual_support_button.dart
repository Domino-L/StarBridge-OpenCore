import 'dart:async';

import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../design_system/interaction/starbridge_interaction_theme.dart';
import 'daily_support_port.dart';
import 'help_support_action.dart';

/// Gratitude is not an entitlement receipt. Do not claim a trial until an
/// account-authoritative grant operation and readback are connected.
class SpiritualSupportButton extends StatelessWidget {
  const SpiritualSupportButton({this.port, super.key});
  final DailySupportPort? port;

  @override
  Widget build(BuildContext context) {
    final locale = AppStrings.of(context).locale;
    final language = locale.languageCode == 'en'
        ? 2
        : locale.countryCode == 'TW' || locale.scriptCode == 'Hant'
        ? 1
        : 0;
    String copy(List<String> values) => values[language];
    return HelpSupportAction(
      kind: StarBridgeActionKind.secondary,
      controlKey: const Key('help-spiritual-support'),
      onActivate: (source) => port != null
          ? showStarBridgeDialog<void>(
              context,
              source: source,
              builder: (dialogContext) => _liveRoute(
                dialogContext,
                _DailySupportDialog(port: port!, language: language),
              ),
            )
          : showStarBridgeDialog<void>(
              context,
              source: source,
              builder: (dialogContext) => _liveRoute(
                dialogContext,
                AlertDialog(
                  scrollable: true,
                  title: Text(copy(['精神赞助', '精神贊助', 'Moral support'])),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        copy([
                          '我们已经收到你的精神赞助，谢谢你！',
                          '我們已經收到你的精神贊助，謝謝你！',
                          'Your moral support means a lot. Thank you!',
                        ]),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        copy([
                          '无需付款，也不会打开支付页面。',
                          '無需付款，也不會開啟付款頁面。',
                          'No payment is needed, and no payment page will open.',
                        ]),
                      ),
                    ],
                  ),
                  actions: [
                    HelpSupportAction(
                      controlKey: const Key('help-support-local-close'),
                      onActivate: (source) => dismissStarBridgeDialog(
                        dialogContext,
                        source: source,
                      ),
                      child: Text(copy(['关闭', '關閉', 'Close'])),
                    ),
                  ],
                ),
              ),
            ),
      child: Text(copy(['赞助', '贊助', 'Support'])),
    );
  }
}

Widget _liveRoute(BuildContext context, Widget child) {
  final live = InteractionScope.of(context);
  return StarBridgeInteractionConfiguration(
    suite: live.suite,
    reduceMotion: live.reduceMotion,
    child: child,
  );
}

class _DailySupportDialog extends StatefulWidget {
  const _DailySupportDialog({required this.port, required this.language});
  final DailySupportPort port;
  final int language;
  @override
  State<_DailySupportDialog> createState() => _DailySupportDialogState();
}

class _DailySupportDialogState extends State<_DailySupportDialog> {
  bool busy = false, started = false, failed = false;
  bool accountChanged = false;
  int revision = 0;
  StreamSubscription<void>? subscription;
  DailySupportResult? result;
  String copy(List<String> values) => values[widget.language];

  @override
  void initState() {
    super.initState();
    subscription = widget.port.invalidations.listen((_) {
      if (!mounted) return;
      setState(() {
        revision++;
        result = null;
        busy = false;
        failed = false;
        started = true;
        accountChanged = true;
      });
    });
  }

  @override
  void dispose() {
    revision++;
    subscription?.cancel();
    super.dispose();
  }

  Future<void> run({bool readOnly = false}) async {
    if (busy) return;
    final current = revision;
    setState(() {
      busy = true;
      started = true;
      failed = false;
    });
    try {
      final value = await (readOnly ? widget.port.read() : widget.port.claim());
      if (mounted && revision == current) setState(() => result = value);
    } catch (_) {
      if (mounted && revision == current) setState(() => failed = true);
    } finally {
      if (mounted && revision == current) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final receipt = result;
    final String message;
    if (accountChanged) {
      message = copy([
        '账号状态已变化，请关闭后重新打开。',
        '帳號狀態已變化，請關閉後重新開啟。',
        'Your account changed. Close and reopen this dialog.',
      ]);
    } else if (busy) {
      message = copy([
        '正在确认今天的赞助与礼物…',
        '正在確認今天的贊助與禮物…',
        'Checking today’s support and gift…',
      ]);
    } else if (failed) {
      message = copy([
        '暂时无法确认领取结果。请先查询结果，避免重复操作。',
        '暫時無法確認領取結果。請先查詢結果，避免重複操作。',
        'The result could not be confirmed. Check the result before trying again.',
      ]);
    } else if (receipt?.outcome == 'granted') {
      message = copy([
        '感谢你在精神上的赞助，你的支持我们已经收到了，这是一些小礼物，记得每天回来领！',
        '感謝你在精神上的贊助，你的支持我們已經收到了，這是一些小禮物，記得每天回來領！',
        'Thank you for your moral support! We’ve received your support. Here’s a small gift—remember to come back every day!',
      ]);
    } else if (receipt?.outcome == 'alreadyClaimed') {
      message = copy([
        '今天已经收到你的支持啦，明天再来！本次不会重复发放礼物或邮件。',
        '今天已經收到你的支持啦，明天再來！本次不會重複發放禮物或郵件。',
        'We already received today’s support. Come back tomorrow! No duplicate gift or email will be sent.',
      ]);
    } else if (receipt?.outcome == 'thanked') {
      message = copy([
        '感谢你在精神上的赞助，你的支持我们已经收到了！当前没有符合条件的体验外观，今天未发放礼物。',
        '感謝你在精神上的贊助，你的支持我們已經收到了！目前沒有符合條件的體驗外觀，今天未發放禮物。',
        'Thank you for your support! No eligible appearance is available, so no gift was issued today.',
      ]);
    } else if (receipt != null) {
      message = receipt.localDay == null
          ? copy(['尚未查到领取记录。', '尚未查到領取記錄。', 'No claim receipt was found.'])
          : copy([
              '已查到领取记录：${receipt.localDay}',
              '已查到領取記錄：${receipt.localDay}',
              'Claim receipt found: ${receipt.localDay}',
            ]);
    } else {
      message = copy([
        '无需付款。按本地日期每天可领取一次，随机获得一个未拥有、未在体验中的正式外观，体验持续24小时。',
        '無需付款。按本地日期每天可領取一次，隨機獲得一個未擁有、未在體驗中的正式外觀，體驗持續24小時。',
        'No payment. Once per local day, receive a random released appearance you do not own or currently trial, for 24 hours.',
      ]);
    }
    return AlertDialog(
      scrollable: true,
      title: Text(copy(['精神赞助', '精神贊助', 'Moral support'])),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message),
          if (!started) ...[
            const SizedBox(height: 12),
            Text(
              copy([
                '确认后会向开发者发送一封含你用户名字的通知邮件，每个账号每天最多一封。',
                '確認後會向開發者寄送一封含你使用者名字的通知郵件，每個帳號每天最多一封。',
                'Confirming sends the developer a notification containing your username, at most once per account per day.',
              ]),
            ),
          ],
          if (receipt?.entitlement != null) ...[
            const SizedBox(height: 12),
            Text(
              receipt!.entitlement == 'overlay.skin.night-shadow'
                  ? copy([
                      '夜影 · 24小时体验',
                      '夜影 · 24小時體驗',
                      'Night Shadow · 24-hour trial',
                    ])
                  : receipt.entitlement!,
            ),
            Text(
              copy(['到期时间：', '到期時間：', 'Expires: ']) +
                  receipt.expiresAt!.toLocal().toString(),
            ),
          ],
        ],
      ),
      actions: [
        if (!started)
          HelpSupportAction(
            controlKey: const Key('help-support-claim'),
            onActivate: (_) => run(),
            child: Text(copy(['赞助并领取', '贊助並領取', 'Support and claim'])),
          ),
        if (failed)
          HelpSupportAction(
            controlKey: const Key('help-support-read-result'),
            onActivate: (_) => run(readOnly: true),
            child: Text(copy(['查询领取结果', '查詢領取結果', 'Check result'])),
          ),
        HelpSupportAction(
          controlKey: const Key('help-support-close'),
          onActivate: (source) =>
              dismissStarBridgeDialog(context, source: source),
          child: Text(copy(['关闭', '關閉', 'Close'])),
        ),
      ],
    );
  }
}
