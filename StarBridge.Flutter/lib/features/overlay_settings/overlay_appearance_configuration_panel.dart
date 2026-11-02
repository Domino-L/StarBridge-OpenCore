import 'package:flutter/material.dart';

import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_select_field.dart';
import '../../design_system/interaction/starbridge_expansion_tile.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'overlay_appearance_configuration.dart';
import 'overlay_appearance_options.dart';

class OverlayAppearanceConfigurationPanel extends StatefulWidget {
  const OverlayAppearanceConfigurationPanel({
    required this.configuration,
    required this.options,
    required this.onChanged,
    this.enabled = true,
    this.collectionTryOn = false,
    this.placementStates = const {},
    super.key,
  });
  final OverlayAppearanceConfiguration configuration;
  final OverlayAppearanceOptions options;
  final ValueChanged<OverlayAppearanceOptions> onChanged;
  final bool enabled;
  final bool collectionTryOn;
  final Map<String, String> placementStates;

  @override
  State<OverlayAppearanceConfigurationPanel> createState() =>
      _ConfigurationPanelState();
}

class _ConfigurationPanelState
    extends State<OverlayAppearanceConfigurationPanel> {
  bool _limitReached = false;

  @override
  void didUpdateWidget(OverlayAppearanceConfigurationPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.options != widget.options ||
        oldWidget.configuration != widget.configuration) {
      _limitReached = false;
    }
  }

  void _edit(OverlayAppearanceOptions Function() transform) {
    final OverlayAppearanceOptions next;
    try {
      next = transform();
    } on FormatException {
      setState(() => _limitReached = true);
      return;
    }
    setState(() => _limitReached = false);
    widget.onChanged(next);
  }

  String _copy(String cn, String tw, String en) =>
      AppearanceText(cn, tw, en).resolve(Localizations.localeOf(context));

  @override
  Widget build(BuildContext context) {
    final configuration = widget.configuration;
    final options = widget.options;
    final locale = Localizations.localeOf(context);
    final tokens = context.tokens;
    final rows = configuration.read(options);
    final fieldValues = configuration.readFields(options);
    final editable = widget.enabled && rows != null;
    final strings = AppStrings.of(context);
    final groups = <String, List<AppearanceSlot>>{};
    for (final slot in configuration.slots) {
      groups.putIfAbsent(slot.group.resolve(locale), () => []).add(slot);
    }
    return StarBridgeSurface(
      role: SurfaceRole.panel,
      padding: EdgeInsets.all(tokens.space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            configuration.title.resolve(locale),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          SizedBox(height: tokens.space.xs),
          Text(
            configuration.description.resolve(locale),
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: tokens.colors.textSecondary),
          ),
          if (widget.collectionTryOn)
            Padding(
              padding: EdgeInsets.only(top: tokens.space.sm),
              child: Text(
                locale.languageCode != 'zh'
                    ? 'Try all decorations here. Locked items stay in your arrangement but will not appear in the actual overlay.'
                    : locale.countryCode == 'TW' || locale.scriptCode == 'Hant'
                    ? '這裡可試裝全部裝飾。未解鎖物件會保留在佈置中，但不會在實際浮層顯示。'
                    : '这里可试装全部装饰。未解锁物件会保留在布置中，但不会在实际浮层显示。',
                key: const Key('appearance-config-collection-try-on'),
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: tokens.colors.textSecondary),
              ),
            ),
          if (rows == null || _limitReached)
            Padding(
              padding: EdgeInsets.only(top: tokens.space.md),
              child: Text(
                strings.text(
                  _limitReached
                      ? 'overlay.appearance.configuration.limit'
                      : 'overlay.appearance.configuration.unsupported',
                ),
                style: TextStyle(color: tokens.colors.warning),
              ),
            ),
          if (fieldValues != null && configuration.fields.isNotEmpty) ...[
            SizedBox(height: tokens.space.lg),
            Text(
              _copy('模块外观', '模組外觀', 'Module appearance'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
          if (fieldValues != null)
            for (final field in configuration.fields) ...[
              SizedBox(height: tokens.space.md),
              _ChoiceField(
                key: Key('appearance-config-global-${field.key}'),
                label: field.label.resolve(locale),
                value: field.options.indexWhere(
                  (option) => option.value == fieldValues[field.key],
                ),
                labels: field.options
                    .map((option) => option.label.resolve(locale))
                    .toList(),
                onChanged: editable
                    ? (index) => _edit(
                        () => configuration.changeField(
                          options,
                          field.key,
                          field.options[index].value,
                        ),
                      )
                    : null,
              ),
            ],
          SizedBox(height: tokens.space.lg),
          Text(
            _copy('装饰布置', '裝飾佈置', 'Arrange decorations'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          for (final group in groups.entries) ...[
            SizedBox(height: tokens.space.lg),
            Material(
              type: MaterialType.transparency,
              child: StarBridgeExpansionTile(
                key: PageStorageKey(
                  'appearance-config-group-${configuration.profileId}-${group.value.first.id}',
                ),
                initiallyExpanded:
                    group.key == groups.keys.first ||
                    group.value.any((slot) => rows?[slot.id] != null),
                childrenPadding: EdgeInsets.only(bottom: tokens.space.sm),
                title: group.key,
                subtitle: _groupSummary(group.value, rows),
                children: [
                  for (final slot in group.value)
                    Padding(
                      padding: EdgeInsets.only(top: tokens.space.md),
                      child: _SlotEditor(
                        slot: slot,
                        row: rows?[slot.id],
                        reason: widget.placementStates[slot.id],
                        enabled: editable,
                        onSelect: (index) => _edit(
                          () => configuration.select(options, slot.id, index),
                        ),
                        onField: (key, value) => _edit(
                          () => configuration.change(
                            options,
                            slot.id,
                            key,
                            value,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
          SizedBox(height: tokens.space.md),
          Text(
            strings.text('overlay.appearance.configuration.draft'),
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: tokens.colors.textSecondary),
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: StarBridgeActionButton(
              key: Key('appearance-config-clear-${configuration.profileId}'),
              kind: StarBridgeActionKind.quiet,
              onActivate: editable && rows.values.any((r) => r != null)
                  ? (_) => _edit(() => configuration.clearCollection(options))
                  : null,
              child: Text(
                strings.text('overlay.appearance.configuration.clear'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _groupSummary(
    List<AppearanceSlot> slots,
    Map<String, Map<String, Object?>?>? rows,
  ) {
    final selected = slots.where((s) => rows?[s.id] != null).toList();
    final stowed = selected
        .where(
          (s) =>
              widget.placementStates[s.id] != null &&
              !const {
                'placed',
                'interaction-space',
                'observation-only',
              }.contains(widget.placementStates[s.id]),
        )
        .length;
    if (selected.isEmpty) return _copy('未放置装饰', '未放置裝飾', 'No decorations');
    final unavailable = selected
        .where((s) => widget.placementStates[s.id] == 'interaction-space')
        .length;
    final observed = selected
        .where((s) => widget.placementStates[s.id] == 'observation-only')
        .length;
    return [
      _copy(
        '已布置 ${selected.length} 件',
        '已佈置 ${selected.length} 件',
        '${selected.length} arranged',
      ),
      if (stowed > 0)
        _copy('$stowed 件暂不能显示', '$stowed 件暫不能顯示', '$stowed hidden by layout'),
      if (unavailable > 0)
        _copy(
          '$unavailable 件暂不能互动',
          '$unavailable 件暫不能互動',
          '$unavailable need more interaction space',
        ),
      if (observed > 0)
        _copy(
          '$observed 件仅供观察',
          '$observed 件僅供觀察',
          '$observed observation only',
        ),
    ].join(' · ');
  }
}

class _SlotEditor extends StatelessWidget {
  const _SlotEditor({
    required this.slot,
    required this.row,
    required this.enabled,
    required this.onSelect,
    required this.onField,
    this.reason,
  });
  final AppearanceSlot slot;
  final Map<String, Object?>? row;
  final bool enabled;
  final String? reason;
  final ValueChanged<int> onSelect;
  final void Function(String, Object) onField;
  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context);
    final choice = row == null
        ? null
        : slot.choices.where((c) => c.value == row![slot.selector]).firstOrNull;
    final index = choice == null ? 0 : slot.choices.indexOf(choice) + 1;
    final tokens = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          slot.label.resolve(locale),
          style: Theme.of(context).textTheme.labelLarge,
        ),
        SizedBox(height: tokens.space.xs),
        _ChoiceField(
          key: Key('appearance-config-slot-${slot.id}'),
          label: const AppearanceText('装饰', '裝飾', 'Decoration').resolve(locale),
          value: index,
          labels: [
            AppStrings.of(context)
                .text('overlay.appearance.configuration.none'),
            ...slot.choices.map((c) => c.label.resolve(locale)),
          ],
          onChanged: enabled ? onSelect : null,
        ),
        if (choice != null && reason != null && reason != 'placed')
          Padding(
            padding: EdgeInsets.only(top: tokens.space.sm),
            child: Text(
              _placementReason(reason!).resolve(locale),
              key: Key('appearance-config-status-${slot.id}'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: reason == 'observation-only'
                    ? Theme.of(context).colorScheme.onSurfaceVariant
                    : tokens.colors.warning,
              ),
            ),
          ),
        if (choice != null)
          Container(
            margin: EdgeInsetsDirectional.only(
              top: tokens.space.sm,
              start: tokens.space.sm,
            ),
            padding: EdgeInsetsDirectional.only(
              start: tokens.space.md,
              top: tokens.space.sm,
              bottom: tokens.space.sm,
            ),
            decoration: BoxDecoration(
              border: BorderDirectional(
                start: BorderSide(color: Theme.of(context).dividerColor),
              ),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) => Wrap(
                spacing: tokens.space.sm,
                runSpacing: tokens.space.sm,
                children: [
                  for (final field in choice.fields)
                    SizedBox(
                      width: constraints.maxWidth < 420
                          ? constraints.maxWidth
                          : (constraints.maxWidth - tokens.space.sm) / 2,
                      child: _ChoiceField(
                        key: Key(
                          'appearance-config-field-${slot.id}-${field.key}',
                        ),
                        label: field.label.resolve(locale),
                        value: field.options.indexWhere(
                          (o) => o.value == row![field.key],
                        ),
                        labels: field.options
                            .map((o) => o.label.resolve(locale))
                            .toList(),
                        onChanged: enabled
                            ? (i) => onField(field.key, field.options[i].value)
                            : null,
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  static AppearanceText _placementReason(String reason) => switch (reason) {
    'interaction-space' => const AppearanceText(
      '装饰可以显示，但互动空间不够。调整装饰位置或模块大小后再试。',
      '裝飾可以顯示，但互動空間不夠。調整裝飾位置或模組大小後再試。',
      'The decoration is visible, but needs more interaction space. Adjust its position or the module size.',
    ),
    'observation-only' => const AppearanceText(
      '当前挂置方式仅供观察。想让伙伴玩它，可换一种挂置方式。',
      '目前掛置方式僅供觀察。想讓夥伴玩它，可換一種掛置方式。',
      'This placement is for observation only. Try another mounting style for interaction.',
    ),
    'screen-edge' => const AppearanceText(
      '这里贴着屏幕边缘，装饰暂时收起。换一侧或移动模块后可显示。',
      '這裡貼著螢幕邊緣，裝飾暫時收起。換一側或移動模組後可顯示。',
      'Stowed at the screen edge. Choose another side or move the module to show it.',
    ),
    'joined-edge' => const AppearanceText(
      '这里是两个模块的接缝，装饰暂时收起。分开模块或换一侧后可显示。',
      '這裡是兩個模組的接縫，裝飾暫時收起。分開模組或換一側後可顯示。',
      'Stowed at a module seam. Separate the modules or choose another side.',
    ),
    'neighbor-module' => const AppearanceText(
      '这个位置被相邻模块挡住，装饰暂时收起。调整位置后可显示。',
      '這個位置被相鄰模組擋住，裝飾暫時收起。調整位置後可顯示。',
      'Stowed behind a neighboring module. Change its position to show it.',
    ),
    'decoration-overlap' => const AppearanceText(
      '这里与另一件装饰重叠，暂时收起。调整位置后可显示。',
      '這裡與另一件裝飾重疊，暫時收起。調整位置後可顯示。',
      'Stowed because decorations overlap. Change its position to show it.',
    ),
    'module-hidden' => const AppearanceText(
      '这个模块已关闭，装饰也会收起。开启模块后可显示。',
      '這個模組已關閉，裝飾也會收起。開啟模組後可顯示。',
      'The module is hidden. Enable it to show the decoration.',
    ),
    'module-space' => const AppearanceText(
      '模块空间不够，装饰暂时收起。增大模块后可显示。',
      '模組空間不夠，裝飾暫時收起。放大模組後可顯示。',
      'The module has too little room. Enlarge it to show the decoration.',
    ),
    _ => const AppearanceText(
      '这件装饰目前无法放置，请换一个位置。',
      '這件裝飾目前無法放置，請換一個位置。',
      'This decoration cannot be placed here. Choose another position.',
    ),
  };
}

class _ChoiceField extends StatelessWidget {
  const _ChoiceField({
    required this.label,
    required this.value,
    required this.labels,
    this.onChanged,
    super.key,
  });
  final String label;
  final int value;
  final List<String> labels;
  final ValueChanged<int>? onChanged;
  @override
  Widget build(BuildContext context) => StarBridgeSelectField<int>(
    identity: key ?? label,
    value: value >= 0 ? value : 0,
    decoration: InputDecoration(
      labelText: label,
      enabled: onChanged != null,
      isDense: true,
    ),
    options: [
      for (var i = 0; i < labels.length; i++)
        StarBridgeSelectOption(value: i, label: labels[i]),
    ],
    onSelected: onChanged == null ? null : (value, _) => onChanged!(value),
  );
}
