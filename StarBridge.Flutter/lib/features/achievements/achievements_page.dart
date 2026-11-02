import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../shared/diagnostics/loading_content_probe.dart';
import '../../shared/diagnostics/loading_metrics.dart';

import '../../app/localization/app_strings.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/interaction/starbridge_native_icon_action.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_activation_origin.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../design_system/interaction/starbridge_interaction_theme.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../account/account_models.dart';
import '../common/social_read_activity.dart';
import 'achievement_collection_view.dart';
import 'achievement_sources.dart';
import 'achievement_catalog.dart';
import 'achievement_collection_controller.dart';
import 'achievement_collection_session.dart';
import 'achievement_collection_port.dart';
import 'achievement_detail.dart';
import 'achievement_idea_form.dart';
import 'achievement_ideas_port.dart';
import '../onboarding/connection_mode_port.dart';

class AchievementsPage extends StatefulWidget {
  const AchievementsPage({
    required this.account,
    this.port = const UnavailableAchievementCollection(),
    this.catalog = achievementCatalog,
    this.onSignIn,
    this.ideas = const UnavailableAchievementIdeas(),
    this.mode,
    this.session,
    this.scmSession,
    this.scmPort,
    super.key,
  });

  final ValueListenable<AccountProjection> account;
  final AchievementCollectionPort port;
  final AchievementCollectionPort? scmPort;
  final AchievementCollectionSession? scmSession;
  final List<AchievementDefinition> catalog;
  final VoidCallback? onSignIn;
  final AchievementIdeasPort ideas;
  final ConnectionModeControl? mode;
  final AchievementCollectionSession? session;

  @override
  State<AchievementsPage> createState() => _AchievementsPageState();
}

class _AchievementsPageState extends State<AchievementsPage> {
  late AchievementCollectionController _collection;
  AchievementCollectionController? _scm;
  AchievementCollection get _state =>
      combineAchievementSources(_collection.value, _scm?.value, widget.catalog);
  List<AchievementDefinition> get _catalog => [
    ...widget.catalog,
    ...?_scm?.value.catalog,
  ];
  Listenable get _sources => Listenable.merge([_collection, ?_scm]);
  void _disconnectScm() {
    _scm?.removeListener(_onScmChanged);
    if (widget.scmSession == null) _scm?.dispose();
    _scm = null;
  }

  void _onScmChanged() {
    _onCollectionChanged();
    if (mounted) setState(() {});
  }

  late final ScrollController _scroll;
  bool _ownsCollection = true;
  int _viewEpoch = 0;
  int _refreshPhase = 0;
  InteractionSource _refreshSource = InteractionSource.programmatic;
  InteractionSource? _admittingRefreshSource;
  bool _restoringScroll = false;
  final _focusNodes = <String, FocusNode>{};
  final _ownedRoutes = <StarBridgeDialogRoute<dynamic>>{};
  final _ideaRoutes = <StarBridgeDialogRoute<dynamic>>{};
  final _detailRoutes = <StarBridgeDialogRoute<dynamic>>{};
  StarBridgeDialogRoute<void>? _detailRoute;
  String? _detailSelectedId;
  int? _detailGeneration;
  AccountSessionState? _detailSessionState;
  StarBridgeDialogRoute<void>? _ideaRoute;
  int? _ideaGeneration;

  @override
  void initState() {
    super.initState();
    _scroll = ScrollController(
      initialScrollOffset: widget.session?.scrollOffset ?? 0,
    );
    _scroll.addListener(_rememberScroll);
    _connect();
    widget.account.addListener(_onAccountChanged);
  }

  void _connect() {
    _refreshPhase++;
    _refreshSource = InteractionSource.programmatic;
    _ownsCollection = widget.session == null;
    _viewEpoch = widget.session?.viewEpoch ?? 0;
    _collection =
        widget.session?.collection ??
        AchievementCollectionController(
          account: widget.account,
          port: widget.port,
          mode: widget.mode,
        );
    _scm =
        widget.scmSession?.collection ??
        (widget.scmPort == null
            ? null
            : AchievementCollectionController(
                account: widget.account,
                port: widget.scmPort!,
                mode: widget.mode,
                permanentMilestones: false,
              ));
    _scm?.addListener(_onScmChanged);
    unawaited(widget.scmSession?.activate());
    _collection.addListener(_onCollectionChanged);
    unawaited(widget.session?.activate());
  }

  void _rememberScroll() {
    if (!_restoringScroll && _scroll.hasClients) {
      widget.session?.rememberScroll(_scroll.offset, expectedEpoch: _viewEpoch);
    }
  }

  @override
  void didUpdateWidget(AchievementsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.account != widget.account ||
        oldWidget.port != widget.port ||
        oldWidget.mode != widget.mode ||
        oldWidget.session != widget.session ||
        oldWidget.scmSession != widget.scmSession ||
        oldWidget.scmPort != widget.scmPort) {
      oldWidget.account.removeListener(_onAccountChanged);
      widget.account.addListener(_onAccountChanged);
      _dismissIdea();
      _dismissInspector();
      _scm?.removeListener(_onScmChanged);
      if (oldWidget.scmSession == null) _scm?.dispose();
      _collection.removeListener(_onCollectionChanged);
      if (_ownsCollection) _collection.dispose();
      _connect();
      _restoreScroll();
    }
  }

  void _dismissIdea() {
    _ideaRoute = null;
    // A reversing child can delay disposal of a removed parent. Retire the
    // exact owned children first, not whichever route happens to be on top.
    for (final route in _ideaRoutes.toList(growable: false).reversed) {
      retireStarBridgeDialog(route, includeClosing: true);
    }
  }

  void _ownRoute<T>(StarBridgeDialogRoute<T> route, {bool idea = false}) {
    _ownedRoutes.add(route);
    if (idea) {
      _ideaRoutes.add(route);
    } else {
      _detailRoutes.add(route);
    }
    unawaited(
      route.completed.then((_) {
        _ownedRoutes.remove(route);
        _ideaRoutes.remove(route);
        _detailRoutes.remove(route);
      }),
    );
  }

  void _onAccountChanged() {
    if (_ideaRoutes.isNotEmpty &&
        (widget.account.value.generation != _ideaGeneration ||
            widget.account.value.sessionState !=
                AccountSessionState.signedIn)) {
      _dismissIdea();
    }
  }

  Future<void> _contribute() async {
    if (widget.mode != null && !widget.mode!.allowsOnlineTraffic) return;
    if (_ideaRoute != null) return;
    if (widget.account.value.sessionState != AccountSessionState.signedIn) {
      widget.onSignIn?.call();
      return;
    }
    final generation = widget.account.value.generation;
    _ideaGeneration = generation;
    final route = StarBridgeDialogRoute<void>(
      data:
          InteractionScope.maybeOf(context) ??
          resolveStarBridgeInteraction(context),
      link: InteractionScope.linkOf(context),
      instant:
          StarBridgeActivationOrigin.sourceOf(context) ==
          InteractionSource.keyboard,
      dismissible: false,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      requestFocus: true,
      traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
      builder: (_) => Semantics(
        scopesRoute: true,
        explicitChildNodes: true,
        child: SafeArea(
          child: AchievementIdeaForm(
            port: widget.ideas,
            generation: generation,
            onConfirmationCreated: (route) => _ownRoute(route, idea: true),
          ),
        ),
      ),
    );
    _ideaRoute = route;
    _ownRoute(route, idea: true);
    await Navigator.of(context).push(route);
    if (identical(_ideaRoute, route)) _ideaRoute = null;
  }

  void _dismissInspector() {
    _detailRoute = null;
    _detailSelectedId = null;
    for (final route in _detailRoutes.toList(growable: false).reversed) {
      retireStarBridgeDialog(route, includeClosing: true);
    }
  }

  void _onCollectionChanged() {
    if (_state.isRefreshing) {
      _refreshPhase++;
      _refreshSource =
          _admittingRefreshSource ?? InteractionSource.programmatic;
    }
    final epoch = widget.session?.viewEpoch ?? 0;
    if (epoch != _viewEpoch) {
      _viewEpoch = epoch;
      _restoreScroll();
    }
    if (widget.mode != null && !widget.mode!.allowsOnlineTraffic) {
      _dismissIdea();
    }
    final state = _state;
    if (_detailSelectedId case final id?) {
      if (id.startsWith('scm-') && !_catalog.any((d) => d.id == id)) {
        _dismissInspector();
      }
    }
    if (_detailRoutes.isNotEmpty && _collection.hasMaterializedHandoff) {
      _detailGeneration = state.generation;
      _detailSessionState = widget.account.value.sessionState;
      return;
    }
    if (_detailRoutes.isNotEmpty &&
        (state.generation != _detailGeneration ||
            widget.account.value.sessionState != _detailSessionState ||
            state.status == AchievementCollectionStatus.signedOut ||
            state.status == AchievementCollectionStatus.loading ||
            state.status == AchievementCollectionStatus.unavailable)) {
      _dismissInspector();
    }
  }

  void _refresh(InteractionSource source) {
    // Tag only synchronous admission. A queued/background follow-up must not
    // inherit this source from the asynchronous command that just completed.
    final previous = _admittingRefreshSource;
    _admittingRefreshSource = source;
    try {
      unawaited(_collection.refresh());
      unawaited(_scm?.refresh());
    } finally {
      _admittingRefreshSource = previous;
    }
  }

  void _restoreScroll() {
    final epoch = _viewEpoch;
    final offset = widget.session?.scrollOffset ?? 0;
    _restoringScroll = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && epoch == _viewEpoch && _scroll.hasClients) {
        _scroll.jumpTo(offset.clamp(0.0, _scroll.position.maxScrollExtent));
        _restoringScroll = false;
        _rememberScroll();
      }
    });
  }

  String _syncTime(BuildContext context, DateTime at) {
    final local = at.toLocal();
    final labels = MaterialLocalizations.of(context);
    return '${labels.formatShortDate(local)} ${labels.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
  }

  Future<void> _inspect(
    AchievementDefinition definition,
    List<AchievementDefinition> order,
  ) async {
    if (_detailRoute != null) return;
    final collection = _state;
    final selected = ValueNotifier(definition);
    _detailSelectedId = definition.id;
    selected.addListener(() => _detailSelectedId = selected.value.id);
    final offset = _scroll.hasClients ? _scroll.offset : 0.0;
    final epoch = _viewEpoch;
    final route = StarBridgeDialogRoute<void>(
      data:
          InteractionScope.maybeOf(context) ??
          resolveStarBridgeInteraction(context),
      link: InteractionScope.linkOf(context),
      instant:
          StarBridgeActivationOrigin.sourceOf(context) ==
          InteractionSource.keyboard,
      barrierLabel: AppStrings.of(context).text('achievements.close'),
      autofocusFallback: false,
      requestFocus: true,
      traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
      builder: (_) => Semantics(
        scopesRoute: true,
        explicitChildNodes: true,
        child: SafeArea(
          child: ValueListenableBuilder<AchievementDefinition>(
            valueListenable: selected,
            builder: (_, current, _) => ListenableBuilder(
              listenable: _sources,
              builder: (_, _) {
                final index = order.indexWhere((d) => d.id == current.id);
                return AchievementDetail(
                  definition:
                      _catalog.where((d) => d.id == current.id).firstOrNull ??
                      current,
                  collection: _state,
                  index: index,
                  total: order.length,
                  onPrevious: index <= 0
                      ? null
                      : () => selected.value = order[index - 1],
                  onNext: index < 0 || index >= order.length - 1
                      ? null
                      : () => selected.value = order[index + 1],
                );
              },
            ),
          ),
        ),
      ),
    );
    _detailGeneration = collection.generation;
    _detailSessionState = widget.account.value.sessionState;
    _detailRoute = route;
    _ownRoute(route);
    await Navigator.of(context).push(route);
    final lastId = selected.value.id;
    // The popped future may finish before the route detaches its listeners.
    unawaited(route.completed.then((_) => selected.dispose()));
    if (!mounted) return;
    if (identical(_detailRoute, route)) _detailRoute = null;
    if (_collection.value.generation == collection.generation &&
        epoch == _viewEpoch) {
      _focusNodes[lastId]?.requestFocus();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            _collection.value.generation == collection.generation &&
            epoch == _viewEpoch &&
            _scroll.hasClients) {
          _scroll.jumpTo(offset.clamp(0.0, _scroll.position.maxScrollExtent));
        }
      });
    }
  }

  @override
  void dispose() {
    for (final route in _ownedRoutes.toList(growable: false).reversed) {
      retireStarBridgeDialog(route, includeClosing: true);
    }
    _ownedRoutes.clear();
    _ideaRoutes.clear();
    _detailRoutes.clear();
    _ideaRoute = null;
    _detailRoute = null;
    widget.account.removeListener(_onAccountChanged);
    _disconnectScm();
    _collection.removeListener(_onCollectionChanged);
    _rememberScroll();
    if (_ownsCollection) _collection.dispose();
    _scroll.dispose();
    for (final node in _focusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Material(
    key: const Key('achievements-page'),
    type: MaterialType.transparency,
    child: ListenableBuilder(
      listenable: Listenable.merge([widget.account, _collection, ?_scm]),
      builder: (context, _) {
        final state = _state;
        final earned = _catalog.where((d) => state.isEarned(d.id)).toList();
        final earnedCount = state.isReady && state.unknownIds.isEmpty
            ? '${earned.length}'
            : '—';
        final content = AchievementCollectionView(
          catalog: _catalog,
          collection: state,
          header: _header(context, state, earnedCount),
          scrollController: _scroll,
          focusNodes: _focusNodes,
          scope: widget.account.value.generation,
          onInspect: _inspect,
        );
        return LoadingContentProbe(
          route: '/achievements',
          status: switch (state.status) {
            AchievementCollectionStatus.loading => LoadingContentStatus.waiting,
            AchievementCollectionStatus.ready =>
              state.refreshFailed
                  ? LoadingContentStatus.partial
                  : LoadingContentStatus.data,
            AchievementCollectionStatus.signedOut ||
            AchievementCollectionStatus.unavailable =>
              LoadingContentStatus.unavailable,
          },
          items: state.isReady ? _catalog.length : 0,
          child: content,
        );
      },
    ),
  );

  Widget _header(
    BuildContext context,
    AchievementCollection state,
    String earnedCount,
  ) {
    final strings = AppStrings.of(context), tokens = context.tokens;
    final summary = strings
        .text('achievements.summary')
        .replaceAll('{total}', '${_catalog.length}')
        .split('{earned}');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 24,
          runSpacing: 12,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings.text('navigation.achievements'),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  strings.text('achievements.intro'),
                  style: TextStyle(color: tokens.colors.textSecondary),
                ),
              ],
            ),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: summary.first),
                      TextSpan(
                        text: earnedCount,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: tokens.colors.textPrimary,
                        ),
                      ),
                      TextSpan(text: summary.last),
                    ],
                  ),
                  key: const Key('achievement-summary'),
                  style: TextStyle(color: tokens.colors.textSecondary),
                ),
                StarBridgeNativeIconAction(
                  controlKey: const Key('achievement-refresh'),
                  label: strings.text('achievements.refresh'),
                  constraints: const BoxConstraints.tightFor(
                    width: 34,
                    height: 34,
                  ),
                  padding: EdgeInsets.zero,
                  onActivate: state.isRefreshing || !_collection.canRefresh
                      ? null
                      : _refresh,
                  icon: const StarBridgeIcon(
                    StarBridgeIconSemantic.refresh,
                    size: 20,
                  ),
                ),
                StarBridgeActionButton(
                  controlKey: const Key('achievement-contribute'),
                  onActivate:
                      (widget.mode == null ||
                              widget.mode!.allowsOnlineTraffic) &&
                          (widget.account.value.sessionState ==
                                  AccountSessionState.signedIn ||
                              widget.onSignIn != null)
                      ? (_) => _contribute()
                      : null,
                  child: Text(strings.text('achievements.idea.title')),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 20),
        Divider(height: 1, color: tokens.surfaces.panel.border),
        if (state.isRefreshing) ...[
          const SizedBox(height: 12),
          if (resolveStarBridgeInteraction(context).reduceMotion)
            Semantics(
              liveRegion: true,
              child: Text(
                strings.text('achievements.syncing'),
                key: const Key('achievement-refresh-static'),
              ),
            )
          else
            SocialReadActivity(
              key: ValueKey(('achievement-refresh-wait', _refreshPhase)),
              source: _refreshSource,
              opening: false,
              label: strings.text('achievements.syncing'),
              height: 2,
            ),
        ],
        if (state.refreshFailed && state.synchronizedAtUtc != null) ...[
          const SizedBox(height: 12),
          Text(
            strings
                .text('achievements.syncFailedAt')
                .replaceAll(
                  '{time}',
                  _syncTime(context, state.synchronizedAtUtc!),
                ),
            key: const Key('achievement-sync-failed'),
            style: TextStyle(color: tokens.colors.warning),
          ),
        ],
        if (state.cachedAtUtc case final at?) ...[
          const SizedBox(height: 16),
          Text(
            strings
                .text('achievements.offlineSnapshot')
                .replaceAll('{time}', at.toLocal().toString()),
            key: const Key('achievement-offline-notice'),
          ),
        ],
        if (!state.isReady) ...[
          const SizedBox(height: 16),
          _RecordNotice(
            status: state.status,
            onSignIn:
                widget.account.value.canLogin &&
                    (widget.mode == null || widget.mode!.allowsOnlineTraffic)
                ? widget.onSignIn
                : null,
          ),
        ],
        if (_scm != null && widget.account.value.isSignedIn) ...[
          if (!_scm!.value.isReady || _scm!.value.refreshFailed) ...[
            const SizedBox(height: 12),
            Text(
              'SCM · ${strings.text(_scm!.value.status == AchievementCollectionStatus.loading
                  ? 'achievements.loading'
                  : _scm!.value.isReady
                  ? 'achievements.sourceSyncFailed'
                  : 'achievements.unavailable')}',
              key: const Key('achievement-scm-notice'),
              style: TextStyle(color: tokens.colors.textSecondary),
            ),
          ],
          if (state.isReady && !_collection.value.isReady) ...[
            const SizedBox(height: 12),
            Text(
              '${strings.text('achievements.sourceBridge')} · ${strings.text(_collection.value.status == AchievementCollectionStatus.loading ? 'achievements.loading' : 'achievements.unavailable')}',
              key: const Key('achievement-bridge-notice'),
            ),
          ],
        ],
        const SizedBox(height: 24),
      ],
    );
  }
}

class _RecordNotice extends StatelessWidget {
  const _RecordNotice({required this.status, this.onSignIn});
  final AchievementCollectionStatus status;
  final VoidCallback? onSignIn;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 8,
      children: [
        Text(
          strings.text(switch (status) {
            AchievementCollectionStatus.signedOut => 'achievements.signedOut',
            AchievementCollectionStatus.loading => 'achievements.loading',
            _ => 'achievements.unavailable',
          }),
          style: TextStyle(color: context.tokens.colors.textSecondary),
        ),
        if (status == AchievementCollectionStatus.signedOut && onSignIn != null)
          StarBridgeActionButton(
            kind: StarBridgeActionKind.quiet,
            controlKey: const Key('achievement-sign-in'),
            onActivate: onSignIn == null ? null : (_) => onSignIn!(),
            child: Text(strings.text('achievements.signIn')),
          ),
      ],
    );
  }
}
