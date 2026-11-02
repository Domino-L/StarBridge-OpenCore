import 'dart:async';

import 'package:flutter/material.dart';

import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/interaction/starbridge_checkbox_tile.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../design_system/interaction/starbridge_interaction_theme.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'hangar_reader_copy.dart';
import 'hangar_reader_waiting.dart';
import 'local_hangar_port.dart';
import 'local_hangar_save_module.dart';
import 'local_hangar_removal_dialog.dart';

/// Inline confirmation stays with the reader and is destroyed on account change.
class LocalHangarSavePanel extends StatefulWidget {
  const LocalHangarSavePanel({
    required this.port,
    required this.view,
    required this.onSaved,
    this.initialSource = InteractionSource.programmatic,
    super.key,
  });
  final LocalHangarPort port;
  final Map<String, Object?> view;
  final VoidCallback onSaved;
  final InteractionSource initialSource;
  @override
  State<LocalHangarSavePanel> createState() => _LocalHangarSavePanelState();
}

class _LocalHangarSavePanelState extends State<LocalHangarSavePanel> {
  late final LocalHangarSaveModule _module;
  bool _confirmed = false, _completed = false;
  StarBridgeDialogRoute<Set<String>>? _reviewRoute;
  late InteractionSource _waitSource = widget.initialSource;
  int _waitPhase = 0;
  bool _inheritOpeningSource = true;

  void _waitFrom(InteractionSource source) {
    _waitSource = source;
    _inheritOpeningSource = false;
    ++_waitPhase;
  }

  Future<void> _reviewRemovals() async {
    if (_reviewRoute != null) return;
    final m = _module;
    final choices = await showStarBridgeDialog<Set<String>>(
      context,
      source: currentStarBridgeActivationSource,
      traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
      onRouteCreated: (route) {
        _reviewRoute = route;
        unawaited(
          route.completed.then((_) {
            if (identical(_reviewRoute, route)) _reviewRoute = null;
          }),
        );
      },
      builder: (_) => LocalHangarRemovalDialog(
        snapshot: m.current!,
        groups: m.removals,
        port: widget.port,
        selected: m.selected,
      ),
    );
    if (!mounted) return;
    if (choices == null) return;
    setState(() => _confirmed = false);
    m.replaceSelection(choices);
  }

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
        if (mounted) {
          runStarBridgeSynchronousActivation<void>(_waitSource, widget.onSaved);
        }
      });
    }
  }

  @override
  void dispose() {
    final route = _reviewRoute;
    _reviewRoute = null;
    // Retain ownership through reverse too; never pop an unrelated top route.
    retireStarBridgeDialog(route, includeClosing: true);
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
      final confirmation = count == 0
          ? pick(
              '确认清空本机机库',
              '確認清空本機機庫',
              'Confirm emptying this device’s hangar',
            )
          : partial
          ? pick('确认保留已有舰船并保存', '確認保留已有艦船並儲存', 'Keep existing ships and save')
          : pick(
              '确认更新本机机库',
              '確認更新本機機庫',
              'Confirm updating this device’s hangar',
            );
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
            if (m.phase == 'ready' && !partial)
              Text(
                pick(
                  '若已明确选择共享组织，保存后会同步到这些组织；不会自动开启共享或更改共享范围。',
                  '若已明確選擇共享組織，儲存後會同步至這些組織；不會自動開啟共享或變更共享範圍。',
                  'If you have explicitly selected sharing organizations, saving also syncs to them. It does not enable sharing or change its audience.',
                ),
              ),
            if (m.phase == 'ready' && m.removals.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                pick(
                  '有 ${m.removals.length} 组同礼包重复舰船数量减少，请先选择哪些本机记录移入“曾拥有”。',
                  '有 ${m.removals.length} 組同禮包重複艦船數量減少，請先選擇哪些本機記錄移入「曾擁有」。',
                  '${m.removals.length} duplicate groups have fewer ships. Choose which local records to move to Previously owned.',
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: StarBridgeActionButton(
                  controlKey: const Key('local-hangar-review-removals'),
                  onActivate: (source) => unawaited(
                    runStarBridgeActivation<void>(source, _reviewRemovals),
                  ),
                  child: Text(
                    m.canSave
                        ? pick(
                            '已选择 ${m.selected.length} 艘 · 重新核对',
                            '已選擇 ${m.selected.length} 艘 · 重新核對',
                            '${m.selected.length} chosen · Review choices',
                          )
                        : pick(
                            '选择已不在的舰船',
                            '選擇已不在的艦船',
                            'Choose ships that left',
                          ),
                  ),
                ),
              ),
            ],
            if (m.busy) ...[
              const SizedBox(height: 8),
              KeyedSubtree(
                key: const Key('local-hangar-save-progress'),
                child: HangarReaderWaiting(
                  key: ValueKey(('save-wait', m.phase, _waitPhase)),
                  source: _waitSource,
                  height: 4,
                  inheritOpeningSource: _inheritOpeningSource,
                ),
              ),
            ] else if (m.phase == 'ready')
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                children: [
                  StarBridgeCheckboxTile(
                    controlKey: const Key('local-hangar-confirm'),
                    value: _confirmed,
                    onChanged: (value) => setState(() => _confirmed = value),
                    label: confirmation,
                    rowBuilder: (control) => Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        control,
                        Flexible(child: Text(confirmation)),
                      ],
                    ),
                  ),
                  StarBridgeActionButton(
                    controlKey: const Key('local-hangar-save'),
                    kind: StarBridgeActionKind.primary,
                    onActivate: !_confirmed || !m.canSave
                        ? null
                        : (source) {
                            _waitFrom(source);
                            unawaited(
                              runStarBridgeActivation<void>(
                                source,
                                () => m.save(confirmEmpty: count == 0),
                              ),
                            );
                          },
                    child: Text(pick('保存到本机', '儲存到本機', 'Save on this device')),
                  ),
                ],
              )
            else if (m.phase == 'error' || m.phase == 'uncertain')
              Align(
                alignment: Alignment.centerLeft,
                child: StarBridgeActionButton(
                  controlKey: const Key('local-hangar-save-retry'),
                  kind: StarBridgeActionKind.quiet,
                  onActivate: (source) {
                    _waitFrom(source);
                    setState(() => _confirmed = false);
                    unawaited(runStarBridgeActivation<void>(source, m.refresh));
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
    'hangar.removal_selection_required' ||
    'hangar.invalid_removal_selection' => c.pick(
      '舰船移出选择尚未确认，原机库未更改。请重新查询并核对选择。',
      '艦船移出選擇尚未確認，原機庫未更改。請重新查詢並核對選擇。',
      'The removal choices need review. Your saved hangar is unchanged. Check the inventory and choose again.',
    ),
    'hangar.revision_conflict' => c.pick(
      '机库已有更新，请重新核对后保存。',
      '機庫已有更新，請重新核對後儲存。',
      'Your hangar has changed. Review it again before saving.',
    ),
    'hangar.ambiguous_instances' => c.pick(
      '同一礼包内的同型舰船数量或图片不同，暂时无法确认对应关系；原机库未更改。重新读取可能无法解决，请保留当前机库。',
      '同一禮包內的同型艦船數量或圖片不同，暫時無法確認對應關係；原機庫未更改。重新讀取可能無法解決，請保留目前機庫。',
      'Identical ships in one pledge have different counts or images, so their identities cannot be confirmed. Your saved hangar is unchanged. Reading again may not resolve this.',
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
