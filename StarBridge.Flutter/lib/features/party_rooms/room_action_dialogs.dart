import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/controls/semantic_action_style.dart';
import 'party_rooms_module.dart';
import 'room_commands.dart';
import 'room_feedback.dart';
import 'room_tag_catalog.dart';
import 'room_tag_picker.dart';
import 'room_tag_colors.dart';

String roomActionText(BuildContext context, String key) =>
    AppStrings.of(context).text('rooms.action.$key');

Future<void> createRoomDialog(BuildContext context, PartyRoomsModule module) =>
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CreateRoomDialog(module: module),
    );

Future<void> editRoomDialog(
  BuildContext context,
  PartyRoomsModule module,
) async {
  if (!module.canManage) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) =>
        _CreateRoomDialog(module: module, initialRoom: module.selectedRoom),
  );
}

Future<void> joinRoomDialog(
  BuildContext context,
  PartyRoomsModule module, {
  PartyRoom? room,
}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _JoinRoomDialog(module: module, initialRoom: room),
);

Future<void> leaveRoomDialog(
  BuildContext context,
  PartyRoomsModule module,
) async {
  final room = module.selectedRoom;
  final revision = module.contextRevision;
  if (room == null) return;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(roomActionText(context, 'leave')),
      content: Text(
        roomActionText(
          context,
          room.viewerIsHost ? 'leaveHostHint' : 'leaveHint',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(roomActionText(context, 'cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          style: semanticActionStyle(
            context,
            roomLeaveTone(room),
            emphasis: ActionEmphasis.filled,
          ),
          child: Text(roomActionText(context, 'leave')),
        ),
      ],
    ),
  );
  if (confirmed == true) {
    await module.execute(
      RoomCommand(RoomOperation.leave, {'roomId': room.id}),
      expectedRevision: revision,
    );
  }
}

class _CreateRoomDialog extends StatefulWidget {
  const _CreateRoomDialog({required this.module, this.initialRoom});
  final PartyRoomsModule module;
  final PartyRoom? initialRoom;
  @override
  State<_CreateRoomDialog> createState() => _CreateRoomDialogState();
}

class _CreateRoomDialogState extends State<_CreateRoomDialog> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController(),
      _goal = TextEditingController(),
      _password = TextEditingController();
  late final int _revision = widget.module.contextRevision;
  late final List<RoomTag> _options = widget.module.directory?.tagOptions ?? [];
  final _tags = <String>{};
  int _capacity = 6, _hours = 6, _minutes = 0;
  bool _public = true, _passwordEnabled = false, _submitting = false;
  String _eligibility = 'everyone',
      _admission = 'direct',
      _voice = 'recommended',
      _language = 'zh';
  String? _error;
  bool get _editing => widget.initialRoom != null;
  @override
  void initState() {
    super.initState();
    final room = widget.initialRoom;
    if (room == null) return;
    _title.text = room.title;
    _goal.text = room.goal;
    _capacity = room.capacity;
    _public = room.isPublic;
    _eligibility = room.eligibility;
    _admission = room.admissionMode;
    _voice = room.voice;
    _language = room.language;
    _passwordEnabled = room.passwordRequired;
    _tags.addAll(room.tags.map((tag) => RoomTagCatalog.normalize(tag.id)));
    final now = widget.module.directory!.serverTime;
    int closest(List<int> options, int requested) => options.reduce(
      (a, b) => (a - requested).abs() <= (b - requested).abs() ? a : b,
    );
    _hours = closest([
      1,
      2,
      4,
      6,
      12,
      24,
    ], (room.expiresAt.difference(now).inSeconds / 3600).ceil().clamp(1, 24));
    _minutes = room.recruitmentClosesAt == null
        ? 0
        : closest(
            [30, 60, 120, 240],
            (room.recruitmentClosesAt!.difference(now).inSeconds / 60)
                .ceil()
                .clamp(1, 1440),
          );
  }

  @override
  void dispose() {
    _title.dispose();
    _goal.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final gameplay = _options
        .where((tag) => tag.isGameplay && _tags.contains(tag.id))
        .toList();
    final extra = _options
        .where((tag) => !tag.isGameplay && _tags.contains(tag.id))
        .toList();
    if (gameplay.isEmpty ||
        gameplay.length > 3 ||
        extra.length > 3 ||
        _tags.length > 5) {
      setState(() => _error = 'tagsRequired');
      return;
    }
    if (_minutes > _hours * 60) {
      setState(() => _error = 'durationInvalid');
      return;
    }
    if (_editing &&
        _capacity < (widget.module.selectedRoom?.members.length ?? 0)) {
      setState(() => _error = 'capacityTooSmall');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    final result = await widget.module.execute(
      RoomCommand(_editing ? RoomOperation.update : RoomOperation.create, {
        if (_editing) 'roomId': widget.initialRoom!.id,
        'title': _title.text.trim(),
        'goal': _goal.text.trim(),
        'capacity': _capacity,
        'isPublic': _public,
        'eligibility': _eligibility,
        'admissionMode': _admission,
        if (!_editing) 'passwordEnabled': _passwordEnabled,
        if (_editing)
          'passwordMode': !_passwordEnabled
              ? 'remove'
              : _password.text.trim().isEmpty
              ? 'keep'
              : 'replace',
        'password': _passwordEnabled ? _password.text.trim() : '',
        'voiceRequirement': _voice,
        'language': _language,
        'autoDisbandHours': _hours,
        'recruitmentDurationMinutes': _minutes == 0 ? null : _minutes,
        'gameplayTagNodeIds': gameplay.map((tag) => tag.id).toList(),
        'contextTagIds': extra.map((tag) => tag.id).toList(),
      }),
      expectedRevision: _revision,
    );
    if (!mounted) return;
    if (result.accepted) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _submitting = false;
      _error = result.error ?? 'rejected';
    });
  }

  @override
  Widget build(BuildContext context) {
    String t(String key) => roomActionText(context, key);
    String field(String key) => AppStrings.of(context).text('rooms.$key');
    Widget choice(
      String label,
      String value,
      List<String> values,
      void Function(String) update,
    ) => DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: field(label)),
      items: values
          .map(
            (item) => DropdownMenuItem(
              value: item,
              child: Text(field('$label.$item')),
            ),
          )
          .toList(),
      onChanged: (value) {
        if (value != null) setState(() => update(value));
      },
    );
    return PopScope(
      canPop: !_submitting,
      child: AlertDialog(
        title: Text(t(_editing ? 'edit' : 'create')),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Form(
              key: _form,
              child: AbsorbPointer(
                absorbing: _submitting,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      key: const Key('room-create-title'),
                      controller: _title,
                      maxLength: 32,
                      decoration: InputDecoration(labelText: t('title')),
                      validator: (value) => (value?.trim().length ?? 0) < 2
                          ? t('titleInvalid')
                          : null,
                    ),
                    TextFormField(
                      key: const Key('room-create-goal'),
                      controller: _goal,
                      maxLength: 120,
                      maxLines: 2,
                      decoration: InputDecoration(labelText: t('goal')),
                    ),
                    DropdownButtonFormField<int>(
                      initialValue: _capacity,
                      decoration: InputDecoration(labelText: t('capacity')),
                      items: [
                        for (var n = 2; n <= 16; n++)
                          DropdownMenuItem(value: n, child: Text('$n')),
                      ],
                      onChanged: (n) => setState(() => _capacity = n!),
                    ),
                    const SizedBox(height: 12),
                    choice('admission', _admission, [
                      'direct',
                      'approval',
                    ], (v) => _admission = v),
                    const SizedBox(height: 12),
                    choice('eligibility', _eligibility, [
                      'everyone',
                      'friends',
                      'fleet',
                      'invite',
                    ], (v) => _eligibility = v),
                    const SizedBox(height: 12),
                    choice('voice', _voice, [
                      'none',
                      'recommended',
                      'required',
                    ], (v) => _voice = v),
                    const SizedBox(height: 12),
                    choice('language', _language, [
                      'zh',
                      'en',
                      'bilingual',
                    ], (v) => _language = v),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(field('public')),
                      value: _public,
                      onChanged: (v) => setState(() => _public = v),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(t('passwordEnabled')),
                      value: _passwordEnabled,
                      onChanged: (v) => setState(() => _passwordEnabled = v),
                    ),
                    if (_passwordEnabled)
                      TextFormField(
                        controller: _password,
                        obscureText: true,
                        maxLength: 32,
                        decoration: InputDecoration(
                          labelText: field('password'),
                        ),
                        validator: (value) =>
                            _editing &&
                                widget.initialRoom!.passwordRequired &&
                                (value?.trim().isEmpty ?? true)
                            ? null
                            : (value?.trim().length ?? 0) < 4
                            ? t('passwordInvalid')
                            : null,
                      ),
                    if (_editing &&
                        widget.initialRoom!.passwordRequired &&
                        _passwordEnabled)
                      Text(t('keepPasswordHint')),
                    if (_editing) Text(t('resetDurationHint')),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      initialValue: _hours,
                      decoration: InputDecoration(labelText: t('disband')),
                      items: [
                        for (final n in [1, 2, 4, 6, 12, 24])
                          DropdownMenuItem(
                            value: n,
                            child: Text('$n ${t('hours')}'),
                          ),
                      ],
                      onChanged: (n) => setState(() => _hours = n!),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      initialValue: _minutes,
                      decoration: InputDecoration(
                        labelText: t('recruitmentDuration'),
                      ),
                      items: [
                        for (final n in [0, 30, 60, 120, 240])
                          DropdownMenuItem(
                            value: n,
                            child: Text(
                              n == 0 ? t('unlimited') : '$n ${t('minutes')}',
                            ),
                          ),
                      ],
                      onChanged: (n) => setState(() => _minutes = n!),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(child: Text(t('tagsRequired'))),
                        OutlinedButton(
                          key: const Key('room-choose-tags'),
                          onPressed: () async {
                            final result = await showRoomTagPicker(
                              context,
                              options: _options,
                              selected: _tags,
                            );
                            if (!mounted || result == null) return;
                            setState(() {
                              _tags
                                ..clear()
                                ..addAll(result);
                            });
                          },
                          child: Text(tagCopy(context, 'choose')),
                        ),
                      ],
                    ),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final tag in RoomTagCatalog.ordered(
                          _options.where((tag) => _tags.contains(tag.id)),
                        ))
                          InputChip(
                            label: Text(RoomTagCatalog.fullText(tag)),
                            backgroundColor: roomTagColors(
                              context,
                              tag.id,
                            ).soft,
                            labelStyle: TextStyle(
                              color: roomTagColors(context, tag.id).foreground,
                            ),
                            onDeleted: () =>
                                setState(() => _tags.remove(tag.id)),
                          ),
                      ],
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: RoomFeedback(_error!),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _submitting ? null : () => Navigator.pop(context),
            child: Text(t('cancel')),
          ),
          FilledButton(
            onPressed: _submitting || !widget.module.canCommand
                ? null
                : _submit,
            child: Text(
              t(
                _submitting
                    ? 'working'
                    : _editing
                    ? 'save'
                    : 'create',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _JoinRoomDialog extends StatefulWidget {
  const _JoinRoomDialog({required this.module, this.initialRoom});
  final PartyRoomsModule module;
  final PartyRoom? initialRoom;
  @override
  State<_JoinRoomDialog> createState() => _JoinRoomDialogState();
}

class _JoinRoomDialogState extends State<_JoinRoomDialog> {
  final _code = TextEditingController(), _password = TextEditingController();
  late final int _revision = widget.module.contextRevision;
  late PartyRoom? _room = widget.initialRoom;
  bool _working = false;
  String? _error;
  @override
  void dispose() {
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_room == null && _code.text.trim().isEmpty) {
      setState(() => _error = 'codeRequired');
      return;
    }
    setState(() {
      _working = true;
      _error = null;
    });
    final result = await widget.module.execute(
      _room == null
          ? RoomCommand(RoomOperation.resolve, {'roomCode': _code.text.trim()})
          : RoomCommand(RoomOperation.join, {
              'roomId': _room!.id,
              'password': _password.text.trim(),
            }),
      expectedRevision: _revision,
    );
    if (!mounted) return;
    if (result.preview != null) {
      setState(() {
        _room = result.preview;
        _working = false;
      });
      return;
    }
    if (result.accepted) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _working = false;
      _error = result.error ?? 'rejected';
    });
  }

  @override
  Widget build(BuildContext context) {
    String t(String key) => roomActionText(context, key);
    return PopScope(
      canPop: !_working,
      child: AlertDialog(
        title: Text(t(_room == null ? 'codeJoin' : 'join')),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_room == null)
                TextField(
                  controller: _code,
                  maxLength: 32,
                  enabled: !_working,
                  decoration: InputDecoration(labelText: t('code')),
                )
              else ...[
                Text(_room!.title),
                const SizedBox(height: 12),
                Text(
                  t(
                    _room!.admissionMode == 'approval'
                        ? 'approvalHint'
                        : 'joinHint',
                  ),
                ),
                if (_room!.passwordRequired)
                  TextField(
                    controller: _password,
                    obscureText: true,
                    maxLength: 32,
                    decoration: InputDecoration(
                      labelText: AppStrings.of(context).text('rooms.password'),
                    ),
                    enabled: !_working,
                  ),
              ],
              if (_error != null) RoomFeedback(_error!),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _working ? null : () => Navigator.pop(context),
            child: Text(t('cancel')),
          ),
          FilledButton(
            onPressed: _working || !widget.module.canCommand ? null : _submit,
            child: Text(
              t(
                _working
                    ? 'working'
                    : _room == null
                    ? 'resolve'
                    : _room!.admissionMode == 'approval'
                    ? 'apply'
                    : 'join',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
