import 'dart:async';

import 'package:flutter/material.dart';

import '../../platform/bridge/bridge_client_session.dart';
import '../../platform/bridge/bridge_account_access.dart';
import '../../platform/bridge/bridge_envelope.dart';

abstract interface class OverlayRosterPort {
  Stream<void> get invalidations;
  Future<Map<String, Object?>> request([
    int? revision,
    String? key,
    String? mode,
  ]);
}

final class BridgeOverlayRoster implements OverlayRosterPort {
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
  ]) async {
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
            if (revision != null) ...{
              'revision': revision,
              'key': key,
              'mode': mode,
            },
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
        p['rows'] is! List) {
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
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: () => showDialog<void>(
      context: context,
      builder: (_) => _RosterDialog(port: port),
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
  const _RosterDialog({required this.port});
  final OverlayRosterPort port;
  @override
  State<_RosterDialog> createState() => _RosterDialogState();
}

class _RosterDialogState extends State<_RosterDialog> {
  Map<String, Object?>? data;
  bool busy = true, failed = false;
  int epoch = 0;
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
    unawaited(load());
  }

  Future<void> load([String? key, String? mode]) async {
    final turn = ++epoch;
    setState(() {
      busy = true;
      failed = false;
    });
    try {
      final next = await widget.port.request(
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

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(_copy(context, '当前场景成员', '目前場景成員', 'Current scene members')),
    content: SizedBox(
      width: 480,
      height: 360,
      child: busy
          ? const Center(child: CircularProgressIndicator())
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
                    trailing: DropdownButton<String>(
                      value: row['mode'] as String,
                      items: [
                        DropdownMenuItem(
                          value: 'auto',
                          child: Text(_copy(context, '自动', '自動', 'Automatic')),
                        ),
                        DropdownMenuItem(
                          value: 'pin',
                          child: Text(_copy(context, '钉住', '釘住', 'Pin')),
                        ),
                        DropdownMenuItem(
                          value: 'exclude',
                          child: Text(_copy(context, '不显示', '不顯示', 'Hide')),
                        ),
                      ],
                      onChanged: (mode) {
                        if (mode != null) {
                          unawaited(load(row['key'] as String, mode));
                        }
                      },
                    ),
                  ),
              ],
            ),
    ),
    actions: [
      TextButton(
        onPressed: busy ? null : () => load(),
        child: Text(_copy(context, '刷新', '重新整理', 'Refresh')),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(_copy(context, '关闭', '關閉', 'Close')),
      ),
    ],
  );
}
