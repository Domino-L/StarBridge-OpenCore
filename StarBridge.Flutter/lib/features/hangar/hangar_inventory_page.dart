import 'dart:async';

import 'package:flutter/material.dart';

import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../ships/ship_display_names.dart';
import 'hangar_combat_icon.dart';
import 'hangar_combat_motion.dart';
import 'hangar_inventory_copy.dart';
import 'hangar_inventory_module.dart';
import 'hangar_inventory_port.dart';

class HangarInventoryPage extends StatefulWidget {
  const HangarInventoryPage({
    required this.module,
    required this.onBack,
    super.key,
  });
  final HangarInventoryModule module;
  final VoidCallback onBack;
  @override
  State<HangarInventoryPage> createState() => _HangarInventoryPageState();
}

class _HangarInventoryPageState extends State<HangarInventoryPage> {
  String _query = '', _size = 'all', _scenario = 'basic';
  bool _clear = false;
  final _search = TextEditingController();
  final _arrivals = <String, DateTime>{};
  @override
  void initState() {
    super.initState();
    unawaited(widget.module.refresh());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String _name(HangarInventoryShip ship) => ShipDisplayNames.primary(
    Localizations.localeOf(context),
    original: ship.original,
    simplifiedChinese: ship.cn,
    traditionalChinese: ship.tw,
  );
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.module,
    builder: (context, _) {
      final m = widget.module, c = HangarInventoryCopy(context);
      final tokens = context.tokens, pending = m.pending;
      final visible =
          pending?.ships ?? m.saved?.ships ?? const <HangarInventoryShip>[];
      final ships = visible
          .where(
            (s) =>
                (_size == 'all' || s.size == _size) &&
                '${s.original} ${s.cn} ${s.tw}'.toLowerCase().contains(
                  _query.toLowerCase(),
                ),
          )
          .toList();
      final clearNeeded =
          pending != null &&
          pending.ships.isEmpty &&
          (m.saved?.ships.isNotEmpty ?? false);
      final tone = m.error != null || m.uncertain
          ? tokens.colors.warning
          : m.phase == 'saved'
          ? tokens.colors.success
          : tokens.colors.accent;
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: c.back,
                  onPressed: m.busy ? null : widget.onBack,
                  icon: const RotatedBox(
                    quarterTurns: 2,
                    child: StarBridgeIcon(StarBridgeIconSemantic.forward),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    c.testTitle,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                DropdownButton<String>(
                  value: m.account,
                  icon: const StarBridgeIcon(StarBridgeIconSemantic.menuDown),
                  items: ['A', 'B']
                      .map(
                        (a) => DropdownMenuItem(
                          value: a,
                          child: Text(
                            '${c.pick("测试账号", "測試帳號", "Test account")} $a',
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: m.busy || m.uncertain || pending != null
                      ? null
                      : (v) {
                          _search.clear();
                          setState(() {
                            _query = '';
                            _clear = false;
                          });
                          unawaited(m.selectAccount(v!));
                        },
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: tokens.surfaces.panel.fill,
                border: Border(
                  left: BorderSide(color: tokens.colors.warning, width: 3),
                ),
              ),
              child: Text(
                c.isolation,
                style: TextStyle(color: tokens.colors.warning),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                DropdownButton<String>(
                  value: _scenario,
                  icon: const StarBridgeIcon(StarBridgeIconSemantic.menuDown),
                  items: ['basic', 'expanded', 'empty']
                      .map(
                        (s) => DropdownMenuItem(
                          value: s,
                          child: Text(c.scenario(s)),
                        ),
                      )
                      .toList(),
                  onChanged: m.busy || m.uncertain || pending != null
                      ? null
                      : (v) => setState(() {
                          _scenario = v!;
                          _clear = false;
                        }),
                ),
                FilledButton(
                  key: const Key('inventory-preview'),
                  onPressed:
                      m.busy ||
                          m.uncertain ||
                          m.saved == null ||
                          pending != null
                      ? null
                      : () {
                          setState(() => _clear = false);
                          unawaited(m.preview(_scenario));
                        },
                  child: Text(c.testData),
                ),
                OutlinedButton(
                  onPressed: m.busy || m.uncertain || pending != null
                      ? null
                      : m.refresh,
                  child: Text(c.refresh),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              child: Text(
                m.uncertain || m.busy
                    ? c.state(m.phase)
                    : m.error != null
                    ? c.failure(m.error!)
                    : c.state(m.phase),
                style: TextStyle(color: tone),
              ),
            ),
            SizedBox(
              height: 4,
              child: m.busy
                  ? LinearProgressIndicator(
                      value: MediaQuery.disableAnimationsOf(context)
                          ? .5
                          : null,
                    )
                  : null,
            ),
            const SizedBox(height: 12),
            if (pending != null) ...[
              Text(c.changes, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(c.diff(pending.added, pending.removed, pending.retained)),
              if (pending.removed > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '${c.pick("将移除", "將移除", "Removing")}: ${m.saved!.ships.where((s) => !pending.ships.any((n) => n.id == s.id)).map(_name).join("、")}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: tokens.colors.warning),
                  ),
                ),
              const SizedBox(height: 10),
            ],
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _search,
                    onChanged: (v) => setState(() => _query = v),
                    decoration: InputDecoration(
                      labelText: c.search,
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                DropdownButton<String>(
                  value: _size,
                  icon: const StarBridgeIcon(StarBridgeIconSemantic.menuDown),
                  items: ['all', 'small', 'medium', 'large', 'capital']
                      .map(
                        (s) =>
                            DropdownMenuItem(value: s, child: Text(c.size(s))),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _size = v!),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Material(
                color: tokens.surfaces.panel.fill,
                shape: RoundedRectangleBorder(
                  side: BorderSide(color: tokens.surfaces.panel.border),
                ),
                child: ships.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text(
                            visible.isNotEmpty
                                ? c.noMatches
                                : pending != null
                                ? c.scenario('empty')
                                : m.saved == null
                                ? c.failure(m.error ?? 'unavailable')
                                : m.saved!.revision == 0
                                ? c.noSaved
                                : c.emptySaved,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : ListView.separated(
                        itemCount: ships.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final ship = ships[i];
                          final key = '${m.account}:${ship.id}';
                          final first = _arrivals.putIfAbsent(
                            key,
                            DateTime.now,
                          );
                          return ListTile(
                            key: ValueKey(key),
                            dense: true,
                            leading: HangarCombatSize.parse(ship.size) == null
                                ? const StarBridgeIcon(
                                    StarBridgeIconSemantic.hangar,
                                  )
                                : HangarCombatIcon(
                                    sizeClass: HangarCombatSize.parse(
                                      ship.size,
                                    )!,
                                    elapsed: DateTime.now().difference(first),
                                  ),
                            title: Text(
                              _name(ship),
                              style: Theme.of(context).textTheme.bodyMedium,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              ship.original,
                              style: Theme.of(context).textTheme.bodySmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Text(
                              c.size(ship.size ?? 'unknown'),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            onTap: () => showDialog<void>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: Text(_name(ship)),
                                content: Text(
                                  '${ship.original}\n${c.size(ship.size ?? "unknown")}\n\n${c.isolation}',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: Text(c.close),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ),
            const SizedBox(height: 12),
            if (clearNeeded)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: _clear,
                title: Text(
                  c.clearConfirm,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                onChanged: m.busy || m.uncertain
                    ? null
                    : (v) => setState(() => _clear = v!),
              ),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                Text(
                  '${c.count(visible.length)}${m.saved?.savedAt == null ? "" : " · ${m.saved!.savedAt!.toLocal().toString().split(".").first}"}',
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (pending != null && !m.uncertain) ...[
                      OutlinedButton(
                        onPressed: m.busy ? null : m.discard,
                        child: Text(c.discard),
                      ),
                      FilledButton(
                        key: const Key('inventory-save'),
                        onPressed:
                            m.busy ||
                                pending.ambiguous ||
                                (clearNeeded && !_clear)
                            ? null
                            : () => m.save(confirmClear: _clear),
                        child: Text(c.save),
                      ),
                    ],
                    if (m.uncertain)
                      FilledButton(
                        onPressed: m.checkResult,
                        child: Text(c.check),
                      ),
                  ],
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
}
