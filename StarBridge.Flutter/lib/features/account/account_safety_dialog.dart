import 'package:flutter/material.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';

import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'account_safety.dart';

Future<void> showAccountSafetyDialog(
  BuildContext context,
  AccountSafetyPort port,
) async {
  await showDialog<void>(
    context: context,
    builder: (_) => _AccountSafetyDialogScope(port: port),
  );
}

class _AccountSafetyDialogScope extends StatefulWidget {
  const _AccountSafetyDialogScope({required this.port});
  final AccountSafetyPort port;
  @override
  State<_AccountSafetyDialogScope> createState() =>
      _AccountSafetyDialogScopeState();
}

class _AccountSafetyDialogScopeState extends State<_AccountSafetyDialogScope> {
  late final controller = AccountSafetyController(widget.port);
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      AccountSafetyDialog(controller: controller);
}

class AccountSafetyDialog extends StatelessWidget {
  const AccountSafetyDialog({required this.controller, super.key});
  final AccountSafetyController controller;
  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    String t(String key) => accountSafetyText(context, key);
    String date(DateTime value) =>
        MaterialLocalizations.of(context).formatMediumDate(value.toLocal());
    Widget records(String title, List<AccountSafetyRecord> records) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        SizedBox(height: tokens.space.sm),
        if (records.isEmpty) Text(t('empty')),
        for (final record in records)
          Padding(
            padding: EdgeInsets.only(bottom: tokens.space.sm),
            child: StarBridgeSurface(
              role: SurfaceRole.panel,
              child: Padding(
                padding: EdgeInsets.all(tokens.space.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: tokens.space.sm,
                      children: [
                        Text(
                          t(record.type),
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        if (record.status != null) Text(t(record.status!)),
                        Text(date(record.createdAt)),
                      ],
                    ),
                    SizedBox(height: tokens.space.sm),
                    SelectableText(record.text),
                    if (record.outcome case final outcome?) ...[
                      SizedBox(height: tokens.space.sm),
                      SelectableText(outcome),
                    ],
                    if (record.expiresAt case final until?)
                      Text('${t('until')} ${date(until)}'),
                    if (record.status == null)
                      _AppealEditor(
                        key: ValueKey(
                          '${controller.identityRevision}:${record.id}',
                        ),
                        controller: controller,
                        record: record,
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
    return Dialog(
      key: const Key('account-safety-dialog'),
      insetPadding: const EdgeInsets.all(16),
      child: StarBridgeSurface(
        role: SurfaceRole.floating,
        child: SizedBox(
          width: 760,
          child: Padding(
            padding: EdgeInsets.all(tokens.space.lg),
            child: ListenableBuilder(
              listenable: controller,
              builder: (context, _) {
                final snapshot = controller.snapshot;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            t('title'),
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        IconButton(
                          tooltip: t('close'),
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const StarBridgeIcon(StarBridgeIconSemantic.windowClose),
                        ),
                      ],
                    ),
                    if (controller.busy && snapshot == null) ...[
                      const LinearProgressIndicator(),
                      SizedBox(height: tokens.space.sm),
                      Text(t('loading')),
                    ],
                    if (controller.failure case final failure?)
                      Padding(
                        padding: EdgeInsets.symmetric(
                          vertical: tokens.space.sm,
                        ),
                        child: Text(t(failure.name)),
                      ),
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (snapshot != null) ...[
                              Text(
                                snapshot.restrictions.isEmpty
                                    ? t('noRestrictions')
                                    : '${t('restrictions')} ${snapshot.restrictions.map(t).join(' · ')}',
                              ),
                              SizedBox(height: tokens.space.lg),
                              records(t('sanctions'), snapshot.sanctions),
                              SizedBox(height: tokens.space.lg),
                              records(t('appeals'), snapshot.appeals),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

String accountSafetyText(BuildContext context, String key) {
  final locale = Localizations.localeOf(context);
  final copy = _copy[key] ?? _copy['unknown']!;
  if (locale.languageCode == 'en') return copy.$3;
  if (locale.countryCode == 'TW' || locale.scriptCode == 'Hant') return copy.$2;
  return copy.$1;
}

const _copy = <String, (String, String, String)>{
  'appeal': ('提交申诉', '提交申訴', 'Submit appeal'),
  'reason': ('申诉理由', '申訴理由', 'Appeal reason'),
  'cancel': ('取消', '取消', 'Cancel'),
  'sending': ('正在提交…', '正在提交…', 'Submitting…'),
  'appealSubmitted': ('已提交申诉', '已提交申訴', 'Appeal submitted'),
  'appealRejected': (
    '未能提交，请检查理由或稍后再试。',
    '未能提交，請檢查理由或稍後再試。',
    'Could not submit. Check the reason or try again later.',
  ),
  'appealUnknown': (
    '暂未收到提交结果，正在自动核对。请勿重复提交。',
    '暫未收到提交結果，正在自動核對。請勿重複提交。',
    'Submission is not yet confirmed. Checking automatically; do not submit again.',
  ),
  'title': ('账号状态与申诉', '帳號狀態與申訴', 'Account status and appeals'),
  'close': ('关闭', '關閉', 'Close'),
  'loading': ('正在读取账号状态…', '正在讀取帳號狀態…', 'Loading account status…'),
  'empty': ('暂无记录', '暫無記錄', 'No records'),
  'noRestrictions': ('当前没有功能限制', '目前沒有功能限制', 'No current feature restrictions'),
  'restrictions': ('当前受限功能：', '目前受限功能：', 'Current restrictions:'),
  'sanctions': ('当前处置', '目前處置', 'Current actions'),
  'appeals': ('我的申诉', '我的申訴', 'My appeals'),
  'until': ('到期：', '到期：', 'Expires:'),
  'signedOut': (
    '登录后可查看账号状态。',
    '登入後可查看帳號狀態。',
    'Sign in to view your account status.',
  ),
  'forbidden': (
    '当前账号暂时无法查看这些资料。',
    '目前帳號暫時無法查看這些資料。',
    'These details are unavailable for this account.',
  ),
  'unavailable': (
    '当前客户端暂不支持读取账号状态。',
    '目前用戶端暫不支援讀取帳號狀態。',
    'Account status is unavailable in this client.',
  ),
  'invalid': (
    '账号资料暂时无法读取，正在自动重试。',
    '帳號資料暫時無法讀取，正在自動重試。',
    'Account details could not be read. Retrying automatically.',
  ),
  'connection': (
    '暂时无法更新，正在自动重试。',
    '暫時無法更新，正在自動重試。',
    'Unable to update. Retrying automatically.',
  ),
  'unknown': ('其他状态', '其他狀態', 'Other status'),
  'warning': ('警告', '警告', 'Warning'),
  'chat_mute': ('聊天', '聊天', 'Chat'),
  'social_restriction': ('社交', '社交', 'Social'),
  'account_restriction': ('账号', '帳號', 'Account'),
  'profile_restriction': ('个人资料', '個人資料', 'Profile'),
  'room_creation_restriction': ('创建房间', '建立房間', 'Room creation'),
  'room_participation_restriction': ('参与房间', '參與房間', 'Room participation'),
  'fleet_participation_restriction': (
    '参与组织',
    '參與組織',
    'Organization participation',
  ),
  'ship_media_upload_restriction': ('上传舰船图片', '上傳艦船圖片', 'Ship image uploads'),
  'submitted': ('已提交', '已提交', 'Submitted'),
  'reviewing': ('审核中', '審核中', 'Under review'),
  'accepted': ('已通过', '已通過', 'Accepted'),
  'denied': ('未通过', '未通過', 'Denied'),
};

class _AppealEditor extends StatefulWidget {
  const _AppealEditor({
    required this.controller,
    required this.record,
    super.key,
  });
  final AccountSafetyController controller;
  final AccountSafetyRecord record;
  @override
  State<_AppealEditor> createState() => _AppealEditorState();
}

class _AppealEditorState extends State<_AppealEditor> {
  final _details = TextEditingController();
  bool _editing = false;
  late final int _identity = widget.controller.identityRevision;
  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    String t(String key) => accountSafetyText(context, key);
    final controller = widget.controller;
    final id = widget.record.id;
    final existing =
        controller.snapshot?.appeals.any((a) => a.sanctionId == id) ?? false;
    final outcome = controller.appealOutcomes[id];
    if (existing ||
        outcome == AccountAppealOutcome.submitted ||
        outcome == AccountAppealOutcome.alreadySubmitted) {
      return Text(t('appealSubmitted'));
    }
    if (outcome == AccountAppealOutcome.unknown) {
      return Text(t('appealUnknown'));
    }
    if (!_editing) {
      return TextButton(
        onPressed: controller.canAppeal(id)
            ? () => setState(() => _editing = true)
            : null,
        child: Text(t('appeal')),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _details,
          maxLength: 2000,
          minLines: 3,
          maxLines: 6,
          enabled: !controller.submitting,
          decoration: InputDecoration(labelText: t('reason')),
          onChanged: (_) => setState(() {}),
        ),
        if (outcome == AccountAppealOutcome.rejected) Text(t('appealRejected')),
        Wrap(
          spacing: context.tokens.space.sm,
          children: [
            FilledButton(
              onPressed:
                  controller.canAppeal(id) && _details.text.trim().isNotEmpty
                  ? () => controller.submit(id, _details.text, _identity)
                  : null,
              child: Text(t(controller.submitting ? 'sending' : 'appeal')),
            ),
            TextButton(
              onPressed: controller.submitting
                  ? null
                  : () => setState(() => _editing = false),
              child: Text(t('cancel')),
            ),
          ],
        ),
      ],
    );
  }
}
