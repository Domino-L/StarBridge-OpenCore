import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../platform/window/native_viewport_visibility.dart';
import '../../design_system/controls/semantic_action_style.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'party_rooms_module.dart';
import 'room_action_dialogs.dart';
import 'room_management_actions.dart';
import 'room_invitation_dialog.dart';
import 'room_chat_panel.dart';
import 'room_directory_card.dart';
import 'room_members_panel.dart';
import 'room_feedback.dart';
import 'room_tag_catalog.dart';
import 'room_tag_picker.dart';
import 'room_filter_panel.dart';

class PartyRoomsPage extends StatefulWidget {
  const PartyRoomsPage({
    required this.module,
    this.openCommunityInvite,
    super.key,
  });
  final PartyRoomsModule module;
  final Future<void> Function(BuildContext, String)? openCommunityInvite;
  @override
  State<PartyRoomsPage> createState() => _PartyRoomsPageState();
}

class _PartyRoomsPageState extends State<PartyRoomsPage> {
  final _listScroll = ScrollController();
  bool _entered = false;
  final _query = TextEditingController();
  Set<String> _filterTags = {};
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Outgoing AnimatedSwitcher pages must stop marking messages read immediately.
    if (NativeViewportScope.isActive(context)) {
      _entered = true;
      scheduleMicrotask(() {
        if (mounted && _entered) widget.module.enter();
      });
    } else {
      _entered = false;
      widget.module.leave();
    }
  }

  @override
  void dispose() {
    if (_entered) widget.module.leave();
    _listScroll.dispose();
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.module,
    builder: (context, _) {
      final module = widget.module;
      String t(String key) => AppStrings.of(context).text('rooms.$key');
      final current = module.directory?.currentRoomId != null;
      return LayoutBuilder(
        builder: (context, constraints) {
          final wideFilters =
              !current &&
              module.state == RoomReadState.ready &&
              constraints.maxWidth - context.tokens.space.lg * 2 >= 1050;
          return Padding(
            padding: EdgeInsets.all(context.tokens.space.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        t(current ? 'current' : 'directory'),
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                    TextButton(
                      onPressed: module.busy
                          ? null
                          : () => module.refresh(foreground: true),
                      child: Text(t(module.manualRefreshing ? 'refreshing' : 'refresh')),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (!module.supportsCommands) ...[
                  Text(
                    t('readOnly'),
                    style: TextStyle(
                      color: context.tokens.colors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (module.supportsCommands) ...[
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (module.supportsInvitations)
                        OutlinedButton(
                          style: semanticActionStyle(
                            context,
                            ActionTone.info,
                            emphasis: ActionEmphasis.outlined,
                          ),
                          onPressed: module.canCommand
                              ? () => showRoomInvitations(context, module)
                              : null,
                          child: Text(
                            '${roomActionText(context, 'invitations')} · ${module.directory?.receivedInvitations.length ?? 0}',
                          ),
                        ),
                      if (module.supportsInvitations &&
                          current &&
                          module.selectedRoom?.viewerIsHost == true)
                        OutlinedButton(
                          onPressed: module.canInvite
                              ? () => showRoomInvitations(
                                  context,
                                  module,
                                  host: true,
                                )
                              : null,
                          child: Text(roomActionText(context, 'inviteFriends')),
                        ),
                      if (!current) ...[
                        FilledButton(
                          onPressed:
                              module.canCommand &&
                                  (module.directory?.tagOptions.isNotEmpty ??
                                      false)
                              ? () => createRoomDialog(context, module)
                              : null,
                          child: Text(roomActionText(context, 'create')),
                        ),
                        OutlinedButton(
                          onPressed: module.canCommand
                              ? () => joinRoomDialog(context, module)
                              : null,
                          child: Text(roomActionText(context, 'codeJoin')),
                        ),
                      ] else
                        OutlinedButton(
                          style: semanticActionStyle(
                            context,
                            roomLeaveTone(module.selectedRoom),
                            emphasis: ActionEmphasis.outlined,
                          ),
                          onPressed: module.canCommand
                              ? () => leaveRoomDialog(context, module)
                              : null,
                          child: Text(roomActionText(context, 'leave')),
                        ),
                      if (current &&
                          module.supportsManagement &&
                          module.selectedRoom?.viewerIsHost == true)
                        RoomManagementActions(module: module),
                    ],
                  ),
                  if (module.commandMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: RoomFeedback(module.commandMessage!),
                    ),
                  const SizedBox(height: 12),
                ],
                if (module.previewScene != null) ...[
                  Wrap(
                    spacing: 16,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        t('example.notice'),
                        style: TextStyle(color: context.tokens.colors.accent),
                      ),
                      SizedBox(
                        width: 230,
                        child: DropdownButtonFormField<String>(
                          key: ValueKey('rooms-example-${module.previewScene}'),
                          initialValue: module.previewScene,
                          decoration: InputDecoration(
                            labelText: t('example.scene'),
                          ),
                          items: [
                            for (final scene in [
                              'directory',
                              'current',
                              'host',
                              'empty',
                              'error',
                            ])
                              DropdownMenuItem(
                                value: scene,
                                child: Text(t('example.$scene')),
                              ),
                          ],
                          onChanged: module.busy
                              ? null
                              : (value) {
                                  if (value != null) {
                                    module.selectPreviewScene(value);
                                  }
                                },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
                if (!current && module.state == RoomReadState.ready)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            key: const Key('rooms-tag-search'),
                            controller: _query,
                            decoration: InputDecoration(
                              labelText: tagCopy(context, 'search'),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        if (!wideFilters) const SizedBox(width: 8),
                        if (!wideFilters)
                          OutlinedButton(
                            key: const Key('rooms-tag-filter'),
                            onPressed: () async {
                              final result = await showRoomTagPicker(
                                context,
                                options: module.directory!.tagOptions,
                                selected: _filterTags,
                                filter: true,
                              );
                              if (mounted && result != null) {
                                setState(() => _filterTags = result);
                              }
                            },
                            child: Text(
                              '${tagCopy(context, 'filter')}${_filterTags.isEmpty ? '' : ' · ${_filterTags.length}'}',
                            ),
                          ),
                        if (_filterTags.isNotEmpty || _query.text.isNotEmpty)
                          TextButton(
                            onPressed: () => setState(() {
                              _filterTags = {};
                              _query.clear();
                            }),
                            child: Text(tagCopy(context, 'clear')),
                          ),
                      ],
                    ),
                  ),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (wideFilters) ...[
                        SizedBox(
                          width: 290,
                          child: RoomFilterPanel(
                            key: const Key('rooms-persistent-filter'),
                            options: module.directory!.tagOptions,
                            selected: _filterTags,
                            onChanged: (value) =>
                                setState(() => _filterTags = value),
                          ),
                        ),
                        const SizedBox(width: 14),
                      ],
                      Expanded(
                        child: switch (module.state) {
                          RoomReadState.loading => Center(
                            child: Text(t('loading')),
                          ),
                          RoomReadState.signedOut => Center(
                            child: Text(t('signedOut')),
                          ),
                          RoomReadState.unavailable => Center(
                            child: Text(t('error.${module.failure}')),
                          ),
                          RoomReadState.ready => _workspace(
                            context,
                            current,
                            t,
                          ),
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );

  Widget _workspace(
    BuildContext context,
    bool current,
    String Function(String) t,
  ) {
    final module = widget.module;
    final rooms = module.directory!.rooms
        .where(
          (room) =>
              current || RoomTagCatalog.matches(room, _filterTags, _query.text),
        )
        .toList();
    if (rooms.isEmpty) {
      return Center(
        key: const Key('rooms-empty'),
        child: Text(
          _filterTags.isNotEmpty || _query.text.isNotEmpty
              ? tagCopy(context, 'noMatches')
              : t('empty'),
        ),
      );
    }
    if (!current) {
      return ListView.separated(
        key: const Key('rooms-directory'),
        controller: _listScroll,
        itemCount: rooms.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) => RoomDirectoryCard(
          room: rooms[index],
          serverTime: module.directory!.serverTime,
          selected: rooms[index].id == module.selectedRoomId,
          onSelect: module.writing ? null : () => module.select(rooms[index].id),
          onJoin: !module.canCommand
              ? null
              : () {
                  module.select(rooms[index].id);
                  joinRoomDialog(context, module, room: rooms[index]);
                },
          supportsCommands: module.supportsCommands,
        ),
      );
    }
    final members = RoomMembersPanel(
      key: ValueKey('members-${module.directory!.currentRoomId}'),
      room: module.selectedRoom!,
      serverTime: module.directory!.serverTime,
    );
    final chat = module.chat;
    if (chat == null || !chat.available) return members;
    final panel = RoomChatPanel(
      key: ValueKey('chat-${module.directory!.currentRoomId}'),
      module: chat,
      openCommunityInvite: widget.openCommunityInvite,
    );
    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth >= 850
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 3, child: members),
                const SizedBox(width: 12),
                Expanded(flex: 2, child: panel),
              ],
            )
          : Column(
              children: [
                Expanded(child: members),
                const SizedBox(height: 12),
                Expanded(child: panel),
              ],
            ),
    );
  }
}
