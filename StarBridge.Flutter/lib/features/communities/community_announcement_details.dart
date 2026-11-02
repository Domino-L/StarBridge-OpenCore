import '../../design_system/icons/standard_icon.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_tooltip.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/interaction/starbridge_interaction_theme.dart';
import '../common/user_avatar_menu.dart';
import '../common/organization_member_actions.dart';
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
  InteractionSource _readSource = InteractionSource.programmatic;
  int epoch = 0;
  final Object _authorSurfaceOwner = Object();
  Object? _requestedAuthor, _requestedEditor;
  bool _detailScheduled = false;
  CommunityAnnouncementDetail? _loadedDetail;
  void _authorChanged() {
    final detail = _loadedDetail;
    if (mounted &&
        widget.model.usesOfficialAuthorProjection &&
        detail != null) {
      final keepAuthor = widget.model.detailPersonIsCurrent(
        widget.entry,
        _authorSurfaceOwner,
        detail,
      );
      final keepEditor = widget.model.detailPersonIsCurrent(
        widget.entry,
        _authorSurfaceOwner,
        detail,
        editor: true,
      );
      if (!keepAuthor) author = null;
      if (!keepEditor) editor = null;
      // This listener runs before the existing AnimatedBuilder publication.
      // Retain the other person's bytes, but release each retired local URI.
      _loadedDetail = CommunityAnnouncementDetail.withoutPeople(
        detail,
        author: !keepAuthor,
        editor: !keepEditor,
      );
    }
    _queueOfficialDetail();
  }

  void _queueOfficialDetail() {
    if (!mounted ||
        !widget.model.usesOfficialAuthorProjection ||
        loading ||
        _detailScheduled) {
      return;
    }
    final keys = widget.model.announcementDetailIdentityKeys(
      widget.entry,
      _authorSurfaceOwner,
    );
    if (!(keys.author != null && keys.author != _requestedAuthor) &&
        !(keys.editor != null && keys.editor != _requestedEditor)) {
      return;
    }
    _detailScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _detailScheduled = false;
      if (!mounted || loading) return;
      final current = widget.model.announcementDetailIdentityKeys(
        widget.entry,
        _authorSurfaceOwner,
      );
      if (current.author != null && current.author != _requestedAuthor ||
          current.editor != null && current.editor != _requestedEditor) {
        unawaited(_load());
      }
    });
  }

  void _beginAuthorSurface() {
    final model = widget.model;
    final surfaceEpoch = model.beginAuthorSurface(
      _authorSurfaceOwner,
      widget.entry,
    );
    if (surfaceEpoch == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !identical(model, widget.model)) return;
      unawaited(model.refreshAuthorSurface(_authorSurfaceOwner, surfaceEpoch));
    });
  }

  @override
  void initState() {
    super.initState();
    widget.model.addListener(_authorChanged);
    _beginAuthorSurface();
    if (!widget.model.usesOfficialAuthorProjection) unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant CommunityAnnouncementDetails oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entry != widget.entry || oldWidget.model != widget.model) {
      if (oldWidget.model != widget.model) {
        oldWidget.model.removeListener(_authorChanged);
        oldWidget.model.endAuthorSurface(_authorSurfaceOwner);
        widget.model.addListener(_authorChanged);
      }
      _beginAuthorSurface();
      if (widget.model.usesOfficialAuthorProjection) {
        ++epoch;
        loading = failed = false;
        author = editor = null;
        _loadedDetail = null;
        _requestedAuthor = _requestedEditor = null;
        _queueOfficialDetail();
      } else {
        unawaited(_load());
      }
    }
  }

  Future<void> _load([
    InteractionSource source = InteractionSource.programmatic,
  ]) async {
    final official = widget.model.usesOfficialAuthorProjection;
    if (official) {
      final keys = widget.model.announcementDetailIdentityKeys(
        widget.entry,
        _authorSurfaceOwner,
      );
      if (keys.author == null && keys.editor == null) return;
      if (keys.author != null) _requestedAuthor = keys.author;
      if (keys.editor != null) _requestedEditor = keys.editor;
    }
    final current = ++epoch;
    setState(() {
      loading = true;
      _readSource = source;
      failed = false;
      author = editor = null;
    });
    try {
      var detail = await widget.model.detail(
        widget.entry,
        authorSurfaceOwner: _authorSurfaceOwner,
      );
      if (!mounted || current != epoch) return;
      if (official) {
        // A retirement can occur between the controller completion and this
        // Widget continuation. Recheck independently before storing any bytes.
        detail = CommunityAnnouncementDetail.withoutPeople(
          detail,
          author: !widget.model.detailPersonIsCurrent(
            widget.entry,
            _authorSurfaceOwner,
            detail,
          ),
          editor: !widget.model.detailPersonIsCurrent(
            widget.entry,
            _authorSurfaceOwner,
            detail,
            editor: true,
          ),
        );
      }
      setState(() {
        _loadedDetail = detail;
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
      if (mounted && current == epoch) {
        setState(() => loading = false);
        if (official) _queueOfficialDetail();
      }
    }
  }

  @override
  void dispose() {
    epoch++;
    widget.model.removeListener(_authorChanged);
    widget.model.endAuthorSurface(_authorSurfaceOwner);
    author = editor = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.model,
    builder: (context, _) {
      final entry = widget.model.presentAnnouncement(
        widget.entry,
        _authorSurfaceOwner,
      );
      final detail = _loadedDetail;
      final legacyPixelsAllowed = !widget.model.usesOfficialAuthorProjection;
      final authorAllowed =
          legacyPixelsAllowed ||
          detail != null &&
              widget.model.detailPersonIsCurrent(
                widget.entry,
                _authorSurfaceOwner,
                detail,
              );
      final editorAllowed =
          legacyPixelsAllowed ||
          detail != null &&
              widget.model.detailPersonIsCurrent(
                widget.entry,
                _authorSurfaceOwner,
                detail,
                editor: true,
              );
      return CommunityAnnouncementDetailsBody(
        entry: entry,
        author: authorAllowed ? author : null,
        editor: editorAllowed ? editor : null,
        loading: loading,
        loadingSource: _readSource,
        onRetryActivate: failed ? _load : null,
        avatarBuilder: (person, bytes, child) => UserAvatarMenu(
          avatarBytes: bytes,
          target:
              person.memberRef == null ||
                  !organizationMemberActionsAvailable(widget.model.port)
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
    },
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
    this.onRetryActivate,
    this.retryEnabled = true,
    this.loadingSource = InteractionSource.programmatic,
    this.avatarBuilder,
  });
  final CommunityAnnouncement entry;
  final Uint8List? author, editor;
  final bool loading;
  final VoidCallback? onRetry;
  final ValueChanged<InteractionSource>? onRetryActivate;
  final bool retryEnabled;
  final InteractionSource loadingSource;
  final Widget Function(CommunityAnnouncementAuthor, Uint8List?, Widget)?
  avatarBuilder;

  Widget _wait(BuildContext context, Widget child) {
    final data = resolveStarBridgeInteraction(context);
    final source = resolveStarBridgeInitialReadSource(context, loadingSource);
    return InteractionScope(
      data: data.copyWith(
        reduceMotion: data.reduceMotion || source != InteractionSource.pointer,
      ),
      child: child,
    );
  }

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
            child: _wait(
              context,
              CommunityWorkspaceImage(
                bytes: bytes,
                loading: loading && person.hasAvatar && bytes == null,
                icon: StandardIconSemantic.person,
                maxWidth: 96,
              ),
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
        if (loading)
          _wait(
            context,
            SizedBox(
              width: double.infinity,
              child: SuiteProgressBar(
                key: const Key('announcement-detail-progress'),
                value: null,
                phase: ProgressPhase.running,
                semanticLabel: t('loading'),
              ),
            ),
          ),
        if (onRetry != null || onRetryActivate != null)
          StarBridgeActionButton(
            controlKey: const Key('announcement-detail-retry'),
            kind: StarBridgeActionKind.quiet,
            onActivate: !retryEnabled
                ? null
                : (source) {
                    if (onRetryActivate case final retry?) {
                      retry(source);
                    } else {
                      onRetry!();
                    }
                  },
            child: Text(t('imageFailed')),
          ),
        for (final (label, time) in [
          ('publishedAt', item.publishedAt),
          ('updatedAt', item.updatedAt),
          if (item.archivedAt != null) ('archivedAt', item.archivedAt!),
          if (item.withdrawnAt != null) ('withdrawnAt', item.withdrawnAt!),
        ])
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: StarBridgeTooltip(
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
