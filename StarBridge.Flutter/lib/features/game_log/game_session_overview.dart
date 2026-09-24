import 'package:flutter/material.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../account/account_models.dart';
import 'game_log_controller.dart';

class GameSessionOverview extends StatelessWidget {
  const GameSessionOverview({this.controller, super.key});

  final GameLogController? controller;

  @override
  Widget build(BuildContext context) {
    final source = controller;
    if (source == null) {
      return const _GameSessionOverviewBody(
        value: GameLogView(visible: true, error: 'unsupported'),
      );
    }
    return ValueListenableBuilder<GameLogView>(
      valueListenable: source,
      builder: (context, value, _) => _GameSessionOverviewBody(
        value: value,
        blockedMessage: switch (source.account.value.sessionState) {
          AccountSessionState.signedOut ||
          AccountSessionState.reauthorizationRequired => 'sessionSignIn',
          AccountSessionState.credentialTemporarilyUnavailable ||
          AccountSessionState.legacyUnavailable => 'sessionAccountUnavailable',
          _ => null,
        },
      ),
    );
  }
}

class _GameSessionOverviewBody extends StatelessWidget {
  const _GameSessionOverviewBody({required this.value, this.blockedMessage});

  final GameLogView value;
  final String? blockedMessage;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final tokens = context.tokens;
    final locale = Localizations.localeOf(context);
    String text(String key) => strings.text('gameLog.$key');

    if (blockedMessage case final message?) {
      return StarBridgeSurface(
        key: const Key('game-session-overview'),
        role: SurfaceRole.status,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              text('sessionTitle'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            SizedBox(height: tokens.space.sm),
            Text(text(message)),
          ],
        ),
      );
    }

    final gameStatus = _gameStatus(text);
    final active = value.visible && value.state == 'identified';
    final needsAttention = value.error != null || value.match == 'mismatch';
    final statusColor = active
        ? tokens.colors.success
        : needsAttention
        ? tokens.colors.warning
        : tokens.colors.textSecondary;
    final version = _version(text);
    final identity = _identity(text);
    final server = _server(text);
    final serverArea = _serverArea(text);
    final location = _location(text, locale);
    final ship = _ship(text, locale);
    final facts = [
      _SessionFactData(
        keyName: 'state',
        label: text('sessionState'),
        value: gameStatus,
        color: statusColor,
      ),
      _SessionFactData(
        keyName: 'version',
        label: text('sessionVersion'),
        value: version,
        color: value.verifiedChannels.contains(value.channel)
            ? tokens.colors.accent
            : tokens.colors.textSecondary,
      ),
      _SessionFactData(
        keyName: 'identity',
        label: text('sessionIdentity'),
        value: identity,
        color: value.match == 'match'
            ? tokens.colors.success
            : value.match == 'mismatch'
            ? tokens.colors.warning
            : tokens.colors.textSecondary,
      ),
      _SessionFactData(
        keyName: 'server',
        label: text('server'),
        value: server,
        color: value.serverState == 'connected'
            ? tokens.colors.success
            : tokens.colors.textSecondary,
      ),
      _SessionFactData(
        keyName: 'server-area',
        label: text('serverArea'),
        value: serverArea,
        color: value.serverState == 'connected' && value.serverShard != null
            ? tokens.colors.accent
            : tokens.colors.textSecondary,
      ),
      _SessionFactData(
        keyName: 'location',
        label: text('location'),
        value: location,
        color: value.locationState == 'confirmed'
            ? tokens.colors.accent
            : tokens.colors.textSecondary,
      ),
      _SessionFactData(
        keyName: 'ship',
        label: text('ship'),
        value: ship,
        color: value.shipState == 'confirmed'
            ? tokens.colors.accent
            : tokens.colors.textSecondary,
      ),
    ];

    return StarBridgeSurface(
      key: const Key('game-session-overview'),
      role: SurfaceRole.status,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final heading = Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: tokens.density.controlHeight,
                    height: tokens.density.controlHeight,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      border: Border.all(
                        color: statusColor.withValues(alpha: 0.55),
                        width: tokens.stroke.hairline,
                      ),
                      borderRadius: tokens.shape.small,
                    ),
                    child: StarBridgeIcon(
                      StarBridgeIconSemantic.statusGame,
                      size: tokens.icons.medium,
                      color: statusColor,
                    ),
                  ),
                  SizedBox(width: tokens.space.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          text('sessionTitle'),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        SizedBox(height: tokens.space.xxs),
                        Text(
                          text('sessionDescription'),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: tokens.colors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              );
              final badge = _SessionStateBadge(
                value: gameStatus,
                color: statusColor,
              );
              if (constraints.maxWidth < 560) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    heading,
                    SizedBox(height: tokens.space.sm),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: badge,
                    ),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: heading),
                  SizedBox(width: tokens.space.sm),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 180),
                    child: badge,
                  ),
                ],
              );
            },
          ),
          SizedBox(height: tokens.space.lg),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 900
                  ? 3
                  : constraints.maxWidth >= 500
                  ? 2
                  : 1;
              final gap = tokens.space.md;
              final itemWidth =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: tokens.space.md,
                children: [
                  for (final fact in facts)
                    SizedBox(
                      width: itemWidth,
                      child: _SessionFact(fact: fact),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  String _gameStatus(String Function(String key) text) {
    if (!value.visible) return text('sessionLoading');
    if (value.error != null) return text('sessionUnavailable');
    return switch (value.state) {
      'identified' => text('sessionPlaying'),
      'notRunning' => text('sessionNotRunning'),
      'stopped' => text('sessionStopped'),
      'reading' || 'waiting' => text('sessionDetecting'),
      'notSelected' => text('sessionNotConfigured'),
      'unknown' => text('sessionDetecting'),
      _ => text('sessionNeedsAttention'),
    };
  }

  String _version(String Function(String key) text) {
    final known =
        value.path != null || value.verifiedChannels.contains(value.channel);
    if (!known) return text('versionUnknown');
    final label = const {'LIVE', 'PTU'}.contains(value.channel)
        ? text(value.channel)
        : value.channel;
    final state = value.verifiedChannels.contains(value.channel)
        ? text('versionConfirmed')
        : text('versionUnconfirmed');
    return '$label · $state';
  }

  String _identity(String Function(String key) text) {
    final handle = value.handle;
    if (handle == null || handle.trim().isEmpty) {
      return text('identityWaiting');
    }
    return switch (value.match) {
      'match' => '$handle · ${text('identityMatched')}',
      'mismatch' => '$handle · ${text('identityMismatch')}',
      _ => '$handle · ${text('identityWaiting')}',
    };
  }

  String _server(String Function(String key) text) =>
      switch (value.serverState) {
        'connected' when value.serverRegion != null => text(
          'region${value.serverRegion!}',
        ),
        'connected' => text('serverConnected'),
        'notConnected' => text('serverNotConnected'),
        _ => text('serverUnknown'),
      };

  String _serverArea(String Function(String key) text) =>
      switch (value.serverState) {
        'connected' when value.serverShard != null => value.serverShard!,
        'connected' => text('serverAreaUnknown'),
        'notConnected' => text('serverNotConnected'),
        _ => text('serverAreaUnknown'),
      };

  String _location(String Function(String key) text, Locale locale) {
    final name =
        value.locationDisplayName(locale.languageCode, locale.countryCode) ??
        text('locationUnknown');
    return switch (value.locationState) {
      'confirmed' => '$name · ${text('locationConfirmed')}',
      'likely' => '$name · ${text('locationLikely')}',
      'possible' => '$name · ${text('locationPossible')}',
      _ => text('locationUnknown'),
    };
  }

  String _ship(String Function(String key) text, Locale locale) {
    final name =
        value.shipDisplayName(locale.languageCode, locale.countryCode) ??
        text('shipUnknown');
    return switch (value.shipState) {
      'confirmed' => '$name · ${text('shipConfirmed')}',
      'likely' => '$name · ${text('shipLikely')}',
      'possible' => '$name · ${text('shipPossible')}',
      _ => text('shipUnknown'),
    };
  }
}

class _SessionStateBadge extends StatelessWidget {
  const _SessionStateBadge({required this.value, required this.color});

  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: tokens.space.sm,
        vertical: tokens.space.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        border: Border.all(
          color: color.withValues(alpha: 0.45),
          width: tokens.stroke.hairline,
        ),
        borderRadius: tokens.shape.small,
      ),
      child: Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color),
      ),
    );
  }
}

class _SessionFactData {
  const _SessionFactData({
    required this.keyName,
    required this.label,
    required this.value,
    required this.color,
  });

  final String keyName;
  final String label;
  final String value;
  final Color color;
}

class _SessionFact extends StatelessWidget {
  const _SessionFact({required this.fact});

  final _SessionFactData fact;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      key: Key('game-session-${fact.keyName}'),
      constraints: const BoxConstraints(minHeight: 50),
      padding: EdgeInsetsDirectional.only(start: tokens.space.sm),
      decoration: BoxDecoration(
        border: BorderDirectional(
          start: BorderSide(
            color: fact.color.withValues(alpha: 0.72),
            width: tokens.stroke.regular,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            fact.label,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: tokens.colors.textSecondary),
          ),
          SizedBox(height: tokens.space.xxs),
          Text(
            fact.value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: tokens.colors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
