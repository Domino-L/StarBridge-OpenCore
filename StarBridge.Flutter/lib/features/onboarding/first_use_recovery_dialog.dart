import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/interaction/starbridge_dialog.dart';

import 'package:starbridge_interaction/starbridge_interaction.dart'
    show InteractionSource;

import 'package:flutter/material.dart';

import '../../app/runtime/first_use_recovery_flow.dart';

Future<FirstUseRecoveryChoice?> showFirstUseRecovery(
  BuildContext context,
  FirstUseRecoveryNotice notice,
) => showStarBridgeDialog<FirstUseRecoveryChoice>(
  context,
  source: StarBridgeActivationOrigin.sourceOf(context),
  barrierDismissible: false,
  builder: (_) => _RecoveryDialog(notice),
);

class _RecoveryDialog extends StatefulWidget {
  const _RecoveryDialog(this.notice);
  final FirstUseRecoveryNotice notice;
  @override
  State<_RecoveryDialog> createState() => _RecoveryDialogState();
}

class _RecoveryDialogState extends State<_RecoveryDialog> {
  void _finish(FirstUseRecoveryChoice result, InteractionSource source) {
    final route = ModalRoute.of(context);
    if (route == null || !route.isActive) return;
    if (!route.isCurrent) {
      // A completed read must never dismiss a newer manual draft above us.
      route.navigator?.removeRoute(route, result);
      return;
    }
    dismissStarBridgeDialog(context, source: source, result: result);
  }

  @override
  void initState() {
    super.initState();
    widget.notice.addListener(_changed);
  }

  void _changed() {
    if (!mounted) return;
    if (!widget.notice.active) {
      final route = ModalRoute.of(context);
      if (route != null && route.isActive) {
        Navigator.of(context).removeRoute(route);
      }
    } else {
      setState(() {});
    }
  }

  @override
  void dispose() {
    widget.notice.removeListener(_changed);
    super.dispose();
  }

  String _text(String key) {
    final locale = Localizations.localeOf(context);
    final index = locale.languageCode == 'en'
        ? 2
        : locale.scriptCode == 'Hant' ||
              const {'TW', 'HK', 'MO'}.contains(locale.countryCode)
        ? 1
        : 0;
    return _words[key]![index];
  }

  static const _words = <String, List<String>>{
    'title': ['当前设置需要确认', '目前設定需要確認', 'Check the current setup'],
    'unreadableHistory': [
      '暂时无法读取使用记录。',
      '暫時無法讀取使用記錄。',
      'Previous use could not be checked.',
    ],
    'unreadableProgress': [
      '暂时无法读取设置进度。',
      '暫時無法讀取設定進度。',
      'Setup progress could not be read.',
    ],
    'installationUnknown': [
      '暂时无法确认安装来源。',
      '暫時無法確認安裝來源。',
      'The installation source is not confirmed.',
    ],
    'unavailable': [
      '暂时无法确认当前记录或模式。',
      '暫時無法確認目前記錄或模式。',
      'The current records or mode are not confirmed.',
    ],
    'pending': [
      '之前的模式切换尚未确认完成。',
      '先前的模式切換尚未確認完成。',
      'A previous mode change is not confirmed complete.',
    ],
    'switching': [
      '模式切换仍在进行，请稍后重新检查。',
      '模式切換仍在進行，請稍後重新檢查。',
      'The mode change is still running. Check again later.',
    ],
    'body': [
      '原记录会保留，不会将未知记录当成空设置。你可以返回使用当前可用的本机功能，稍后再检查；在线功能仍以原模式和身份检查为准。',
      '原記錄會保留，不會將未知記錄當成空設定。你可以返回使用目前可用的本機功能，稍後再檢查；線上功能仍以原模式與身分檢查為準。',
      'Original records are kept; unknown records are not treated as empty settings. You can return to the local features currently available and check again later. Online features still require the original mode and identity checks.',
    ],
    'keep': ['保留记录并返回', '保留記錄並返回', 'Keep records and return'],
    'retry': ['重新检查', '重新檢查', 'Check again'],
    'open': ['打开设置引导', '開啟設定引導', 'Open setup'],
  };
  @override
  Widget build(BuildContext context) => AlertDialog(
    key: const Key('first-use-recovery-dialog'),
    title: Text(_text('title')),
    content: SingleChildScrollView(
      child: Text('${_text(widget.notice.reason)}\n\n${_text('body')}'),
    ),
    actions: [
      StarBridgeActionButton(
        controlKey: const Key('first-use-recovery-keep'),
        kind: StarBridgeActionKind.quiet,
        onActivate: widget.notice.busy || !widget.notice.active
            ? null
            : (source) => _finish(FirstUseRecoveryChoice.keepCurrent, source),
        child: Text(_text('keep')),
      ),
      StarBridgeActionButton(
        controlKey: const Key('first-use-recovery-recheck'),
        kind: StarBridgeActionKind.secondary,
        onActivate: widget.notice.busy || !widget.notice.active
            ? null
            : (source) async {
                final healthy = await widget.notice.recheck();
                if (!mounted || !healthy || !widget.notice.active) return;
                _finish(FirstUseRecoveryChoice.keepCurrent, source);
              },
        child: Text(_text('retry')),
      ),
      StarBridgeActionButton(
        controlKey: const Key('first-use-recovery-open'),
        kind: StarBridgeActionKind.primary,
        onActivate: widget.notice.busy || !widget.notice.active
            ? null
            : (source) => _finish(FirstUseRecoveryChoice.openSetup, source),
        child: Text(_text('open')),
      ),
    ],
  );
}
