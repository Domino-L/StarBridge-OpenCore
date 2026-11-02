import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../communities/community_logo_crop.dart';
import 'account_avatar.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_dialog.dart';

class AccountAvatarScope extends InheritedWidget {
  const AccountAvatarScope({
    required this.port,
    required this.imageData,
    required this.editable,
    required super.child,
    this.rsiManaged = false,
    super.key,
  });
  final AccountAvatarPort? port;
  final String? imageData;
  final bool editable;

  /// SCM-signed-in users show their RSI avatar and change it on the RSI site.
  final bool rsiManaged;
  static AccountAvatarScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AccountAvatarScope>();
  @override
  bool updateShouldNotify(AccountAvatarScope oldWidget) =>
      imageData != oldWidget.imageData ||
      editable != oldWidget.editable ||
      rsiManaged != oldWidget.rsiManaged ||
      port != oldWidget.port;
}

class AccountAvatarEditor extends StatefulWidget {
  const AccountAvatarEditor({super.key});
  @override
  State<AccountAvatarEditor> createState() => _AccountAvatarEditorState();
}

class _AccountAvatarEditorState extends State<AccountAvatarEditor> {
  bool _busy = false;
  String? _message;
  StarBridgeDialogRoute<dynamic>? _child;
  AccountAvatarPort? _scopePort;
  StreamSubscription<dynamic>? _events;
  bool _editable = false;
  int _epoch = 0;
  void _invalidate() {
    ++_epoch;
    retireStarBridgeDialog(_child);
    _child = null;
    if (mounted) setState(() => _message = null);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = AccountAvatarScope.of(context);
    final port = scope?.port;
    final editable = scope?.editable == true;
    if (!identical(port, _scopePort)) {
      _invalidate();
      unawaited(_events?.cancel());
      _scopePort = port;
      _events = port?.session.events.listen(
        (event) {
          if (!identical(port, _scopePort)) return;
          if (event.name == 'account.changed' ||
              event.name == 'bootstrap.invalidated') {
            _invalidate();
          }
        },
        onDone: () {
          if (identical(port, _scopePort)) _invalidate();
        },
      );
    } else if (_editable && !editable) {
      _invalidate();
    }
    _editable = editable;
  }

  Future<T?> _dialog<T>(WidgetBuilder builder) async {
    StarBridgeDialogRoute<T>? opened;
    try {
      return await showStarBridgeDialog<T>(
        context,
        builder: builder,
        onRouteCreated: (route) => _child = opened = route,
      );
    } finally {
      if (identical(_child, opened)) _child = null;
    }
  }

  @override
  void dispose() {
    ++_epoch;
    retireStarBridgeDialog(_child);
    _scopePort = null;
    unawaited(_events?.cancel());
    super.dispose();
  }

  Future<void> _choose(AccountAvatarPort port) async {
    if (_busy ||
        !mounted ||
        !_editable ||
        !identical(port, _scopePort) ||
        !port.canPickLogo) {
      return;
    }
    final epoch = ++_epoch, generation = port.session.activeGeneration;
    bool current() =>
        mounted &&
        epoch == _epoch &&
        _editable &&
        identical(port, _scopePort) &&
        generation == port.session.activeGeneration;
    final strings = AppStrings.of(context);
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final source = await port.pickLogo();
      if (!current() || source == null) return;
      final cropped = await _dialog<String>(
        (_) => CommunityLogoCrop(port: port, source: source),
      );
      if (!current() || cropped == null) return;
      final confirmed = await _dialog<bool>(
        (context) => AlertDialog(
          title: Text(strings.text('profile.avatar.change')),
          content: Text(strings.text('profile.avatar.confirm')),
          actions: [
            StarBridgeActionButton(
              kind: StarBridgeActionKind.quiet,
              controlKey: const Key('account-avatar-confirm-cancel'),
              onActivate: (source) => dismissStarBridgeDialog(
                context,
                source: source,
                result: false,
              ),
              child: Text(strings.text('common.cancel')),
            ),
            StarBridgeActionButton(
              kind: StarBridgeActionKind.primary,
              controlKey: const Key('account-avatar-confirm-save'),
              onActivate: (source) => dismissStarBridgeDialog(
                context,
                source: source,
                result: true,
              ),
              child: Text(strings.text('profile.avatar.change')),
            ),
          ],
        ),
      );
      if (!current() || confirmed != true) return;
      await port.save(cropped);
      if (current()) setState(() => _message = 'profile.avatar.saved');
    } catch (_) {
      if (current()) setState(() => _message = 'profile.avatar.failed');
    } finally {
      try {
        await port.clearLogo();
      } catch (_) {
        /* Account invalidation clears native image buffers. */
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openRsi(AccountAvatarPort port) async {
    final epoch = _epoch;
    setState(() => _message = null);
    try {
      final response = await port.session.request(
        'helpSupport.openRsiProfileSettings',
        payload: const {'schemaVersion': 1},
      );
      if (response.status != 'ok') throw const FormatException();
    } on Object {
      if (mounted && epoch == _epoch) {
        setState(() => _message = 'profile.avatar.rsiOpenFailed');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = AccountAvatarScope.of(context);
    final strings = AppStrings.of(context);
    final port = scope?.port;
    final canEdit = scope?.editable == true && port?.canPickLogo == true;
    final rsi = !canEdit && scope?.rsiManaged == true;
    final canOpenRsi =
        rsi &&
        port?.session.hostCapabilities.contains(
              'helpSupport.openRsiProfileSettings',
            ) ==
            true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          strings.text(
            canEdit
                ? 'profile.avatar.shared'
                : rsi
                ? 'profile.avatar.rsi'
                : 'profile.avatar.managed',
          ),
        ),
        if (canOpenRsi) ...[
          const SizedBox(height: 8),
          StarBridgeActionButton(
            controlKey: const Key('profile-open-rsi-avatar'),
            onActivate: _busy ? null : (_) => _openRsi(port!),
            child: Text(strings.text('profile.avatar.rsiOpen')),
          ),
        ],
        const SizedBox(height: 8),
        if (canEdit)
          StarBridgeActionButton(
            controlKey: const Key('profile-change-account-avatar'),
            onActivate: _busy ? null : (_) => _choose(port!),
            child: Text(
              strings.text(
                _busy ? 'profile.avatar.saving' : 'profile.avatar.change',
              ),
            ),
          ),
        if (_message != null) Text(strings.text(_message!)),
      ],
    );
  }
}
