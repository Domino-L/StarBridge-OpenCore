import 'dart:math';

import 'package:flutter/material.dart';

import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../design_system/interaction/starbridge_field_frame.dart';
import 'local_hangar_copy.dart';
import 'local_hangar_port.dart';

/// Edits one local instance. An uncertain write is reconciled before any retry.
class LocalHangarPersonalDataEditor extends StatefulWidget {
  const LocalHangarPersonalDataEditor({
    required this.port,
    required this.snapshot,
    required this.ship,
    required this.isCurrent,
    super.key,
  });
  final LocalHangarPort port;
  final LocalHangarSnapshot snapshot;
  final LocalHangarShip ship;
  final bool Function() isCurrent;
  @override
  State<LocalHangarPersonalDataEditor> createState() => _EditorState();
}

class _EditorState extends State<LocalHangarPersonalDataEditor> {
  late final _nickname = TextEditingController(
    text: widget.ship.nickname ?? '',
  );
  late final _notes = TextEditingController(text: widget.ship.notes ?? '');
  final _form = GlobalKey<FormState>();
  bool _busy = false, _uncertain = false, _conflict = false;
  String? _error, _operationId, _submittedName, _submittedNotes;
  @override
  void dispose() {
    _nickname.dispose();
    _notes.dispose();
    super.dispose();
  }

  bool get _current => mounted && widget.isCurrent();
  String _pick(String cn, String tw, String en) =>
      LocalHangarCopy(context).pick(cn, tw, en);

  Future<void> _save() async {
    if (_busy || _conflict || !_current || !_form.currentState!.validate()) {
      return;
    }
    final port = widget.port as LocalHangarPersonalDataPort;
    if (!port.personalDataAvailable) return;
    _operationId ??= List.generate(
      16,
      (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    _submittedName ??= _nickname.text;
    _submittedNotes ??= _notes.text;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await port.savePersonalData(
        widget.ship.id,
        _submittedName,
        _submittedNotes,
        widget.snapshot.revision,
        operationId: _operationId!,
      );
      if (result.operationId != _operationId ||
          result.revision != widget.snapshot.revision + 1) {
        throw StateError('Unconfirmed local ship details receipt');
      }
      if (mounted && widget.isCurrent()) {
        dismissStarBridgeDialog(context, result: result);
      }
    } catch (error) {
      if (!mounted || !widget.isCurrent()) return;
      // Only explicit Host rejections are known not to have committed. Transport
      // failures require a read receipt, never a new blind write.
      final rejected =
          error is LocalHangarFailure &&
          const {
            'hangar.invalid_personal_data',
            'hangar.invalid_observation',
            'hangar.revision_conflict',
            'hangar.ship_unavailable',
            'hangar.unavailable',
            'hangar.account_changed',
          }.contains(error.code);
      setState(() {
        _conflict =
            error is LocalHangarFailure &&
            const {
              'hangar.revision_conflict',
              'hangar.ship_unavailable',
            }.contains(error.code);
        _uncertain = !rejected;
        _error = _conflict
            ? _pick(
                '机库已变化，请复制需要保留的内容，关闭后重新打开。',
                '機庫已變更，請複製需要保留的內容，關閉後重新開啟。',
                'Your hangar changed. Copy your draft, close this editor and reopen it.',
              )
            : _uncertain
            ? _pick(
                '尚未确认保存结果，请先查询。',
                '尚未確認儲存結果，請先查詢。',
                'Save outcome unknown. Check its status before retrying.',
              )
            : _pick(
                '未能保存，请检查输入或稍后重试。',
                '未能儲存，請檢查輸入或稍後重試。',
                'Could not save. Check your input or try again later.',
              );
        if (rejected && !_conflict) {
          _operationId = null;
          _submittedName = null;
          _submittedNotes = null;
        }
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _check() async {
    if (_busy || !_current) return;
    setState(() => _busy = true);
    try {
      final result = await (widget.port as LocalHangarPersonalDataPort)
          .readPersonalDataReceipt();
      if (!mounted || !widget.isCurrent()) return;
      if (result.operationId == _operationId &&
          result.revision == widget.snapshot.revision + 1) {
        dismissStarBridgeDialog(context, result: result);
      } else {
        setState(() {
          _conflict = result.revision != widget.snapshot.revision;
          _uncertain = _conflict;
          _error = _conflict
              ? _pick(
                  '机库已变化，请关闭后重新打开核对。',
                  '機庫已變更，請關閉後重新開啟核對。',
                  'Your hangar changed. Close and reopen to review it.',
                )
              : _pick(
                  '尚未保存，可以重试同一次提交。',
                  '尚未儲存，可以重試同一次提交。',
                  'Not saved yet. You can retry the same submission.',
                );
        });
      }
    } catch (_) {
      if (_current) {
        setState(
          () => _error = _pick(
            '暂时无法查询，请稍后再试。',
            '暫時無法查詢，請稍後再試。',
            'Could not check. Try again later.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final locked = _busy || _uncertain || _conflict || _operationId != null;
    Widget field({
      required TextEditingController controller,
      required String label,
      required String key,
      required int limit,
      int lines = 1,
    }) => StarBridgeFieldFrame(
      builder: (_, focus) => TextFormField(
        key: Key(key),
        controller: controller,
        focusNode: focus,
        readOnly: locked,
        maxLength: limit,
        minLines: lines,
        maxLines: lines == 1 ? 1 : 7,
        decoration: InputDecoration(labelText: label),
        validator: (value) => (value ?? '').characters.length > limit
            ? _pick('内容过长', '內容過長', 'Too long')
            : null,
      ),
    );
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text(_pick('编辑本艘资料', '編輯本艘資料', 'Edit your ship')),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Form(
              key: _form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _pick(
                      '昵称和备注仅保存在本机，不会随舰船共享到组织。',
                      '暱稱和備註僅儲存在本機，不會隨艦船共用到組織。',
                      'Nicknames and notes stay on this device and are not shared with your organization.',
                    ),
                  ),
                  const SizedBox(height: 16),
                  field(
                    controller: _nickname,
                    label: _pick(
                      '昵称（留空使用型号名称）',
                      '暱稱（留空使用型號名稱）',
                      'Nickname (blank uses model name)',
                    ),
                    key: 'hangar-nickname',
                    limit: 64,
                  ),
                  const SizedBox(height: 12),
                  field(
                    controller: _notes,
                    label: _pick('备注', '備註', 'Notes'),
                    key: 'hangar-notes',
                    limit: 2000,
                    lines: 3,
                  ),
                  if (_error != null)
                    Semantics(liveRegion: true, child: Text(_error!)),
                ],
              ),
            ),
          ),
        ),
        actions: [
          StarBridgeActionButton(
            kind: StarBridgeActionKind.quiet,
            controlKey: const Key('hangar-personal-cancel'),
            onActivate: _busy
                ? null
                : (source) => dismissStarBridgeDialog(context, source: source),
            child: Text(_pick('取消', '取消', 'Cancel')),
          ),
          StarBridgeActionButton(
            kind: StarBridgeActionKind.primary,
            controlKey: const Key('hangar-personal-save'),
            onActivate: _busy || _conflict
                ? null
                : (_) => _uncertain ? _check() : _save(),
            child: Text(
              _busy
                  ? _pick('处理中…', '處理中…', 'Working…')
                  : _uncertain
                  ? _pick('查询保存结果', '查詢儲存結果', 'Check save status')
                  : _pick('保存', '儲存', 'Save'),
            ),
          ),
        ],
      ),
    );
  }
}
