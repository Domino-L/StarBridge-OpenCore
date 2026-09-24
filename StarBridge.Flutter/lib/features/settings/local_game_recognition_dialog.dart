import 'package:flutter/material.dart';

import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../game_log/game_log_controller.dart';
import '../game_log/game_session_overview.dart';

/// Uses the existing account-scoped reader; opening this does not create an owner,
/// start another log watcher, change consent, or publish game presence.
Future<void> showLocalGameRecognitionDialog(
  BuildContext context,
  GameLogController? controller,
) => showDialog<void>(
  context: context,
  builder: (_) => LocalGameRecognitionDialog(controller: controller),
);

class LocalGameRecognitionDialog extends StatelessWidget {
  const LocalGameRecognitionDialog({required this.controller, super.key});
  final GameLogController? controller;

  @override
  Widget build(BuildContext context) {
    final source = controller;
    return source == null
        ? _body(context, const GameLogView(error: 'unsupported'))
        : ValueListenableBuilder<GameLogView>(
            valueListenable: source,
            builder: (context, value, _) => _body(context, value),
          );
  }

  Widget _body(BuildContext context, GameLogView value) {
    final copy = _Copy(Localizations.localeOf(context));
    final tokens = context.tokens;
    final unsupported = controller == null || value.error == 'unsupported';
    return Dialog(
      key: const Key('settings-entry-local-game-recognition'),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: StarBridgeSurface(
        role: SurfaceRole.floating,
        child: SizedBox(
          width: 760,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Flexible(
                child: SingleChildScrollView(
                  child: unsupported || !value.visible
                      ? Padding(
                          padding: EdgeInsets.all(tokens.space.sm),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                copy.title,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              SizedBox(height: tokens.space.sm),
                              Text(
                                unsupported ? copy.unavailable : copy.signIn,
                                key: const Key(
                                  'local-game-recognition-unavailable',
                                ),
                              ),
                            ],
                          ),
                        )
                      : GameSessionOverview(controller: controller),
                ),
              ),
              SizedBox(height: tokens.space.sm),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: tokens.space.sm,
                children: [
                  OutlinedButton(
                    key: const Key('local-game-recognition-refresh'),
                    onPressed: unsupported || !value.visible || value.busy
                        ? null
                        : () => controller!.run(),
                    child: Text(copy.refresh),
                  ),
                  TextButton(
                    key: const Key('settings-entry-close'),
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(copy.close),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Copy {
  _Copy(Locale locale)
    : english = locale.languageCode == 'en',
      traditional = locale.countryCode == 'TW' || locale.scriptCode == 'Hant';
  final bool english;
  final bool traditional;
  String get title => english
      ? 'Game recognition'
      : traditional
      ? '遊戲識別'
      : '游戏识别';
  String get unavailable => english
      ? 'Game recognition is temporarily unavailable.'
      : traditional
      ? '暫時無法讀取遊戲識別資訊。'
      : '暂时无法读取游戏识别信息。';
  String get signIn => english
      ? 'Check your sign-in status in Account and identity.'
      : traditional
      ? '請先在「帳號與識別」中確認登入狀態。'
      : '请先在“账号与识别”中确认登录状态。';
  String get refresh => english
      ? 'Refresh'
      : traditional
      ? '重新整理'
      : '刷新';
  String get close => english
      ? 'Close'
      : traditional
      ? '關閉'
      : '关闭';
}
