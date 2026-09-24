import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import 'overlay_preview_identity.dart';
import 'overlay_workspace_models.dart';

/// Preview-only fixtures. Nothing here enters the workspace mutation or feed.
class OverlayPreviewModuleSurface extends StatelessWidget {
  const OverlayPreviewModuleSurface({
    required this.settings,
    required this.child,
    this.backgroundOpacity = 1,
    this.textOpacity = 1,
    this.decorationOpacity = 1,
    this.selected = false,
    this.visible = true,
    super.key,
  });

  final OverlayWorkspaceSettings settings;
  final Widget child;
  final double backgroundOpacity;
  final double textOpacity;
  final double decorationOpacity;
  final bool selected;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final accent = tokens.colors.accent;
    return Container(
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: tokens.surfaces.panel.fill.withValues(
          alpha: visible ? backgroundOpacity : 0.04,
        ),
        border: Border.all(
          color: accent.withValues(
            alpha: visible ? 0.65 * decorationOpacity : 0.25,
          ),
          width: 1,
        ),
      ),
      foregroundDecoration: selected
          ? BoxDecoration(border: Border.all(color: accent, width: 2))
          : null,
      child: Opacity(opacity: visible ? textOpacity : 0.4, child: child),
    );
  }
}

/// Uses the real overlay information hierarchy and spacing with fixed sample
/// values. Simulation changes only the data source, never the module shape.
class OverlayPreviewContent extends StatelessWidget {
  const OverlayPreviewContent({
    required this.moduleKey,
    required this.settings,
    required this.referenceSize,
    this.previewIdentity,
    this.simulate = false,
    super.key,
  });

  final String moduleKey;
  final OverlayWorkspaceSettings settings;
  final Size referenceSize;
  final OverlayPreviewIdentity? previewIdentity;
  final bool simulate;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    String copy(String key) => strings.text('overlay.sample.$key');
    String moduleTitle() =>
        moduleKey == 'Squads' && settings['scenePreference'] == 'PartyRoom'
        ? copy('room')
        : strings.text('overlay.workspace.module.$moduleKey');

    if (!simulate) {
      return Center(
        child: Text(
          moduleTitle(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }

    return KeyedSubtree(
      key: Key('overlay-simulated-structure-$moduleKey'),
      child: switch (moduleKey) {
        'Notice' => _NoticePreview(copy: copy, settings: settings),
        'Squads' => _FleetOverviewPreview(
          copy: copy,
          title: moduleTitle(),
          room: settings['scenePreference'] == 'PartyRoom',
        ),
        'Members' => _MembersPreview(
          copy: copy,
          title: moduleTitle(),
          settings: settings,
          referenceSize: referenceSize,
          previewIdentity: previewIdentity,
        ),
        'Chat' => _ChatPreview(
          copy: copy,
          title: moduleTitle(),
          settings: settings,
          referenceSize: referenceSize,
        ),
        'Events' => _EventPreview(copy: copy),
        _ => Center(child: Text(moduleTitle())),
      },
    );
  }
}

typedef _PreviewCopy = String Function(String key);

Text _previewText(
  BuildContext context,
  String value, {
  double size = 11,
  Color? color,
  FontWeight weight = FontWeight.normal,
  TextAlign textAlign = TextAlign.left,
  int maxLines = 1,
}) => Text(
  value,
  maxLines: maxLines,
  overflow: TextOverflow.ellipsis,
  textAlign: textAlign,
  style: TextStyle(
    color: color ?? context.tokens.colors.textPrimary,
    fontSize: size,
    fontWeight: weight,
    height: 1.12,
  ),
);

Widget _previewFittedText(
  BuildContext context,
  String value, {
  double size = 11,
}) => Align(
  alignment: AlignmentDirectional.centerStart,
  child: FittedBox(
    fit: BoxFit.scaleDown,
    alignment: AlignmentDirectional.centerStart,
    child: Text(
      value,
      maxLines: 1,
      softWrap: false,
      style: TextStyle(
        color: context.tokens.colors.textPrimary,
        fontSize: size,
        height: 1.12,
      ),
    ),
  ),
);

class _NoticePreview extends StatelessWidget {
  const _NoticePreview({required this.copy, required this.settings});

  final _PreviewCopy copy;
  final OverlayWorkspaceSettings settings;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final room = settings['scenePreference'] == 'PartyRoom';
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 7, 18, 7),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _previewText(
                  context,
                  room ? copy('roomCommunication') : copy('communication'),
                  size: 11.2,
                  color: tokens.colors.accent,
                  weight: FontWeight.w600,
                ),
                const SizedBox(height: 3),
                _previewText(
                  context,
                  room ? copy('roomReady') : copy('notice'),
                  size: 10.5,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 54,
            child: _previewText(
              context,
              '${settings['communicationEventDurationSeconds']}s',
              size: 11,
              color: tokens.colors.warning,
              weight: FontWeight.w600,
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

class _FleetOverviewPreview extends StatelessWidget {
  const _FleetOverviewPreview({
    required this.copy,
    required this.title,
    required this.room,
  });

  final _PreviewCopy copy;
  final String title;
  final bool room;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    Widget metric(
      String value, {
      Color? color,
      TextAlign align = TextAlign.left,
    }) => Expanded(
      child: _previewText(
        context,
        value,
        size: 11,
        color: color,
        weight: FontWeight.w600,
        textAlign: align,
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _previewText(
            context,
            title,
            size: 12,
            color: tokens.colors.accent,
            weight: FontWeight.w600,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              metric('${copy('online')} 3 / 4', color: tokens.colors.success),
              metric('${copy('inGame')} 2 / 3', align: TextAlign.center),
              metric(
                '${copy('usServer')} · 2${copy('peopleSuffix')}',
                align: TextAlign.right,
              ),
            ],
          ),
          const SizedBox(height: 7),
          _previewText(
            context,
            room
                ? copy('roomObjective')
                : '${copy('sameShard')} 2${copy('peopleSuffix')}',
            size: 10,
            color: tokens.colors.textSecondary,
          ),
          const SizedBox(height: 7),
          Row(
            children: [
              Expanded(child: _previewText(context, copy('orison'), size: 10)),
              _previewText(
                context,
                '${copy('atLocation')} 2 / 3',
                size: 10,
                color: tokens.colors.textSecondary,
                textAlign: TextAlign.right,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MembersPreview extends StatelessWidget {
  const _MembersPreview({
    required this.copy,
    required this.title,
    required this.settings,
    required this.referenceSize,
    required this.previewIdentity,
  });

  final _PreviewCopy copy;
  final String title;
  final OverlayWorkspaceSettings settings;
  final Size referenceSize;
  final OverlayPreviewIdentity? previewIdentity;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final identity = previewIdentity;
    var rows =
        <
              ({
                String callsign,
                String handle,
                String status,
                String location,
                String ship,
                bool self,
              })
            >[
              if (identity != null)
                (
                  callsign: identity.callSign,
                  handle: identity.gameHandle,
                  status: copy('appOnline'),
                  location: '${copy('locationLabel')}: ${copy('notInGame')}',
                  ship: '${copy('shipLabel')}: ${copy('notInGame')}',
                  self: true,
                ),
            ]
            .where((row) => !(settings['hideSelfMember'] == true && row.self))
            .toList();
    final availableRows = math.max(
      0,
      ((referenceSize.height - 44) / 35).floor(),
    );
    rows = rows.take(availableRows).toList(growable: false);
    final ratio = ((settings['memberNameColumnRatio']! as num).toDouble() * 100)
        .round();
    final hideStatus = settings['hideMemberOnlineStatus'] == true;

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _previewText(
            context,
            title,
            size: 12,
            color: tokens.colors.accent,
            weight: FontWeight.w600,
          ),
          const SizedBox(height: 8),
          for (final row in rows)
            SizedBox(
              height: 35,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        flex: ratio,
                        child: _previewFittedText(
                          context,
                          switch (settings['memberNameMode']) {
                            'CallsignOnly' => row.callsign,
                            'GameNameOnly' => row.handle,
                            _ =>
                              row.callsign.toLowerCase() ==
                                      row.handle.toLowerCase()
                                  ? row.handle
                                  : '${row.callsign} (${row.handle})',
                          },
                        ),
                      ),
                      if (!hideStatus)
                        SizedBox(
                          width: 40,
                          child: _previewText(
                            context,
                            row.status,
                            size: 9.5,
                            color: row.status == copy('offline')
                                ? tokens.colors.textSecondary
                                : tokens.colors.success,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      Expanded(
                        flex: 100 - ratio,
                        child: _previewText(
                          context,
                          row.location,
                          size: 9.5,
                          color: tokens.colors.textSecondary,
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  _previewText(
                    context,
                    row.ship,
                    size: 9.5,
                    color: tokens.colors.textSecondary,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ChatPreview extends StatelessWidget {
  const _ChatPreview({
    required this.copy,
    required this.title,
    required this.settings,
    required this.referenceSize,
  });

  final _PreviewCopy copy;
  final String title;
  final OverlayWorkspaceSettings settings;
  final Size referenceSize;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final maximumRows = math.max(1, ((referenceSize.height - 46) / 48).floor());
    final samples =
        <({String sender, String message, String time, bool self})>[
              (
                sender: copy('sender'),
                message: copy('chat1'),
                time: '21:14',
                self: false,
              ),
              (
                sender: copy('self'),
                message: copy('chat2'),
                time: '21:15',
                self: true,
              ),
            ]
            .where(
              (row) => !(settings['chatHideSelfMessages'] == true && row.self),
            )
            .take(maximumRows);

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 13, 18, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _previewText(
            context,
            title,
            size: 12,
            color: tokens.colors.accent,
            weight: FontWeight.w600,
          ),
          const SizedBox(height: 7),
          for (final sample in samples)
            SizedBox(
              height: 48,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 2,
                    margin: const EdgeInsets.only(top: 2, bottom: 8),
                    color: tokens.colors.accent.withValues(alpha: 0.78),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _previewText(
                                context,
                                settings['chatShowSender'] == true
                                    ? sample.sender
                                    : copy('communicationMessage'),
                                size: 10.5,
                                color: tokens.colors.accent,
                                weight: FontWeight.w600,
                              ),
                            ),
                            if (settings['chatShowTimestamp'] == true)
                              _previewText(
                                context,
                                sample.time,
                                size: 9,
                                color: tokens.colors.textSecondary,
                                textAlign: TextAlign.right,
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        _previewText(
                          context,
                          sample.message,
                          size: 10,
                          maxLines: 2,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _EventPreview extends StatelessWidget {
  const _EventPreview({required this.copy});

  final _PreviewCopy copy;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(width: 4, color: tokens.colors.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _previewText(
                        context,
                        copy('memberOnline'),
                        size: 11,
                        color: tokens.colors.accent,
                        weight: FontWeight.w600,
                      ),
                    ),
                    _previewText(
                      context,
                      '21:11',
                      size: 9,
                      color: tokens.colors.textSecondary,
                      textAlign: TextAlign.right,
                    ),
                  ],
                ),
                const SizedBox(height: 9),
                _previewText(
                  context,
                  copy('memberEnteredGame'),
                  size: 10,
                  maxLines: 2,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
