import 'dart:async';

import '../../features/direct_messages/direct_messages_module.dart';
import '../../platform/window/menu_preview_window_port.dart';
import '../../platform/window/menu_profile_navigation.dart';
import 'menu_message_drafts.dart';
import 'menu_organization_avatars.dart';
import 'menu_comms_invitations.dart';
import 'menu_chat_archive.dart';
import 'menu_account_avatar.dart';

/// Visible-only communication lease in the primary engine.
/// Opaque UI keys resolve against the latest account-scoped directory here;
/// Target refs and receipt identifiers never cross to the surface.
final class MenuCommsSession
    implements
        MenuCommsReadLease,
        MenuCommsComposeLease,
        MenuProfileTargets,
        MenuChatOpener {
  MenuCommsSession(
    this._port,
    this._publish, {
    this.archive,
    this.ownAvatar,
    MenuCommsInvitations Function(void Function(Map<String, Object?>))?
    invitations,
  }) {
    _invitations = invitations?.call((view) {
      _invitationView = view;
      _emit(_view);
    });
    _subscription = _port.invalidations.listen((_) {
      if (_disposed) return;
      _identityEpoch++;
      _ownPhoto.clear();
      _history.clear();
      _drafts.clear();
      _clear();
      if (_visible) unawaited(_read());
    });
  }
  final DirectMessagesPort _port;
  final MenuChatArchive? archive;
  final String? Function()? ownAvatar;
  late final _ownPhoto = MenuAccountAvatar(() {
    if (_visible) _emit(_view);
  });
  MenuCommsInvitations? _invitations;
  Map<String, Object?>? _invitationView;
  final _attachmentCodes = <String, String>{};
  int _attachmentSerial = 0;
  final void Function(Map<String, Object?>) _publish;
  late final StreamSubscription<void> _subscription;
  Timer? _timer;
  bool _visible = false, _disposed = false, _reading = false;
  bool _silentRead = false;
  int _epoch = 0, _serial = 0, _before = 0, _oldest = 0;
  int _identityEpoch = 0;
  bool _hasOlder = false;
  Map<String, Conversation> _targets = {};
  Conversation? _selected;
  String? _selectedKey;
  final _drafts = MenuMessageDrafts();
  final _avatars = MenuOrganizationAvatars();
  final _portraits = <String, String?>{};
  // Bounded display-only history. Never cache command grants or invitation codes.
  final _history = <(String, int), Map<String, Object?>>{};
  String _historyIdentity(Conversation row) => row.conversationKey ?? row.ref;
  Map<String, Object?> _view = const {'state': 'idle'};
  bool _sending = false, _canSend = false;
  bool _receipting = false;
  int _receiptSerial = 0, _readThrough = 0;
  String? _readRef;
  String _readStatus = '';
  final _receipts = <String, int>{};
  @override
  void openChat(MenuChatTarget? target) {
    if (_disposed || !_visible || _sending) return;
    _clear();
    if (target == null || target.reference.isEmpty) {
      _emit({'state': 'restricted'});
      return;
    }
    _selected = Conversation(
      target.reference,
      target.name,
      '',
      DateTime.now(),
      0,
      'none',
      avatar: target.avatar,
      conversationKey: target.stableKey,
    );
    _selectedKey = 'c${++_serial}';
    unawaited(_read());
  }

  DateTime? _permissionAt;
  bool get _supportsSending =>
      _port is DirectMessageSender &&
      (_port as DirectMessageSender).supportsSending;
  bool get _permissionFresh =>
      _permissionAt != null &&
      DateTime.now().difference(_permissionAt!) < const Duration(seconds: 30);

  // Stable conversation identity survives renewed Host command references.
  // Older hosts without this field retain drafts only while their ref is valid.
  MenuMessageDraft? _draftFor(Conversation target) => _drafts.forTarget(
    target.conversationKey == null
        ? 'ref:${target.ref}'
        : 'conversation:${target.conversationKey}',
  );

  void _emit(Map<String, Object?> view) {
    _view = view;
    if (_disposed) return;
    final selected = _selected;
    final draft = selected == null ? null : _draftFor(selected);
    _publish({
      ...view,
      if (view['state'] == 'ready') ...{
        'ownAvatar': _ownPhoto.read(ownAvatar?.call()),
        'refreshing': _reading && !_silentRead,
        'invitation': _invitations?.opened == true ? _invitationView : null,
        'inviteAvailable': _invitations?.supportsSend == true,
        'archiveAvailable': archive != null,
        'busy': _sending,
        'rows': [
          for (final row in _targets.entries)
            {
              'key': row.key,
              'name': _text(row.value.name, 128),
              'preview': _text(row.value.preview, 256),
              'avatar': _portraits[row.key],
              'time': row.value.time.toUtc().toIso8601String(),
              'unread': row.value.unread,
              'request': row.value.request,
            },
        ],
      },
      if (view['state'] == 'ready' && _readStatus.isNotEmpty)
        'readStatus': _readStatus,
      if (view['state'] == 'ready' && selected != null && _supportsSending) ...{
        'compose': true,
        'canSend': _canSend && _permissionFresh && !_sending,
        'draft': draft?.text ?? '',
        'draftRevision': draft?.revision ?? 0,
        'delivery': draft?.status ?? 'limit',
        'locked': draft == null || draft.locked,
      },
    });
  }

  @override
  void compose(String action, String key, String text, int revision) {
    if (_disposed ||
        !_visible ||
        key != _selectedKey ||
        _selected == null ||
        !_supportsSending) {
      return;
    }
    final draft = _draftFor(_selected!);
    if (draft == null) return;
    if (action == 'check') {
      if (!_sending && !_reading) {
        _before = 0;
        unawaited(_read());
      }
      return;
    }
    if (!const {'edit', 'send'}.contains(action) ||
        !draft.edit(text, revision)) {
      return;
    }
    if (action == 'send' &&
        _view['state'] == 'ready' &&
        !_sending &&
        _canSend &&
        _permissionFresh &&
        draft.text.trim().isNotEmpty) {
      unawaited(_send(_selected!, draft, _identityEpoch));
    } else {
      _emit(_view);
      if (action == 'send' && !_permissionFresh) unawaited(_read());
    }
  }

  Future<void> _send(
    Conversation target,
    MenuMessageDraft draft,
    int identity,
  ) async {
    if (_reading) _cancel();
    _sending = true;
    final task = draft.send(_port as DirectMessageSender, target.ref);
    _emit(_view);
    await task;
    if (_disposed) return;
    _sending = false;
    if (identity != _identityEpoch) {
      if (_visible) unawaited(_read());
      return;
    }
    if (_selected?.ref == target.ref && _visible) {
      _before = 0;
      _canSend = false; // Revalidate current permission after every attempt.
      _emit(_view);
    }
    if (_visible) unawaited(_read());
  }

  @override
  MenuProfileTarget? profileTarget(String key) {
    if (key == 'self' && _visible && !_disposed && _selected != null) {
      final identity = _identityEpoch;
      return MenuProfileTarget(
        source: 'self',
        reference: '',
        query: '',
        avatar: _ownPhoto.read(ownAvatar?.call()),
        isCurrent: () => _visible && !_disposed && identity == _identityEpoch,
        isAccountCurrent: () => !_disposed && identity == _identityEpoch,
      );
    }
    final row = _selectedKey == key ? _selected : _targets[key];
    if (!_visible || _disposed || row == null) return null;
    final epoch = _epoch;
    final identity = _identityEpoch;
    return MenuProfileTarget(
      source: 'conversation',
      reference: row.ref,
      query: row.gameId,
      avatar: _inlineAvatar(row.avatar),
      isAccountCurrent: () => !_disposed && identity == _identityEpoch,
      isCurrent: () =>
          _current(epoch) &&
          ((_selectedKey == key && _selected?.ref == row.ref) ||
              _targets[key]?.ref == row.ref),
    );
  }

  @override
  void show(bool visible) {
    if (_disposed || visible == _visible) return;
    _visible = visible;
    _timer?.cancel();
    _timer = null;
    _clear();
    if (visible) {
      unawaited(_read());
      _timer = Timer.periodic(
        const Duration(seconds: 3),
        (_) => unawaited(_read(silent: true)),
      );
    }
  }

  void _cancel() {
    _receipting = false;
    _epoch++;
    _reading = false;
    _port.cancel();
  }

  void _clear() {
    _invitations?.closeFlow();
    _invitationView = null;
    _attachmentCodes.clear();
    _cancel();
    _receipting = false;
    _receipts.clear();
    _readRef = null;
    _readThrough = 0;
    _readStatus = '';
    _canSend = false;
    _permissionAt = null;
    _targets = {};
    _portraits.clear();
    _avatars.clear();
    _selected = null;
    _selectedKey = null;
    _before = _oldest = 0;
    _hasOlder = false;
    _emit({'state': _visible ? 'loading' : 'idle'});
  }

  @override
  void act(String action, String key) {
    if (_disposed || !_visible || _sending) return;
    if (action == 'clearLocal' && archive != null && _selected != null) {
      unawaited(_clearLocal(_selected!, _epoch));
      return;
    }
    final invitations = _invitations;
    if (invitations != null) {
      if (action == 'inviteAction') {
        invitations.act(key, '');
        return;
      }
      if (action == 'inviteClose') {
        invitations.closeFlow();
        _invitationView = null;
        _emit(_view);
        return;
      }
      if (action == 'inviteRecords') {
        invitations.openRecords();
        return;
      }
      if (action == 'attachment') {
        final code = _attachmentCodes[key];
        if (code != null && _permissionFresh) invitations.openAttachment(code);
        return;
      }
      if (action == 'inviteSend') {
        final target = _selected, identity = _identityEpoch;
        if (target != null) {
          invitations.openSend(
            target,
            () =>
                !_disposed &&
                _visible &&
                identity == _identityEpoch &&
                _selected?.ref == target.ref &&
                _canSend &&
                _permissionFresh &&
                !_sending,
          );
        }
        return;
      }
    }
    if (action == 'read') {
      final through = _receipts[key];
      if (through != null &&
          !_reading &&
          !_receipting &&
          _permissionFresh &&
          _selected != null &&
          _port is DirectReadReceiptPort &&
          (_port as DirectReadReceiptPort).supportsReadReceipts &&
          (_readRef != _selected!.ref || through > _readThrough)) {
        unawaited(_markRead(_selected!.ref, through, _epoch));
      }
      return;
    }
    if (action == 'select') {
      final target = _targets[key];
      if (target == null || _selectedKey == key) return;
      invitations?.closeFlow();
      _invitationView = null;
      _cancel();
      _selected = target;
      _selectedKey = key;
      _before = 0;
      _receipts.clear();
      _readStatus = '';
    } else if (action == 'back') {
      _clear();
    } else if (action == 'retry') {
      _cancel();
    } else if (action == 'older' &&
        !_reading &&
        _selected != null &&
        _hasOlder &&
        _oldest > 0) {
      _cancel();
      _before = _oldest;
    } else if (action == 'latest' && !_reading && _selected != null) {
      _cancel();
      _before = 0;
    } else {
      return;
    }
    _canSend = false;
    _permissionAt = null;
    final selected = _selected;
    final cached = selected == null
        ? null
        : _history[(_historyIdentity(selected), _before)];
    _emit(
      cached == null
          ? (_targets.isEmpty
                ? {'state': 'loading'}
                : {
                    'state': 'ready',
                    'notice': selected == null ? '' : '正在读取消息…',
                  })
          : {
              ...cached,
              'profileKey': _selectedKey,
              'pageKey': '$_selectedKey/$_before',
              'notice': '',
            },
    );
    unawaited(_read(silent: action == 'select' && cached != null));
  }

  Future<void> _read({bool silent = false}) async {
    if (_disposed || !_visible || _reading || _sending || _receipting) return;
    _reading = true;
    _silentRead = silent;
    if (_selected != null && !silent) _emit(_view);
    final epoch = _epoch, selected = _selected;
    try {
      final Map<String, Object?> view;
      if (selected == null) {
        final rows = await _bounded(_port.directory(), epoch);
        if (!_current(epoch)) return;
        if (rows.length > 5000) throw const DirectReadFailure('data_invalid');
        final previousKeys = {
          for (final entry in _targets.entries) entry.value.ref: entry.key,
        };
        final seen = <String>{};
        if (rows.any((row) => row.ref.isEmpty || !seen.add(row.ref))) {
          throw const DirectReadFailure('data_invalid');
        }
        // Same-account refresh retains focus for unchanged directory targets.
        // Removed targets lose their key; account/visibility changes clear all.
        _targets = {
          for (final row in rows) previousKeys[row.ref] ?? 'c${++_serial}': row,
        };
        // Bound decode work and wire size independently of directory length.
        // Remaining rows keep their readable initial avatar, not a missing row.
        final portraitRows = _targets.entries.take(16).toList();
        final portraits = await Future.wait(
          portraitRows.map((row) => _avatars.logo(row.value.avatar)),
        );
        if (!_current(epoch)) return;
        _portraits.clear();
        var portraitBytes = 0;
        for (final (i, row) in portraitRows.indexed) {
          final portrait = portraits[i];
          if (portrait == null || portraitBytes + portrait.length > 180000) {
            continue;
          }
          portraitBytes += portrait.length;
          _portraits[row.key] = portrait;
        }
        view = {
          'state': 'ready',
          'rows': [
            for (final row in _targets.entries)
              {
                'key': row.key,
                'name': _text(row.value.name, 128),
                'time': row.value.time.toUtc().toIso8601String(),
                'unread': row.value.unread,
                'request': row.value.request,
              },
          ],
        };
      } else {
        if (archive != null &&
            _before == 0 &&
            !_history.containsKey((_historyIdentity(selected), 0))) {
          try {
            final rows = await archive!
                .load('private', selected.ref)
                .timeout(const Duration(seconds: 2));
            if (!_current(epoch)) return;
            if (rows.isNotEmpty) {
              _silentRead = true;
              _emit({
                'state': 'ready',
                'name': selected.name,
                'avatar':
                    _portraits[_selectedKey] ?? _inlineAvatar(selected.avatar),
                'profileKey': _selectedKey,
                'pageKey': '$_selectedKey/0',
                'request': false,
                'hasOlder': false,
                'olderPage': false,
                'notice': '',
                'refreshing': false,
                'messages': [
                  for (final row in rows)
                    {
                      'incoming': row['self'] == false,
                      'text': row['text'],
                      'time': row['time'],
                      'attachment': row['attachment'],
                    },
                ],
              });
            }
          } on Object {
            if (!_current(epoch)) return;
            _emit({..._view, 'notice': '本机记录暂时无法读取，正在获取在线消息。'});
          }
        }
        final page = await _bounded(
          _port.history(selected.ref, before: _before),
          epoch,
        );
        if (!_current(epoch)) return;
        if (page.ref != selected.ref ||
            page.messages.length > 50 ||
            page.oldest < 0 ||
            (page.hasOlder && page.oldest <= 0)) {
          throw const DirectReadFailure('data_invalid');
        }
        _oldest = page.oldest;
        _hasOlder = page.hasOlder;
        _canSend =
            page.canSend &&
            const {
              'none',
              'friend',
              'accepted',
              'request_incoming',
              'request_outgoing',
            }.contains(page.state);
        _permissionAt = DateTime.now();
        _receipts.clear();
        final receiptKeys = <String, String>{};
        if (_port is DirectReadReceiptPort &&
            (_port as DirectReadReceiptPort).supportsReadReceipts) {
          for (var i = 0; i < page.messages.length; i++) {
            final message = page.messages[i];
            if (message.incoming &&
                message.sequence > 0 &&
                (_readRef != selected.ref || message.sequence > _readThrough)) {
              final key = 'r${++_receiptSerial}';
              _receipts[key] = message.sequence;
              receiptKeys['$i'] = key;
            }
          }
        }
        _draftFor(selected)?.observe(page.messages);
        _attachmentCodes.clear();
        final attachmentKeys = <int, String>{};
        if (_invitations?.supportsRead == true) {
          for (final (index, message) in page.messages.indexed) {
            final invitation = message.communityInvitation;
            if (invitation != null) {
              final key = 'i${++_attachmentSerial}';
              _attachmentCodes[key] = invitation.inviteCode;
              attachmentKeys[index] = key;
            }
          }
        }
        if (_before == 0 && _targets.containsKey(_selectedKey)) {
          final last = page.messages.lastOrNull;
          final updated = Conversation(
            selected.ref,
            selected.name,
            last == null ? selected.preview : last.text,
            last?.time ?? selected.time,
            _targets[_selectedKey]!.unread,
            page.state,
            avatar: selected.avatar,
            conversationKey: selected.conversationKey,
            gameId: selected.gameId,
          );
          _targets[_selectedKey!] = updated;
          _selected = updated;
        }
        view = {
          'state': 'ready',
          'notice': page.localHistoryUnavailable
              ? '消息已读取，但本机记录保存失败；重启后可能需要重新读取。'
              : '',
          'name': _text(selected.name, 128),
          'profileKey': _selectedKey,
          'pageKey': '$_selectedKey/$_before',
          'conversationState': page.state,
          'avatar':
              _portraits[_selectedKey] ?? await _avatars.logo(selected.avatar),
          'request':
              page.state == 'request_incoming' ||
              page.state == 'request_outgoing',
          'hasOlder': page.hasOlder,
          'olderPage': _before > 0,
          'receipts': receiptKeys,
          'messages': [
            for (final (index, message) in page.messages.indexed)
              {
                'attachmentKey': attachmentKeys[index],
                'incoming': message.incoming, 'text': _text(message.text, 4096),
                'time': message.time.toUtc().toIso8601String(),
                // No attachment targets, invitation codes, URLs or action grants.
                'attachment': message.attachment != null,
                'attachmentDetail': message.communityInvitation == null
                    ? ''
                    : _text(
                        '${message.communityInvitation!.title}\n${message.communityInvitation!.summary}',
                        512,
                      ),
              },
          ],
        };
      }
      if (_current(epoch)) {
        _reading = false;
        if (selected != null) {
          final display = {...view, 'receipts': <String, String>{}};
          display['messages'] = [
            for (final raw in view['messages'] as List)
              {...raw as Map<String, Object?>, 'attachmentKey': null},
          ];
          final key = (_historyIdentity(selected), _before);
          _history.remove(key);
          if (_history.length >= 48) _history.remove(_history.keys.first);
          _history[key] = display;
        }
        _emit(view);
      }
    } on Object catch (error) {
      if (!_current(epoch)) return;
      _reading = false;
      final restricted =
          error is DirectReadFailure &&
          const [
            'identity_unavailable',
            'forbidden',
            'target_changed',
          ].contains(error.code);
      if (!restricted &&
          error is DirectReadFailure &&
          error.code == 'unavailable' &&
          _selected != null &&
          _view['state'] == 'ready') {
        // An unavailable transport is not a permission denial. Existing grants
        // still expire after 30 seconds; the server rechecks every actual send.
        _receipts.clear();
        _emit({
          ..._view,
          'receipts': <String, String>{},
          'notice': silent ? '' : '消息刷新失败，当前显示上次内容。草稿已保留，请重新读取。',
        });
        return;
      }
      _targets = {};
      _history.clear();
      _invitations?.closeFlow();
      _invitationView = null;
      _attachmentCodes.clear();
      _selected = null;
      _selectedKey = null;
      _before = _oldest = 0;
      _hasOlder = false;
      _canSend = false;
      _permissionAt = null;
      _receipts.clear();
      _emit({
        'state':
            error is DirectReadFailure &&
                const [
                  'identity_unavailable',
                  'forbidden',
                  'target_changed',
                ].contains(error.code)
            ? 'restricted'
            : 'unavailable',
      });
    } finally {
      if (_current(epoch)) _reading = false;
    }
  }

  bool _current(int epoch) => !_disposed && _visible && epoch == _epoch;
  Future<void> _clearLocal(Conversation target, int epoch) async {
    try {
      await archive!.clear('private', target.ref);
      if (!_current(epoch)) return;
      _history.removeWhere((key, _) => key.$1 == _historyIdentity(target));
      _emit({..._view, 'notice': '本机会话记录已清除。在线消息未删除，后续读取可再次缓存。'});
    } on Object {
      if (_current(epoch)) _emit({..._view, 'notice': '本机记录未能清除，请重试。'});
    }
  }

  Future<void> _markRead(String ref, int through, int epoch) async {
    _receipting = true;
    _emit(_view);
    // Retire this batch even on failure: never loop retries for a visible frame.
    _receipts.clear();
    try {
      final receipt = await (_port as DirectReadReceiptPort)
          .markRead(ref, through)
          .timeout(const Duration(seconds: 10));
      if (!_current(epoch) || _selected?.ref != ref) return;
      if (receipt.through < through || receipt.unread < 0) {
        throw const FormatException();
      }
      _readRef = ref;
      _readThrough = receipt.through;
      _readStatus = '';
      for (final entry in _targets.entries.toList()) {
        final row = entry.value;
        if (row.ref != ref) continue;
        _targets[entry.key] = Conversation(
          row.ref,
          row.name,
          row.preview,
          row.time,
          receipt.unread,
          row.state,
          avatar: row.avatar,
          conversationKey: row.conversationKey,
          gameId: row.gameId,
        );
      }
    } on Object {
      // Receipt failure must not interrupt conversation or claim it was read.
      // A later authenticated poll may issue a new visible receipt token.
    } finally {
      if (_current(epoch)) {
        _receipting = false;
        _emit({..._view, 'receipts': <String, String>{}});
      }
    }
  }

  Future<T> _bounded<T>(Future<T> task, int epoch) => task.timeout(
    const Duration(seconds: 10),
    onTimeout: () {
      if (_current(epoch)) _port.cancel();
      throw const DirectReadFailure('unavailable');
    },
  );
  static String _text(String value, int limit) {
    final text = value.replaceAll(
      RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]'),
      '',
    );
    return text.length <= limit ? text : text.substring(0, limit);
  }

  static String? _inlineAvatar(String? value) =>
      value != null &&
          value.length <= 128 * 1024 &&
          (value.startsWith('data:image/png;base64,') ||
              value.startsWith('data:image/jpeg;base64,'))
      ? value
      : null;

  @override
  void dispose() {
    if (_disposed) return;
    show(false);
    _disposed = true;
    _drafts.clear();
    _history.clear();
    _avatars.dispose();
    _ownPhoto.dispose();
    _invitations?.dispose();
    _epoch++;
    unawaited(_subscription.cancel());
    unawaited(_port.close());
  }
}
