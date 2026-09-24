import 'dart:async';

import 'package:flutter/material.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import 'hangar_reader_copy.dart';
import 'local_hangar_port.dart';
import 'local_hangar_save_module.dart';

/// Inline confirmation stays with the reader and is destroyed on account change.
class LocalHangarSavePanel extends StatefulWidget {
  const LocalHangarSavePanel({
    required this.port,
    required this.view,
    required this.onSaved,
    super.key,
  });
  final LocalHangarPort port;
  final Map<String, Object?> view;
  final VoidCallback onSaved;
  @override
  State<LocalHangarSavePanel> createState() => _LocalHangarSavePanelState();
}

class _LocalHangarSavePanelState extends State<LocalHangarSavePanel> {
  late final LocalHangarSaveModule _module;
  bool _confirmed = false, _completed = false;
  @override
  void initState() {
    super.initState();
    _module = LocalHangarSaveModule(
      widget.port,
      widget.view['operationId'] as String,
      widget.view['shipCount'] as int,
    )..addListener(_changed);
    unawaited(_module.refresh());
  }

  void _changed() {
    if (_module.phase == 'saved' && !_completed) {
      _completed = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onSaved();
      });
    }
  }

  @override
  void dispose() {
    _module.removeListener(_changed);
    _module.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _module,
    builder: (context, _) {
      final c = HangarReaderCopy(context), m = _module;
      final partial = widget.view['phase'] == 'needsReview';
      final count = m.shipCount, previous = m.current?.ships.length ?? 0;
      String pick(String cn, String tw, String en) => c.pick(cn, tw, en);
      final message = switch (m.phase) {
        'loading' => pick(
          '正在读取已保存的机库…',
          '正在讀取已儲存的機庫…',
          'Reading your saved hangar…',
        ),
        'saving' => pick('正在保存…', '正在儲存…', 'Saving…'),
        'uncertain' => pick(
          '尚未确认保存结果，请查询后继续。',
          '尚未確認儲存結果，請查詢後繼續。',
          'The save result is not confirmed. Check the result before continuing.',
        ),
        'error' => _error(c, m.error),
        _ =>
          partial
              ? pick(
                  '本次识别 $count 艘。保存时会保留已有舰船，暂不同步到组织。',
                  '本次識別 $count 艘。儲存時會保留已有艦船，暫不同步到組織。',
                  '$count ships recognized. Existing ships will be kept; organization sync is paused.',
                )
              : pick(
                  '已保存 $previous 艘，本次读取 $count 艘。',
                  '已儲存 $previous 艘，本次讀取 $count 艘。',
                  '$previous ships saved; $count ships in this reading.',
                ),
      };
      return Container(
        key: const Key('local-hangar-save-panel'),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: context.tokens.surfaces.panel.fill,
          border: Border.all(color: context.tokens.surfaces.panel.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(liveRegion: true, child: Text(message)),
            if (m.busy) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: MediaQuery.disableAnimationsOf(context) ? .5 : null,
              ),
            ] else if (m.phase == 'ready')
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Checkbox(
                        key: const Key('local-hangar-confirm'),
                        value: _confirmed,
                        onChanged: (value) =>
                            setState(() => _confirmed = value ?? false),
                      ),
                      Flexible(
                        child: Text(
                          count == 0
                              ? pick(
                                  '确认清空本机机库',
                                  '確認清空本機機庫',
                                  'Confirm emptying this device’s hangar',
                                )
                              : partial
                              ? pick(
                                  '确认保留已有舰船并保存',
                                  '確認保留已有艦船並儲存',
                                  'Keep existing ships and save',
                                )
                              : pick(
                                  '确认更新本机机库',
                                  '確認更新本機機庫',
                                  'Confirm updating this device’s hangar',
                                ),
                        ),
                      ),
                    ],
                  ),
                  FilledButton(
                    key: const Key('local-hangar-save'),
                    onPressed: !_confirmed
                        ? null
                        : () => m.save(confirmEmpty: count == 0),
                    child: Text(pick('保存到本机', '儲存到本機', 'Save on this device')),
                  ),
                ],
              )
            else if (m.phase == 'error' || m.phase == 'uncertain')
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: const Key('local-hangar-save-retry'),
                  onPressed: () {
                    setState(() => _confirmed = false);
                    unawaited(m.refresh());
                  },
                  child: Text(pick('查询保存结果', '查詢儲存結果', 'Check save result')),
                ),
              ),
          ],
        ),
      );
    },
  );

  String _error(HangarReaderCopy c, String? code) => switch (code) {
    'hangar.revision_conflict' => c.pick(
      '机库已有更新，请重新核对后保存。',
      '機庫已有更新，請重新核對後儲存。',
      'Your hangar has changed. Review it again before saving.',
    ),
    'hangar.ambiguous_instances' => c.pick(
      '部分同型舰船无法对应，已保留原机库。请重新读取。',
      '部分同型艦船無法對應，已保留原機庫。請重新讀取。',
      'Some ship instances could not be matched. Your saved hangar is unchanged. Read again.',
    ),
    'hangar.operation_expired' || 'hangar.account_changed' => c.pick(
      '本次读取已失效，请重新打开机库读取。',
      '本次讀取已失效，請重新開啟機庫讀取。',
      'This reading is no longer available. Open the reader and start again.',
    ),
    _ => c.pick(
      '暂时无法读写本机机库，请重试。',
      '暫時無法讀寫本機機庫，請重試。',
      'The local hangar could not be read or saved. Try again.',
    ),
  };
}
