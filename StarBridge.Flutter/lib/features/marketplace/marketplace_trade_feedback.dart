import 'dart:ui' show SemanticsHitTestBehavior;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart' show InteractionScope;
import '../../design_system/appearance/appearance_scope.dart';
import '../../design_system/interaction/starbridge_snack_bar.dart';
import '../../design_system/interaction/starbridge_dialog.dart';

import 'marketplace_controller.dart';
import 'marketplace_states.dart' show marketTextAction;
import 'marketplace_trade_copy.dart';
import 'marketplace_trade_style.dart';
import '../../design_system/interaction/starbridge_timed_snack_bar.dart';

class TradeFailure extends StatelessWidget {
  const TradeFailure(
    this.c, {
    required this.retry,
    this.writing = false,
    super.key,
  });
  final MarketplaceController c;
  final VoidCallback retry;
  final bool writing;
  @override
  Widget build(BuildContext context) {
    final t = c.trades;
    final code = writing ? t.writeErrorCode : t.errorCode;
    final message = writing ? t.writeError : t.error;
    final login = code == 'marketplace.sign_in_required';
    final forbidden = code == 'marketplace.forbidden';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TradeNoticeBox(tradeText(context, message ?? '暂时读不到交易'), danger: true),
        if (!writing || login || forbidden || t.writeUncertain)
          Align(
            alignment: Alignment.centerLeft,
            child: marketTextAction(
              key: const Key('market-trade-failure-action'),
              onPressed: login
                  ? (c.login == null ? null : () => c.login!(context))
                  : forbidden
                  ? () async {
                      await Clipboard.setData(
                        ClipboardData(text: t.diagnostic),
                      );
                      if (context.mounted) {
                        showStarBridgeSnackBar(
                          context,
                          starBridgeTimedSnackBar(
                            content: Text(tradeText(context, '诊断信息已复制')),
                          ),
                        );
                      }
                    }
                  : retry,
              child: Text(
                tradeText(
                  context,
                  login
                      ? '登录 SCM'
                      : forbidden
                      ? '复制诊断信息'
                      : writing && t.writeUncertain
                      ? '刷新交易单'
                      : '重试',
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Trade and listing dialogs share the approved suite route (the selected
/// open/close motion; keyboard and reader closes land within two frames).
Future<T?> tradeMotionDialog<T>(BuildContext context, WidgetBuilder builder, {
  bool barrierDismissible = false,
}) =>
    _restoreTradeFocus<T>(() {
      var themes = InheritedTheme.capture(
        from: context,
        to: Navigator.of(context, rootNavigator: true).context,
      );
      return showStarBridgeDialog<T>(
        context,
        barrierDismissible: barrierDismissible,
        builder: (routeContext) {
          // Reuse the route's live relay, not a second settings listener.
          // Native captured themes otherwise pin a local suite at opening.
          InteractionScope.of(routeContext);
          // The opener may be leaving the tree while the dialog rebuilds;
          // mounted stays true until it is gone, but its render object is
          // already detached. Keep the last capture then.
          if (context.mounted &&
              ((context as Element).renderObject?.attached ?? false)) {
            themes = InheritedTheme.capture(
              from: context,
              to: Navigator.of(context, rootNavigator: true).context,
            );
          }
          return Semantics(
          scopesRoute: true,
          explicitChildNodes: true,
          hitTestBehavior: SemanticsHitTestBehavior.opaque,
          child: DisplayFeatureSubScreen(
            // 有的交易弹窗是从根浮层打开的，拿不到交易页的主题，这里统一还原。
            child: SafeArea(
              child: themes.wrap(
                HolidayColorExempt(child: Builder(builder: builder)),
              ),
            ),
          ),
          );
        },
      );
    });

Future<T?> _restoreTradeFocus<T>(Future<T?> Function() open) async {
  final trigger = FocusManager.instance.primaryFocus;
  try {
    return await open();
  } finally {
    if (trigger?.context != null && trigger!.canRequestFocus) {
      trigger.requestFocus();
    }
  }
}
