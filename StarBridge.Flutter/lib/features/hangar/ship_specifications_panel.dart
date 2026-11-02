import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart'
    show SuiteMotion;

import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/icons/native_dropdown_indicator_icon.dart';
import '../../design_system/interaction/starbridge_expansion_tile.dart';
import '../../design_system/interaction/starbridge_interaction_theme.dart';
import '../settings/help_support_waiting.dart';

import 'local_hangar_copy.dart';
import 'local_hangar_port.dart';
import 'ship_specifications_copy.dart';
import 'ship_specifications_port.dart';

/// A lazy section inside the existing detail surface. Opening inventory does no catalogue IO.
class ShipSpecificationsPanel extends StatefulWidget {
  const ShipSpecificationsPanel({
    required this.ship,
    required this.provider,
    super.key,
  });
  final LocalHangarShip ship;
  final ShipSpecificationsProvider provider;
  @override
  State<ShipSpecificationsPanel> createState() =>
      _ShipSpecificationsPanelState();
}

class _ShipSpecificationsPanelState extends State<ShipSpecificationsPanel> {
  ShipSpecifications? _value;
  bool _loading = false, _failed = false;
  int _epoch = 0;
  InteractionSource _waitSource = InteractionSource.programmatic;
  int _waitPhase = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ShipSpecificationsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ship.modelKey != widget.ship.modelKey ||
        oldWidget.provider != widget.provider) {
      _value = null;
      _load();
    }
  }

  Future<void> _load({
    bool refresh = false,
    InteractionSource source = InteractionSource.programmatic,
  }) async {
    final epoch = ++_epoch;
    if (!widget.provider.specificationsAvailable) return;
    setState(() {
      _loading = true;
      _failed = false;
      _waitSource = source;
      _waitPhase++;
    });
    try {
      final value = await widget.provider.specificationsFor(
        widget.ship,
        refresh: refresh,
      );
      if (mounted && epoch == _epoch) {
        setState(() {
          _value = value;
        });
      }
    } catch (_) {
      if (mounted && epoch == _epoch) {
        setState(() {
          _failed = true;
        });
      }
    } finally {
      if (mounted && epoch == _epoch) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = LocalHangarCopy(context), value = _value;
    final data = resolveStarBridgeInteraction(context);
    String number(num value) {
      final decimal = value
          .toStringAsFixed(4)
          .replaceFirst(RegExp(r'\.?0+$'), '');
      final parts = decimal.split('.');
      return '${MaterialLocalizations.of(context).formatDecimal(int.parse(parts.first))}${parts.length > 1 ? '.${parts.last}' : ''}';
    }

    String formatted(ShipSpecificationField f) {
      final n = num.tryParse(f.value);
      if (n != null && f.key == 'radar.size') return 'S${number(n)}';
      if (n != null && f.key == 'quantum.range') return '${number(n / 1e9)} Gm';
      return '${n == null ? f.value : number(n)}${f.unit.isEmpty ? '' : ' ${f.unit}'}';
    }

    Widget row(String label, String text) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              text,
              textAlign: TextAlign.end,
              style: const TextStyle(
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
    Widget disclosure({
      required Key key,
      required String title,
      required List<Widget> children,
      bool initiallyExpanded = false,
      EdgeInsetsGeometry childrenPadding = EdgeInsets.zero,
    }) => Padding(
      // Match the former native tile's transparent top and bottom borders.
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: StarBridgeExpansionTile(
        key: key,
        title: title,
        initiallyExpanded: initiallyExpanded,
        useNativePageStorage: true,
        headerMinHeight: 0,
        childrenPadding: childrenPadding,
        childrenCrossAxisAlignment: CrossAxisAlignment.center,
        headerBuilder: (context, visual, open) {
          final theme = Theme.of(context);
          final expansion = ExpansionTileTheme.of(context);
          final progress = SuiteMotion.curve.transform(open);
          return ListTileTheme.merge(
            textColor: Color.lerp(
              expansion.collapsedTextColor ??
                  (theme.useMaterial3
                      ? theme.colorScheme.onSurface
                      : theme.textTheme.titleMedium?.color),
              expansion.textColor ??
                  (theme.useMaterial3
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.primary),
              progress,
            ),
            iconColor: Color.lerp(
              expansion.collapsedIconColor ??
                  (theme.useMaterial3
                      ? theme.colorScheme.onSurfaceVariant
                      : theme.unselectedWidgetColor),
              expansion.iconColor ?? theme.colorScheme.primary,
              progress,
            ),
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(title),
              trailing: Transform.rotate(
                angle: math.pi * progress,
                child: const NativeDropdownIndicatorIcon.expandMore(),
              ),
            ),
          );
        },
        children: children,
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 28),
        Wrap(
          spacing: 16,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(c.specsTitle, style: Theme.of(context).textTheme.titleMedium),
            if (widget.provider.specificationsAvailable)
              StarBridgeActionButton(
                controlKey: const Key('ship-spec-refresh'),
                kind: StarBridgeActionKind.quiet,
                onActivate: _loading
                    ? null
                    : (source) => _load(refresh: true, source: source),
                child: Text(value == null ? c.specsRetry : c.specsRefresh),
              ),
          ],
        ),
        if (!widget.provider.specificationsAvailable)
          Text(c.specsOffline)
        else ...[
          if (_loading)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: data.suite == InteractionSuite.standard
                  ? Text(c.specsLoading)
                  : HelpSupportWaiting(
                      key: ValueKey(('ship-spec-wait', _waitPhase)),
                      source: _waitSource,
                      label: c.specsLoading,
                    ),
            ),
          if (_failed) Semantics(liveRegion: true, child: Text(c.specsFailure)),
          if (value != null) ...[
            if (value.stale) Text(c.specsStale),
            if (value.state != 'ready')
              Text(
                value.state == 'ambiguous'
                    ? c.specsAmbiguous
                    : widget.ship.deliveryStatus == 'concept'
                    ? c.specsConceptMissing
                    : c.specsMissing,
              )
            else ...[
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  Text('SCM', style: Theme.of(context).textTheme.bodySmall),
                  Text(
                    c.specsMatched(value.modelName),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (value.dataVersion case final version?)
                    Text(
                      c.specsVersion(version),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  if (value.fetchedAt case final at?)
                    Text(
                      c.specsFetched(c.dateTime(context, at.toLocal())),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 24,
                runSpacing: 8,
                children: [
                  for (final f
                      in value.groups
                          .where((g) => g.key == 'overview')
                          .expand((g) => g.fields)
                          .where(
                            (f) => const {'crew', 'cargo'}.contains(f.key),
                          ))
                    Text(
                      '${c.specLabel(f.key)}  ${formatted(f)}',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(c.specsBasis, style: Theme.of(context).textTheme.bodySmall),
              if (value.paintBaseModel case final base?)
                Text(
                  c.specsPaintBase(base),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              if (value.bundleBaseModel case final carrier?)
                Text(
                  c.specsBundleBase(carrier),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              const SizedBox(height: 6),
              LayoutBuilder(
                builder: (context, bounds) {
                  final wide =
                      bounds.maxWidth >= 640 &&
                      MediaQuery.textScalerOf(context).scale(14) <= 20;
                  return Wrap(
                    spacing: 20,
                    runSpacing: 8,
                    children: [
                      for (final group in value.groups)
                        if (c.specLabel(group.key).isNotEmpty)
                          SizedBox(
                            key: ValueKey('${group.key}-$wide'),
                            width: wide
                                ? (bounds.maxWidth - 20) / 2
                                : bounds.maxWidth,
                            child: disclosure(
                              key: ValueKey('ship-spec-${group.key}'),
                              childrenPadding: const EdgeInsets.only(
                                bottom: 12,
                              ),
                              initiallyExpanded:
                                  wide || group.key == 'overview',
                              title: c.specLabel(group.key),
                              children: [
                                for (final f in group.fields)
                                  if (c.specLabel(f.key).isNotEmpty)
                                    row(c.specLabel(f.key), formatted(f)),
                              ],
                            ),
                          ),
                    ],
                  );
                },
              ),
              if (value.components.isNotEmpty)
                disclosure(
                  key: const ValueKey('ship-spec-components'),
                  title: c.specLabel('components'),
                  children: _components(context, c, value.components, row),
                ),
            ],
          ],
        ],
      ],
    );
  }

  List<Widget> _components(
    BuildContext context,
    LocalHangarCopy c,
    List<ShipSpecificationComponent> parts,
    Widget Function(String, String) row,
  ) {
    final grouped = <String, List<ShipSpecificationComponent>>{};
    for (final part in parts) {
      if (c.specComponentLabel(part.group).isEmpty) continue;
      final key =
          '${part.group}|${part.name}|${part.size}|${part.grade}|${part.editable}';
      grouped.putIfAbsent(key, () => []).add(part);
    }
    return [
      for (final items in grouped.values) ...[
        row(
          c.specComponentLabel(items.first.group),
          '${c.locale.languageCode == 'zh' ? items.first.chineseName ?? items.first.name : items.first.name}${items.length > 1 ? ' × ${items.length}' : ''}',
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Align(
            alignment: Alignment.centerRight,
            child: Text(
              [
                if (items.first.size case final size?) 'S$size',
                if (items.first.grade case final grade?) c.specsGrade(grade),
                if (items.first.editable == false) c.specsFixed,
              ].join(' · '),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
      ],
    ];
  }
}
