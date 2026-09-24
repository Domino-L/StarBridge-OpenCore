import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../../platform/bridge/bridge_client_session.dart';
import 'friend_sharing_controller.dart';
import 'privacy_page_drafts.dart';

class FriendSharingSetting extends StatefulWidget {
  const FriendSharingSetting({required this.session, super.key});
  final BridgeClientSession session;
  @override
  State<FriendSharingSetting> createState() => _FriendSharingSettingState();
}

class _FriendSharingSettingState extends State<FriendSharingSetting> {
  late final controller = FriendSharingController(widget.session);
  PrivacyPageDrafts? _drafts;
  String? _preparedOwner;

  @override
  void initState() {
    super.initState();
    controller.addListener(_prepareInitialDraft);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _drafts = PrivacyDraftScope.of(context);
    _prepareInitialDraft();
  }

  void _prepareInitialDraft() {
    final c = controller;
    final drafts = _drafts;
    final owner = c.accountKey;
    if (drafts == null ||
        owner == null ||
        _preparedOwner == owner ||
        !c.canEdit ||
        c.snapshot?['revision'] != 0) {
      return;
    }
    _preparedOwner = owner;
    final epoch = drafts.epoch;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          owner != c.accountKey ||
          drafts.epoch != epoch ||
          !c.canEdit ||
          c.snapshot?['revision'] != 0) {
        return;
      }
      // -1 distinguishes an absent preference from an explicitly saved OFF.
      drafts.edit('friend-fields', -1, 63, (next) async {
        if (owner != c.accountKey || !c.canEdit || c.snapshot?['revision'] != 0) {
          return false;
        }
        await c.saveFields(next);
        return c.error == null && c.fields == next;
      });
    });
  }

  @override
  void dispose() {
    controller.removeListener(_prepareInitialDraft);
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final strings = AppStrings.of(context), tokens = context.tokens;
      final c = controller;
      final drafts = PrivacyDraftScope.of(context);
      final fields = drafts?.value('friend-fields', c.fields) ?? c.fields;
      final revision = c.snapshot?['revision'];
      return Card(
        child: Padding(
          padding: EdgeInsets.all(tokens.space.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                strings.text('settings.privacy.friends.title'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(strings.text('settings.privacy.friends.description')),
              if (c.busy && c.snapshot == null) const LinearProgressIndicator(),
              Text(
                strings.text(
                  c.error != null
                      ? 'settings.privacy.friends.unavailable'
                      : c.snapshot == null
                      ? 'settings.privacy.loading'
                      : c.fields == 0
                      ? 'settings.privacy.friends.off'
                      : c.state == 'active'
                      ? 'settings.privacy.friends.active'
                      : 'settings.privacy.friends.savedPaused',
                ),
              ),
              for (final item in const {
                1: 'presence',
                2: 'serverRelation',
                4: 'serverDetails',
                8: 'ship',
                16: 'location',
                32: 'lastOnline',
              }.entries)
                SwitchListTile.adaptive(
                  key: Key('friend-sharing-${item.value}'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    strings.text('settings.privacy.field.${item.value}'),
                  ),
                  value: fields & item.key != 0,
                  onChanged: c.canEdit && !(drafts?.saving ?? false)
                      ? (value) {
                          if (drafts == null) {
                            c.change(item.key, value);
                            return;
                          }
                          drafts.edit(
                            'friend-fields',
                            revision == 0 ? -1 : c.fields,
                            value ? fields | item.key : fields & ~item.key,
                            (next) async {
                              if (c.fields == next &&
                                  c.error == null &&
                                  c.snapshot?['revision'] != 0) {
                                return true;
                              }
                              if (c.snapshot?['revision'] != revision) {
                                return false;
                              }
                              if (!c.canEdit) return false;
                              await c.saveFields(next);
                              return c.error == null && c.fields == next;
                            },
                          );
                        }
                      : null,
                ),
            ],
          ),
        ),
      );
    },
  );
}
