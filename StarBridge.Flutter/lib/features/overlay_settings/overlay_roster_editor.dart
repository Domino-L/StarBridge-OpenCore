import 'dart:async';

import 'package:flutter/material.dart';

import '../../design_system/interaction/starbridge_interaction_theme.dart';
import '../../design_system/interaction/starbridge_compact_select.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../platform/bridge/bridge_client_session.dart';
import '../../platform/bridge/bridge_account_access.dart';
import '../../platform/bridge/bridge_envelope.dart';
import '../common/social_read_activity.dart';
import 'overlay_roster_display_options.dart';

abstract interface class OverlayRosterPort {
  Stream<void> get invalidations;
  Future<Map<String, Object?>> request([
    int? revision,
    String? key,
    String? mode,
  ]);
}

final class BridgeOverlayRoster
    implements OverlayRosterPort, OverlayRosterDisplayPort {
  BridgeOverlayRoster(this.session);
  final BridgeClientSession session;
  BridgeAccountContext? _owner;
  int? _generation;
  @override
  Stream<void> get invalidations => session.events
      .where(
        (e) => e.name == 'account.changed' || e.name == 'bootstrap.invalidated',
      )
      .map((_) {});
  @override
  Future<Map<String, Object?>> request([
    int? revision,
    String? key,
    String? mode,
  ]) => _send(revision, {'key': key, 'mode': mode});

  @override
  Future<Map<String, Object?>> updateDisplay(
    int revision,
    OverlayRosterDisplay display,
  ) => _send(revision, {'display': display.toWire()});

  Future<Map<String, Object?>> _send(
    int? revision,
    Map<String, Object?> change,
  ) async {
    final account = await session
        .beginRequest('account.getCurrent', payload: const {'schemaVersion': 1})
        .future;
    if (!hasRelayAccount(account) || account.accountContext == null) {
      throw StateError('Signed out');
    }
    final owner = account.accountContext!;
    if (revision != null &&
        (_generation != session.activeGeneration ||
            _owner?.subject != owner.subject ||
            _owner?.authority != owner.authority ||
            _owner?.environment != owner.environment)) {
      throw StateError('Account changed');
    }
    final reply = await session
        .beginRequest(
          revision == null ? 'overlayRoster.read' : 'overlayRoster.update',
          accountContext: account.accountContext,
          payload: {
            'schemaVersion': 1,
            if (revision != null) ...{'revision': revision, ...change},
          },
        )
        .future;
    if (reply.accountContext != account.accountContext &&
        (reply.accountContext?.subject != account.accountContext?.subject ||
            reply.accountContext?.authority !=
                account.accountContext?.authority ||
            reply.accountContext?.environment !=
                account.accountContext?.environment)) {
      throw StateError('Account changed');
    }
    if (reply.sessionGeneration != session.activeGeneration) {
      throw StateError('Account changed');
    }
    final p = reply.payload;
    if (p['schemaVersion'] != 1 ||
        p['revision'] is! int ||
        p['rows'] is! List ||
        (p.containsKey('display') &&
            OverlayRosterDisplay.tryParse(p['display']) == null)) {
      throw const FormatException();
    }
    for (final row in p['rows']! as List) {
      if (row is! Map ||
          row['key'] is! String ||
          row['name'] is! String ||
          !['auto', 'pin', 'exclude'].contains(row['mode'])) {
        throw const FormatException();
      }
    }
    _owner = owner;
    _generation = reply.sessionGeneration;
    return p;
  }
}

class OverlayRosterButton extends StatelessWidget {
  const OverlayRosterButton({required this.port, super.key});
  final OverlayRosterPort port;
  @override
  Widget build(BuildContext context) => StarBridgeActionButton(
    controlKey: const Key('overlay-roster-open'),
    onActivate: (source) => unawaited(
      showStarBridgeDialog<void>(
        context,
        source: source,
        builder: (_) => _RosterDialog(port: port, openingSource: source),
      ),
    ),
    child: Text(_copy(context, '选择显示成员', '選擇顯示成員', 'Choose visible members')),
  );
}

String _copy(BuildContext c, String zh, String hant, String en) {
  final l = Localizations.localeOf(c);
  return l.languageCode != 'zh'
      ? en
      : l.scriptCode == 'Hant' || l.countryCode == 'TW'
      ? hant
      : zh;
}

class _RosterDialog extends StatefulWidget {
  const _RosterDialog({required this.port, required this.openingSource});
  final OverlayRosterPort port;
  final InteractionSource openingSource;
  @override
  State<_RosterDialog> createState() => _RosterDialogState();
}

class _RosterDialogState extends State<_RosterDialog> {
  Map<String, Object?>? data;
  bool busy = true, failed = false;
  int epoch = 0;
  InteractionSource _waitingSource = InteractionSource.programmatic;
  late final StreamSubscription<void> events;
  @override
  void initState() {
    super.initState();
    events = widget.port.invalidations.listen(
      (_) {
        epoch++;
        if (mounted) {
          setState(() {
            data = null;
          });
          unawaited(load());
        }
      },
      onDone: () {
        if (mounted) {
          setState(() {
            epoch++;
            data = null;
            failed = true;
            busy = false;
          });
        }
      },
    );
    unawaited(load(source: widget.openingSource));
  }

  Future<void> load({
    String? key,
    String? mode,
    OverlayRosterDisplay? display,
    InteractionSource source = InteractionSource.programmatic,
  }) async {
    final turn = ++epoch;
    setState(() {
      busy = true;
      failed = false;
      _waitingSource = source;
    });
    try {
      final next = display != null
          ? await (widget.port as OverlayRosterDisplayPort).updateDisplay(
              data!['revision'] as int,
              display,
            )
          : await widget.port.request(
              key == null ? null : data!['revision'] as int,
              key,
              mode,
            );
      if (mounted && turn == epoch) {
        setState(() {
          data = next;
          busy = false;
        });
      }
    } catch (_) {
      if (mounted && turn == epoch) {
        setState(() {
          data = null;
          busy = false;
          failed = true;
        });
      }
    }
  }

  @override
  void dispose() {
    epoch++;
    events.cancel();
    super.dispose();
  }

  /// The overflow display options, when both the port and the Host support them.
  Widget? _displayOptions(BuildContext context) {
    final display = widget.port is OverlayRosterDisplayPort
        ? OverlayRosterDisplay.tryParse(data?['display'])
        : null;
    if (display == null) return null;
    return OverlayRosterDisplayOptions(
      display: display,
      copy: (zh, hant, en) => _copy(context, zh, hant, en),
      onChanged: busy
          ? null
          : (next, source) => unawaited(load(display: next, source: source)),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(_copy(context, '当前场景成员', '目前場景成員', 'Current scene members')),
    content: SizedBox(
      width: 480,
      height: 360,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!busy && !failed) ...[
            ?_displayOptions(context),
            if (_displayOptions(context) != null) const Divider(height: 16),
          ],
          Expanded(child: _members(context)),
        ],
      ),
    ),
    actions: _actions(context),
  );

  Widget _members(BuildContext context) => busy
      ? Center(
          child: _RosterWaiting(
            key: ValueKey(('overlay-roster-wait-phase', epoch)),
            source: _waitingSource,
          ),
        )
      : failed
      ? Text(
          _copy(
            context,
            '读取或保存失败，请刷新后重试。',
            '讀取或儲存失敗，請重新整理後重試。',
            'Could not read or save. Refresh to retry.',
          ),
        )
      : (data?['rows'] as List? ?? []).isEmpty
      ? Text(
          _copy(
            context,
            '当前没有可选择的成员。',
            '目前沒有可選擇的成員。',
            'No members are available in this scene.',
          ),
        )
      : ListView(
          children: [
            for (final row in data!['rows']! as List)
              ListTile(
                title: Text(row['name'] as String),
                trailing: StarBridgeCompactSelect<String>(
                  identity: ('overlay-roster-mode', row['key']),
                  controlKey: ValueKey((
                    'overlay-roster-mode-control',
                    row['key'],
                  )),
                  semanticLabel:
                      '${row['name']} · ${_copy(context, '显示方式', '顯示方式', 'Display mode')}',
                  value: row['mode'] as String,
                  options: [
                    StarBridgeSelectOption(
                      value: 'auto',
                      label: _copy(context, '自动', '自動', 'Automatic'),
                    ),
                    StarBridgeSelectOption(
                      value: 'pin',
                      label: _copy(context, '钉住', '釘住', 'Pin'),
                    ),
                    StarBridgeSelectOption(
                      value: 'exclude',
                      label: _copy(context, '不显示', '不顯示', 'Hide'),
                    ),
                  ],
                  onSelected: (mode, source) => unawaited(
                    load(key: row['key'] as String, mode: mode, source: source),
                  ),
                ),
              ),
          ],
        );

  List<Widget> _actions(BuildContext context) => [
    StarBridgeActionButton(
      kind: StarBridgeActionKind.quiet,
      controlKey: const Key('overlay-roster-refresh'),
      onActivate: busy ? null : (source) => unawaited(load(source: source)),
      child: Text(_copy(context, '刷新', '重新整理', 'Refresh')),
    ),
    StarBridgeActionButton(
      kind: StarBridgeActionKind.quiet,
      controlKey: const Key('overlay-roster-close'),
      onActivate: (source) => dismissStarBridgeDialog(context, source: source),
      child: Text(_copy(context, '关闭', '關閉', 'Close')),
    ),
  ];
}

/// Presentation of the admitted request only. Each epoch freezes its own
/// provenance; an invalidation is never relabelled by an earlier user action.
class _RosterWaiting extends StatelessWidget {
  const _RosterWaiting({required this.source, super.key});
  final InteractionSource source;

  @override
  Widget build(BuildContext context) {
    final data = resolveStarBridgeInteraction(context);
    final animate = !data.reduceMotion && source == InteractionSource.pointer;
    final label = _copy(context, '正在处理…', '正在處理…', 'Please wait…');
    return SizedBox(
      key: const Key('overlay-roster-waiting'),
      width: 160,
      height: 40,
      child: Center(
        child: data.suite == InteractionSuite.standard
            ? Semantics(
                liveRegion: true,
                label: label,
                child: ExcludeSemantics(
                  child: CircularProgressIndicator(value: animate ? null : .5),
                ),
              )
            : SocialReadActivity(
                source: source,
                // The exact opening source was passed by the existing button.
                opening: false,
                label: label,
                height: 4,
              ),
      ),
    );
  }
}
