import 'package:flutter/material.dart';

import '../../features/common/user_interaction.dart';
import '../../features/direct_messages/direct_messages_page.dart';
import '../../features/direct_messages/direct_messages_module.dart';

import 'package:flutter/foundation.dart';

import '../presence/account_presence_scope.dart';

import 'package:flutter_localizations/flutter_localizations.dart';

import '../../design_system/style_registry.dart';
import '../../design_system/brand/brand_lockup.dart';
import '../../design_system/brand/brand_lockup_spec.dart';
import '../../design_system/theme/theme_builder.dart';
import '../../shared/inline_image_cache.dart';
import '../composition/app_composition.dart';
import '../composition/app_activity_listener.dart';
import '../composition/room_session_listener.dart';
import '../composition/session_warmup_listener.dart';
import '../composition/local_notification_listener.dart';
import '../localization/app_strings.dart';
import '../preferences/app_preferences.dart';
import '../preferences/app_preferences_projection.dart';
import '../runtime/example_scene_control.dart';
import '../shell/starbridge_shell.dart';
import '../routing/open_destination_intent.dart';
import '../startup/startup_loading_page.dart';
import '../startup/startup_session.dart';

class StarBridgeApp extends StatefulWidget {
  const StarBridgeApp({
    required this.composition,
    this.exampleSceneControl = const ExampleSceneControl.hidden(),
    this.navigatorKey,
    this.navigatorObservers = const [],
    this.navigationRequests,
    this.onRetryConnection,
    this.startupSession,
    this.onRetryStartup,
    super.key,
  });

  final AppComposition composition;
  final ExampleSceneControl exampleSceneControl;
  final GlobalKey<NavigatorState>? navigatorKey;
  final List<NavigatorObserver> navigatorObservers;
  final ValueListenable<OpenDestinationIntent?>? navigationRequests;
  final Future<void> Function()? onRetryConnection;
  final StartupSession? startupSession;
  final Future<void> Function()? onRetryStartup;

  @override
  State<StarBridgeApp> createState() => _StarBridgeAppState();
}

class _StarBridgeAppState extends State<StarBridgeApp> {
  final _userNavigation = UserPageNavigation();
  final _inlineImages = InlineImageCache();
  Object? _mediaOwner;
  void _resetMediaOwner() {
    final account = widget.composition.account.projection.value;
    final owner = (
      account.generation,
      account.isSignedIn || account.isLegacyAccount,
    );
    if (_mediaOwner != owner) {
      _inlineImages.clear();
      _mediaOwner = owner;
    }
  }

  @override
  void initState() {
    super.initState();
    widget.composition.account.projection.addListener(_resetMediaOwner);
    _resetMediaOwner();
  }

  @override
  void didUpdateWidget(covariant StarBridgeApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.composition != widget.composition) {
      oldWidget.composition.account.projection.removeListener(_resetMediaOwner);
      widget.composition.account.projection.addListener(_resetMediaOwner);
      _inlineImages.clear();
      _resetMediaOwner();
    }
  }

  @override
  void dispose() {
    widget.composition.account.projection.removeListener(_resetMediaOwner);
    _inlineImages.clear();
    widget.composition.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppPreferencesProjection>(
      valueListenable: widget.composition.preferences.projection,
      builder: (context, projection, _) {
        final preferences = projection.effective;
        final baseTokens = StyleRegistry()
            .resolve(preferences.designStyleId, preferences.appearanceMode)
            .tokens;
        return AccountPresenceScope(
          account: widget.composition.account.projection,
          connection: widget.composition.manualPresence,
          child: MaterialApp(
            navigatorKey: widget.navigatorKey,
            navigatorObservers: widget.navigatorObservers,
            debugShowCheckedModeBanner: false,
            title: 'StarBridge',
            locale: preferences.locale,
            supportedLocales: AppStrings.runtimeSupportedLocales(),
            localizationsDelegates: const [
              AppStringsDelegate(),
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            theme: buildStarBridgeTheme(baseTokens, preferences.locale),
            builder: (context, child) {
              final systemReduced =
                  MediaQuery.maybeOf(context)?.disableAnimations ?? false;
              final userReduced =
                  preferences.motionPreference == MotionPreference.reduce;
              final resolvedTokens = baseTokens.withReducedMotion(
                systemReduced || userReduced,
              );
              return AppActivityListener(
                activity: widget.composition.appActivity,
                child: AnimatedTheme(
                  key: const Key('starbridge-theme-transition'),
                  data: buildStarBridgeTheme(
                    resolvedTokens,
                    preferences.locale,
                  ),
                  duration: resolvedTokens.motion.surfaceEnter,
                  curve: resolvedTokens.motion.enterCurve,
                  child: UserInteractionScope(
                    navigation: _userNavigation,
                    port: widget.composition.userInteractions,
                    messagePage: (row, back) => DirectMessagesPage(
                      createPort: widget.composition.createUserMessages,
                      onBack: back,
                      initialConversation: Conversation(
                        row.chatTargetRef!,
                        row.name,
                        '',
                        row.updatedAt,
                        0,
                        row.relationship == 'friend' ? 'friend' : 'none',
                        avatar: row.avatar,
                        gameId: row.gameId,
                        conversationKey: row.conversationKey,
                      ),
                    ),
                    child: InlineImageCacheScope(
                      cache: _inlineImages,
                      child: child!,
                    ),
                  ),
                ),
              );
            },
            home: widget.startupSession != null
                ? ValueListenableBuilder<StartupPhase>(
                    valueListenable: widget.startupSession!,
                    builder: (context, phase, _) =>
                        phase == StartupPhase.complete
                        ? _shell()
                        : StartupLoadingPage(
                            session: widget.startupSession!,
                            windowChrome: widget.composition.windowChrome,
                            preferencesConfirmed: projection.confirmed != null,
                            reduceMotion:
                                preferences.motionPreference ==
                                MotionPreference.reduce,
                            onRetry: widget.onRetryStartup!,
                          ),
                  )
                : projection.isInitialLoading
                ? const _PreferencesBootstrapSurface()
                : _shell(),
          ),
        );
      },
    );
  }

  Widget _shell() => SessionWarmupListener(
    composition: widget.composition,
    child: RoomSessionListener(
      module: widget.composition.partyRooms,
      child: LocalNotificationListener(
        events: widget.composition.notificationReminders,
        settings: widget.composition.notificationSettings,
        desktop: widget.composition.desktopNotifications,
        child: StarBridgeShell(
          userNavigation: _userNavigation,
          navigationRequests: widget.navigationRequests,
          composition: widget.composition,
          exampleSceneControl: widget.exampleSceneControl,
          onRetryConnection: widget.onRetryConnection,
        ),
      ),
    ),
  );
}

class _PreferencesBootstrapSurface extends StatelessWidget {
  const _PreferencesBootstrapSurface();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: BrandLockup(scale: BrandLockupScale.display)),
    );
  }
}
