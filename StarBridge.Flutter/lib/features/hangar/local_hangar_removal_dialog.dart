import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_checkbox_tile.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import 'local_hangar_names.dart';
import 'hangar_reader_copy.dart';
import 'local_hangar_copy.dart';
import 'local_hangar_card_image.dart';
import 'local_hangar_image_cache.dart';
import 'local_hangar_images.dart';
import 'local_hangar_port.dart';
import 'local_hangar_presentation.dart';
import 'local_hangar_reconciliation.dart';

/// One review for every reduced group. Cancel has no effect on saved inventory.
class LocalHangarRemovalDialog extends StatefulWidget {
  const LocalHangarRemovalDialog({
    required this.snapshot,
    required this.groups,
    required this.port,
    required this.selected,
    super.key,
  });
  final LocalHangarSnapshot snapshot;
  final List<LocalHangarRemovalGroup> groups;
  final LocalHangarPort port;
  final Set<String> selected;
  @override
  State<LocalHangarRemovalDialog> createState() =>
      _LocalHangarRemovalDialogState();
}

class _LocalHangarRemovalDialogState extends State<LocalHangarRemovalDialog> {
  late final _selected = {...widget.selected};
  late final _ships = {for (final ship in widget.snapshot.ships) ship.id: ship};
  late final _rows = [
    for (final group in widget.groups) ...[
      (group: group, id: null as String?),
      for (final id in group.shipIds) (group: group, id: id),
    ],
  ];
  final _cache = LocalHangarImageCache();
  bool get _complete => widget.groups.every(
    (g) => g.shipIds.where(_selected.contains).length == g.requiredCount,
  );

  String _name(BuildContext context, LocalHangarShip ship) =>
      LocalHangarNames.primary(Localizations.localeOf(context), ship);

  @override
  Widget build(BuildContext context) {
    final c = HangarReaderCopy(context), local = LocalHangarCopy(context);
    String pick(String cn, String tw, String en) => c.pick(cn, tw, en);
    return Dialog(
      child: SizedBox(
        width: 680,
        height: math.min(640, MediaQuery.sizeOf(context).height * .85),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                pick(
                  '选择已不在机库的舰船',
                  '選擇已不在機庫的艦船',
                  'Which ships left your hangar?',
                ),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  key: const Key('hangar-removal-list'),
                  itemCount: _rows.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return Text(
                        pick(
                          '同一礼包里的相同舰船无法逐艘对应。请选择本机记录中已不在的舰船；保存后移入“曾拥有”，图片和收藏会保留。',
                          '同一禮包裡的相同艦船無法逐艘對應。請選擇本機記錄中已不在的艦船；儲存後移入「曾擁有」，圖片和收藏會保留。',
                          'RSI does not distinguish identical ships within one pledge. Choose the local records to move to Previously owned. Their images and bookmarks will be kept.',
                        ),
                      );
                    }
                    final row = _rows[index - 1], group = row.group;
                    final chosen = group.shipIds
                        .where(_selected.contains)
                        .length;
                    if (row.id == null) {
                      final ship = _ships[group.shipIds.first]!;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          '${LocalHangarNames.model(Localizations.localeOf(context), ship)} · ${pick('原有', '原有', 'Previously')} ${group.shipIds.length} → ${group.shipIds.length - group.requiredCount} · ${pick('已选', '已選', 'Selected')} $chosen/${group.requiredCount}',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      );
                    }
                    final ship = _ships[row.id]!;
                    final selected = _selected.contains(ship.id);
                    final title = _name(context, ship);
                    final imagePort = widget.port is LocalHangarImageProvider
                        ? (widget.port as LocalHangarImageProvider).imageFor(
                            ship.id,
                            widget.snapshot.revision,
                          )
                        : null;
                    final canSelect =
                        !(group.requiredCount > 1 &&
                            !selected &&
                            chosen >= group.requiredCount);
                    final label =
                        '$title${ship.isFavorite ? ' · ${local.favorites}' : ''}';
                    final subtitle = [
                      if (ship.nickname?.trim().isNotEmpty == true)
                        LocalHangarNames.model(
                          Localizations.localeOf(context),
                          ship,
                        ),
                      if (ship.addedAt != null)
                        '${local.addedAt} ${local.dateTime(context, ship.addedAt!)}',
                    ].join('\n');
                    return StarBridgeCheckboxTile(
                      controlKey: ValueKey('hangar-remove-${ship.id}'),
                      value: selected,
                      label: label,
                      subtitle: subtitle,
                      onChanged: !canSelect
                          ? null
                          : (value) => setState(() {
                              if (value == true) {
                                if (group.requiredCount == 1) {
                                  _selected.removeAll(group.shipIds);
                                }
                                _selected.add(ship.id);
                              } else {
                                _selected.remove(ship.id);
                              }
                            }),
                      rowBuilder: (control) => ListTile(
                        enabled: canSelect,
                        contentPadding: EdgeInsets.zero,
                        leading: control,
                        trailing: LocalHangarCardImage(
                          item: LocalHangarPresentation.fromSaved(ship),
                          width: MediaQuery.sizeOf(context).width < 480
                              ? 52
                              : 80,
                          height: 56,
                          imagePort: imagePort,
                          cache: _cache,
                          cacheKey: ship.id,
                        ),
                        title: Text(label),
                        subtitle: Text(subtitle),
                      ),
                    );
                  },
                ),
              ),
              const Divider(),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 12,
                children: [
                  StarBridgeActionButton(
                    controlKey: const Key('hangar-removal-cancel'),
                    kind: StarBridgeActionKind.quiet,
                    onActivate: (source) =>
                        dismissStarBridgeDialog<Set<String>>(
                          context,
                          source: source,
                        ),
                    child: Text(pick('取消', '取消', 'Cancel')),
                  ),
                  StarBridgeActionButton(
                    controlKey: const Key('hangar-removal-confirm'),
                    kind: StarBridgeActionKind.primary,
                    onActivate: _complete
                        ? (source) => dismissStarBridgeDialog<Set<String>>(
                            context,
                            source: source,
                            result: _selected,
                          )
                        : null,
                    child: Text(pick('使用这些选择', '使用這些選擇', 'Use these choices')),
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
