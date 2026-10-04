import '../../design_system/icons/standard_icon.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../common/user_avatar_menu.dart';
import '../direct_messages/communication_time_formatter.dart';
import 'community_announcements_controller.dart';
import 'community_announcements_copy.dart';
import 'community_announcements_port.dart';
import 'community_workspace_image.dart';

class CommunityAnnouncementDetails extends StatefulWidget {
  const CommunityAnnouncementDetails({
    required this.model,
    required this.entry,
    super.key,
  });
  final CommunityAnnouncementsController model;
  final CommunityAnnouncement entry;
  @override
  State<CommunityAnnouncementDetails> createState() =>
      _CommunityAnnouncementDetailsState();
}

class _CommunityAnnouncementDetailsState
    extends State<CommunityAnnouncementDetails> {
  Uint8List? author, editor;
  bool failed = false, loading = false;
  int epoch = 0;
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant CommunityAnnouncementDetails oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entry != widget.entry || oldWidget.model != widget.model) {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    final current = ++epoch;
    setState(() {
      loading = true;
      failed = false;
      author = editor = null;
    });
    try {
      final detail = await widget.model.detail(widget.entry);
      if (!mounted || current != epoch) return;
      setState(() {
        author = detail.authorAvatarImageData == null
            ? null
            : base64Decode(detail.authorAvatarImageData!.split(',').last);
        editor = detail.editorAvatarImageData == null
            ? null
            : base64Decode(detail.editorAvatarImageData!.split(',').last);
      });
    } catch (_) {
      if (mounted && current == epoch) setState(() => failed = true);
    } finally {
      if (mounted && current == epoch) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    epoch++;
    author = editor = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CommunityAnnouncementDetailsBody(
    entry: widget.entry,
    author: author,
    editor: editor,
    loading: loading,
    onRetry: failed ? _load : null,
    avatarBuilder: (person, bytes, child) => UserAvatarMenu(
      avatarBytes: bytes,
      target: person.memberRef == null
          ? null
          : UserTarget.community(
              widget.model.targetRef,
              person.memberRef!,
              query: person.gameId,
            ),
      name: person.gameId.isEmpty
          ? person.callsign
          : '${person.callsign} (${person.gameId})',
      child: child,
    ),
  );
}

/// Shared display only. Callers retain ownership of reads and avatar actions.
class CommunityAnnouncementDetailsBody extends StatelessWidget {
  const CommunityAnnouncementDetailsBody({
    super.key,
    required this.entry,
    this.author,
    this.editor,
    this.loading = false,
    this.onRetry,
    this.avatarBuilder,
  });
  final CommunityAnnouncement entry;
  final Uint8List? author, editor;
  final bool loading;
  final VoidCallback? onRetry;
  final Widget Function(CommunityAnnouncementAuthor, Uint8List?, Widget)?
  avatarBuilder;

  Widget _person(
    BuildContext context,
    String label,
    CommunityAnnouncementAuthor person,
    Uint8List? bytes,
  ) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(
      children: [
        _avatar(
          person,
          bytes,
          SizedBox(
            width: 40,
            height: 40,
            child: CommunityWorkspaceImage(
              bytes: bytes,
              loading: loading && person.hasAvatar && bytes == null,
              icon: StandardIconSemantic.person,
              maxWidth: 96,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(color: context.tokens.colors.textSecondary),
              ),
              Text(
                person.gameId.isEmpty
                    ? person.callsign
                    : '${person.callsign} (${person.gameId})',
              ),
              Text(
                person.roleTitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Color(
                    int.parse(person.roleColor.substring(1), radix: 16) |
                        0xff000000,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
  Widget _avatar(
    CommunityAnnouncementAuthor person,
    Uint8List? bytes,
    Widget child,
  ) => avatarBuilder?.call(person, bytes, child) ?? child;
  @override
  Widget build(BuildContext context) {
    final item = entry;
    String t(String key) => communityAnnouncementText(context, key);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t(item.state),
          style: TextStyle(
            color: item.state == 'published'
                ? context.tokens.colors.success
                : context.tokens.colors.warning,
          ),
        ),
        const SizedBox(height: 10),
        SelectableText(
          item.title,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        SelectableText(item.content.isEmpty ? t('emptyBody') : item.content),
        const Divider(height: 30),
        _person(context, t('author'), item.author, author),
        _person(context, t('editor'), item.editor, editor),
        if (loading) const LinearProgressIndicator(),
        if (onRetry != null)
          TextButton(onPressed: onRetry, child: Text(t('imageFailed'))),
        for (final (label, time) in [
          ('publishedAt', item.publishedAt),
          ('updatedAt', item.updatedAt),
          if (item.archivedAt != null) ('archivedAt', item.archivedAt!),
          if (item.withdrawnAt != null) ('withdrawnAt', item.withdrawnAt!),
        ])
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Tooltip(
              message: time.toLocal().toString(),
              child: Text(
                '${t(label)} · ${communicationTime(time, AppStrings.of(context).locale)}',
              ),
            ),
          ),
      ],
    );
  }
}
