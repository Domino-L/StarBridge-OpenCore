import '../../features/communities/communities_module.dart';
import '../../features/communities/community_admission_controller.dart';
import '../../features/communities/community_invite_port.dart';
import '../../features/communities/community_invite_copy.dart';
import '../../features/communities/community_invitation_send_controller.dart';
import '../../features/communities/community_invitation_send_port.dart';
import '../../features/communities/community_invitation_send_copy.dart';
import '../../features/settings/local_privacy_port.dart';
import '../../features/direct_messages/direct_messages_module.dart';
import 'menu_feature_session.dart';

/// Existing admission/outbox owners, presented through one short-lived menu
/// lease. Invite codes, account references and delivery IDs never leave it.
final class MenuCommsInvitations extends MenuFeatureSession {
  MenuCommsInvitations(
    this.port,
    void Function(Map<String, Object?>) publish, {
    this.createPrivacy,
  }) : super(publish, port.invalidations);
  final CommunitiesPort port;
  final LocalPrivacyPort Function()? createPrivacy;
  CommunityAdmissionController? _admission;
  CommunityInvitationSendController? _sender;
  Conversation? _recipient;
  bool Function()? _canSend;
  String? _code, _after;
  bool _records = false;
  bool get opened => visible;
  bool get supportsSend =>
      port is CommunityInvitationSendPort &&
      (port as CommunityInvitationSendPort).invitationSendingAvailable;
  bool get supportsRead => port is CommunityInvitePort;

  void openAttachment(String code) {
    closeFlow();
    if (!supportsRead) return;
    _code = code;
    _admission = CommunityAdmissionController(
      port as CommunityInvitePort,
      createPrivacy?.call(),
    );
    show(true);
  }

  void openSend(Conversation recipient, bool Function() canSend) {
    closeFlow();
    if (!supportsSend || !canSend()) return;
    _recipient = recipient;
    _canSend = canSend;
    _sender = CommunityInvitationSendController(
      port as CommunityInvitationSendPort,
    );
    show(true);
  }

  void openRecords() {
    closeFlow();
    if (!supportsSend) return;
    _records = true;
    _sender = CommunityInvitationSendController(
      port as CommunityInvitationSendPort,
    );
    show(true);
  }

  void closeFlow() {
    show(false);
    reset();
  }

  @override
  void reset() {
    changeScope();
    _admission?.dispose();
    _sender?.dispose();
    _admission = null;
    _sender = null;
    _recipient = null;
    _canSend = null;
    _code = _after = null;
    _records = false;
  }

  @override
  Future<void> closePort() {
    reset();
    return port.close();
  }

  String inviteText(String key) =>
      communityInviteCopy[key]?.$1 ?? '暂时无法完成，请刷新后重试。';
  String sendText(String key) =>
      invitationSendCopy[key]?.$1 ?? '暂时无法完成，请刷新后重试。';

  @override
  Future<Map<String, Object?>> read() async {
    final epoch = generation;
    final admission = _admission;
    if (admission != null) return _readAdmission(admission);
    final sender = _sender;
    if (sender == null || sender.invalidated) throw StateError('retired');
    if (!sender.loaded) await sender.load();
    if (sender.invalidated || !current(epoch) || _sender != sender) {
      throw StateError('retired');
    }
    final actions = <Map<String, Object?>>[];
    final rows = <Map<String, Object?>>[];
    final progress = sender.progress;
    if (sender.error != null) {
      actions.add(button('重新读取发送记录', (_) => sender.load()));
    }
    if (_records || sender.activeOperationId != null) {
      for (final item in sender.items.take(128)) {
        rows.add({
          'title': '${item.sourceName} → ${item.destinationName}',
          'detail': '${item.requestedAt.toLocal()} · ${sendText(item.phase)}',
          'buttons': [
            if (item.phase != 'sent') ...[
              button('核对发送结果', (_) => sender.recover(item.operationId)),
              if ({'prepared', 'generating', 'ready'}.contains(item.phase))
                button(
                  '继续发送',
                  (_) => sender.recover(
                    item.operationId,
                    action: InvitationRecoveryAction.continueSending,
                  ),
                  confirm:
                      '继续向 ${item.destinationName} 发送 ${item.sourceName} 的邀请？',
                ),
              if (item.phase == 'sending')
                button(
                  '重试投递',
                  (_) => sender.recover(
                    item.operationId,
                    action: InvitationRecoveryAction.retryDelivery,
                    retryConfirmed: true,
                  ),
                  confirm: '请先核对聊天记录；只有确认未收到邀请后才重试投递。',
                ),
            ],
          ],
        });
      }
      actions.add(button('刷新发送记录', (_) => sender.load()));
    } else {
      final directory = await port.read(view: 'mine', query: '', after: _after);
      if (!current(epoch)) throw StateError('retired');
      for (final row in directory.items.where(
        (r) => {'member', 'owner'}.contains(r.relationship),
      )) {
        rows.add({
          'title': row.name,
          'detail': row.description,
          'buttons': [
            if (sender.canStart && _canSend?.call() == true)
              button(
                '发送此组织邀请',
                (_) async {
                  if (_canSend?.call() != true) throw StateError('retired');
                  await sender.start(
                    organizationRef: row.targetRef,
                    channel: 'private',
                    destinationRef: _recipient!.ref,
                    maxUses: 1,
                  );
                },
                confirm:
                    '向 ${_recipient!.name} 发送 ${row.name} 的邀请？有效期 7 天，可使用 1 次。',
              ),
          ],
        });
      }
      if (directory.next != null) {
        actions.add(
          button('更多组织', (_) async {
            _after = directory.next;
          }),
        );
      }
      if (_after != null) {
        actions.add(
          button('返回首批组织', (_) async {
            _after = null;
          }),
        );
      }
    }
    return {
      'title': _records ? '邀请发送记录' : '邀请 ${_recipient?.name ?? ""} 加入组织',
      'notice': [
        if (progress != null) sendText(progress.status),
        if (sender.error != null) sendText(sender.error!),
        if (!_records && sender.activeOperationId == null) sendText('sendInfo'),
        if (!_records && _canSend?.call() != true) '会话权限已过期，请返回聊天并刷新后再发送。',
      ].join('\n'),
      'rows': rows,
      'buttons': actions,
    };
  }

  Future<Map<String, Object?>> _readAdmission(
    CommunityAdmissionController model,
  ) async {
    final epoch = generation;
    if (model.invalidated) throw StateError('retired');
    if (model.preview == null && model.error == null) {
      await model.verify(_code!);
    }
    if (model.invalidated || _admission != model || !current(epoch)) {
      throw StateError('retired');
    }
    final preview = model.preview;
    final actions = <Map<String, Object?>>[];
    final rows = <Map<String, Object?>>[];
    if (model.outcome == null && !model.sharing) {
      actions.add(button('重新验证邀请', (_) => model.verify(_code!)));
    }
    if (preview != null) {
      rows.add({
        'title': preview.name,
        'detail':
            '负责人：${preview.commander}\n成员：${preview.memberCount}\n'
            '有效期：${preview.expiresAt?.toLocal() ?? "长期有效"}\n'
            '剩余次数：${preview.remainingUses < 0 ? "不限" : preview.remainingUses}\n'
            '${inviteText(preview.alreadyMember
                ? "already"
                : preview.membershipConflict
                ? "membershipConflict"
                : "direct")}',
      });
      if (!preview.alreadyMember &&
          !preview.membershipConflict &&
          !model.expired &&
          model.outcome == null) {
        if (!model.sharing) {
          actions.add(button('确认共享设置', (_) => model.reviewSharing()));
        }
        final draft = model.draft;
        if (model.sharing && draft != null) {
          void toggle(String label, bool enabled, void Function() change) {
            rows.add({
              'title': label,
              'detail': enabled ? '已开启' : '已关闭',
              'buttons': [
                button(enabled ? '关闭' : '开启', (_) async {
                  change();
                }),
              ],
            });
          }

          rows.add({
            'title': '加入前确认共享设置',
            'detail':
                '${inviteText("scopeWarning")}\n${inviteText("publicationWarning")}',
          });
          toggle(
            '实时状态共享',
            draft.publicationEnabled,
            () => model.edit(
              draft.copyWith(publicationEnabled: !draft.publicationEnabled),
            ),
          );
          if (draft.publicationEnabled) {
            toggle(
              '所有成员可见',
              draft.fleetAllMembersCanView,
              () => model.edit(
                draft.copyWith(
                  fleetAllMembersCanView: !draft.fleetAllMembersCanView,
                ),
              ),
            );
            if (!draft.fleetAllMembersCanView) {
              toggle(
                '组织管理员可见',
                draft.fleetAdministratorsCanView,
                () => model.edit(
                  draft.copyWith(
                    fleetAdministratorsCanView:
                        !draft.fleetAdministratorsCanView,
                  ),
                ),
              );
            }
            for (final entry in const {
              1: '在线状态',
              2: '当前飞船',
              4: '当前位置',
              8: '服务器信息',
              16: '活动事件',
              32: '个人机库',
            }.entries) {
              toggle(
                entry.value,
                draft.fleetFields & entry.key != 0,
                () => model.edit(
                  draft.copyWith(fleetFields: draft.fleetFields ^ entry.key),
                ),
              );
            }
          }
          rows.add({
            'title': '成员分组',
            'detail': '保留已选的 ${draft.fleetVisibilityGroupIds.length} 个分组。',
          });
          actions.add(
            button(model.acknowledged ? '取消确认' : '我已确认共享选择', (_) async {
              model.acknowledge(!model.acknowledged);
            }),
          );
          if (model.canJoin) {
            actions.add(
              button(
                '保存选择并加入',
                (_) => model.join(),
                confirm: '保存当前共享选择并加入 ${preview.name}？',
              ),
            );
          }
        }
      }
    }
    if (model.error == 'privacySaveFailed' ||
        model.error == 'privacyUnavailable') {
      actions.add(button('重新读取共享设置', (_) => model.reviewSharing()));
    }
    return {
      'title': '组织邀请',
      'rows': rows,
      'buttons': actions,
      'notice': [
        if (model.expired) inviteText('inviteInvalid'),
        if (model.error != null) inviteText(model.error!),
        if (model.savedChoices) inviteText('savedChoices'),
        if (model.outcome?.status == 'accepted') '已加入组织。',
        if (model.outcome?.status == 'unknown') inviteText('outcomeUnknown'),
      ].join('\n'),
    };
  }
}
