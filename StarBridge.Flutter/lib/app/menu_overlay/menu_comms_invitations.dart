
import 'menu_overlay_text.dart';
import 'menu_overlay_locale.dart';
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
    super.locale,
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

  Object inviteText(String key) => MenuOverlayComputed(
    (strings) =>
        menuOverlayRecord(strings.locale, communityInviteCopy[key]) ??
        strings.text('menu.overlay.errors.retry'),
  );
  Object sendText(String key) => MenuOverlayComputed(
    (strings) =>
        menuOverlayRecord(strings.locale, invitationSendCopy[key]) ??
        strings.text('menu.overlay.errors.retry'),
  );

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
      actions.add(
        button(
          MenuOverlayText('menu.overlay.comms.reloadInvites'),
          (_) => sender.load(),
        ),
      );
    }
    if (_records || sender.activeOperationId != null) {
      for (final item in sender.items.take(128)) {
        rows.add({
          'title': '${item.sourceName} → ${item.destinationName}',
          'detail': MenuOverlayJoin([
            item.requestedAt.toLocal(),
            sendText(item.phase),
          ], ' · '),
          'buttons': [
            if (item.phase != 'sent') ...[
              button(
                MenuOverlayText('menu.overlay.comms.checkInvite'),
                (_) => sender.recover(item.operationId),
              ),
              if ({'prepared', 'generating', 'ready'}.contains(item.phase))
                button(
                  MenuOverlayText('menu.overlay.comms.continueInvite'),
                  (_) => sender.recover(
                    item.operationId,
                    action: InvitationRecoveryAction.continueSending,
                  ),
                  confirm: MenuOverlayText(
                    'menu.overlay.comms.continueInviteConfirm',
                    {
                      'recipient': item.destinationName,
                      'organization': item.sourceName,
                    },
                  ),
                ),
              if (item.phase == 'sending')
                button(
                  MenuOverlayText('menu.overlay.comms.retryDelivery'),
                  (_) => sender.recover(
                    item.operationId,
                    action: InvitationRecoveryAction.retryDelivery,
                    retryConfirmed: true,
                  ),
                  confirm: MenuOverlayText(
                    'menu.overlay.comms.retryDeliveryConfirm',
                  ),
                ),
            ],
          ],
        });
      }
      actions.add(
        button(
          MenuOverlayText('menu.overlay.comms.refreshInvites'),
          (_) => sender.load(),
        ),
      );
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
                MenuOverlayText('menu.overlay.comms.sendInvite'),
                (_) async {
                  if (_canSend?.call() != true) throw StateError('retired');
                  await sender.start(
                    organizationRef: row.targetRef,
                    channel: 'private',
                    destinationRef: _recipient!.ref,
                    maxUses: 1,
                  );
                },
                confirm: MenuOverlayText(
                  'menu.overlay.comms.sendInviteConfirm',
                  {'recipient': _recipient!.name, 'organization': row.name},
                ),
              ),
          ],
        });
      }
      if (directory.next != null) {
        actions.add(
          button(MenuOverlayText('menu.overlay.comms.moreOrganizations'), (
            _,
          ) async {
            _after = directory.next;
          }),
        );
      }
      if (_after != null) {
        actions.add(
          button(MenuOverlayText('menu.overlay.comms.firstOrganizations'), (
            _,
          ) async {
            _after = null;
          }),
        );
      }
    }
    return {
      'title': _records
          ? MenuOverlayText('menu.overlay.comms.inviteHistory')
          : MenuOverlayText('menu.overlay.comms.inviteTitle', {
              'name': _recipient?.name ?? "",
            }),
      'notice': MenuOverlayJoin([
        if (progress != null) sendText(progress.status),
        if (sender.error != null) sendText(sender.error!),
        if (!_records && sender.activeOperationId == null) sendText('sendInfo'),
        if (!_records && _canSend?.call() != true)
          MenuOverlayText('menu.overlay.comms.invitePermissionExpired'),
      ], '\n'),
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
      actions.add(
        button(
          MenuOverlayText('menu.overlay.comms.verifyInvite'),
          (_) => model.verify(_code!),
        ),
      );
    }
    if (preview != null) {
      rows.add({
        'title': preview.name,
        'detail': MenuOverlayJoin([
          MenuOverlayText('menu.overlay.comms.inviteOwnerCount', {
            'owner': preview.commander,
            'count': preview.memberCount,
          }),
          MenuOverlayText('menu.overlay.comms.inviteExpiry', {
            'expiry':
                preview.expiresAt?.toLocal() ??
                const MenuOverlayText('menu.overlay.comms.neverExpires'),
          }),
          MenuOverlayText('menu.overlay.comms.inviteUses', {
            'count': preview.remainingUses < 0
                ? const MenuOverlayText('menu.overlay.comms.unlimited')
                : preview.remainingUses,
          }),
          inviteText(
            preview.alreadyMember
                ? 'already'
                : preview.membershipConflict
                ? 'membershipConflict'
                : 'direct',
          ),
        ]),
      });
      if (!preview.alreadyMember &&
          !preview.membershipConflict &&
          !model.expired &&
          model.outcome == null) {
        if (!model.sharing) {
          actions.add(
            button(
              MenuOverlayText('menu.overlay.comms.reviewSharing'),
              (_) => model.reviewSharing(),
              role: 'reviewSharing',
            ),
          );
        }
        final draft = model.draft;
        if (model.sharing && draft != null) {
          void toggle(
            Object label,
            bool enabled,
            void Function() change, {
            String role = 'toggleSharing',
          }) {
            rows.add({
              'title': label,
              'detail': enabled
                  ? MenuOverlayText('menu.overlay.comms.enabled')
                  : MenuOverlayText('menu.overlay.comms.disabled'),
              'buttons': [
                button(
                  enabled
                      ? MenuOverlayText('menu.overlay.comms.disable')
                      : MenuOverlayText('menu.overlay.comms.enable'),
                  (_) async {
                    change();
                  },
                  role: role,
                ),
              ],
            });
          }

          rows.add({
            'title': MenuOverlayText('menu.overlay.comms.sharingBeforeJoin'),
            'detail': MenuOverlayJoin([
              inviteText('scopeWarning'),
              inviteText('publicationWarning'),
            ], '\n'),
          });
          toggle(
            MenuOverlayText('menu.overlay.comms.liveSharing'),
            draft.publicationEnabled,
            () => model.edit(
              draft.copyWith(publicationEnabled: !draft.publicationEnabled),
            ),
            role: 'togglePublication',
          );
          if (draft.publicationEnabled) {
            toggle(
              MenuOverlayText('menu.overlay.comms.allMembers'),
              draft.fleetAllMembersCanView,
              () => model.edit(
                draft.copyWith(
                  fleetAllMembersCanView: !draft.fleetAllMembersCanView,
                ),
              ),
            );
            if (!draft.fleetAllMembersCanView) {
              toggle(
                MenuOverlayText('menu.overlay.comms.admins'),
                draft.fleetAdministratorsCanView,
                () => model.edit(
                  draft.copyWith(
                    fleetAdministratorsCanView:
                        !draft.fleetAdministratorsCanView,
                  ),
                ),
              );
            }
            for (final entry in {
              1: MenuOverlayText('menu.overlay.comms.onlineStatus'),
              2: MenuOverlayText('menu.display.shipLabel'),
              4: MenuOverlayText('menu.overlay.comms.currentLocation'),
              8: MenuOverlayText('menu.overlay.comms.serverInfo'),
              16: MenuOverlayText('menu.overlay.comms.events'),
              32: MenuOverlayText('menu.overlay.comms.hangar'),
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
            'title': MenuOverlayText('menu.overlay.comms.groups'),
            'detail': MenuOverlayText('menu.overlay.comms.keepGroups', {
              'count': draft.fleetVisibilityGroupIds.length,
            }),
          });
          actions.add(
            button(
              model.acknowledged
                  ? MenuOverlayText('menu.overlay.comms.unacknowledge')
                  : MenuOverlayText('menu.overlay.comms.acknowledge'),
              (_) async {
                model.acknowledge(!model.acknowledged);
              },
              role: 'acknowledgeSharing',
            ),
          );
          if (model.canJoin) {
            actions.add(
              button(
                MenuOverlayText('menu.overlay.comms.saveJoin'),
                (_) => model.join(),
                confirm: MenuOverlayText('menu.overlay.comms.saveJoinConfirm', {
                  'name': preview.name,
                }),
                role: 'joinOrganization',
              ),
            );
          }
        }
      }
    }
    if (model.error == 'privacySaveFailed' ||
        model.error == 'privacyUnavailable') {
      actions.add(
        button(
          MenuOverlayText('menu.overlay.comms.reloadSharing'),
          (_) => model.reviewSharing(),
        ),
      );
    }
    return {
      'title': MenuOverlayText('menu.overlay.comms.organizationInvite'),
      'rows': rows,
      'buttons': actions,
      'notice': MenuOverlayJoin([
        if (model.expired) inviteText('inviteInvalid'),
        if (model.error != null) inviteText(model.error!),
        if (model.savedChoices) inviteText('savedChoices'),
        if (model.outcome?.status == 'accepted')
          MenuOverlayText('menu.overlay.comms.joinedOrganization'),
        if (model.outcome?.status == 'unknown') inviteText('outcomeUnknown'),
      ], '\n'),
    };
  }
}
