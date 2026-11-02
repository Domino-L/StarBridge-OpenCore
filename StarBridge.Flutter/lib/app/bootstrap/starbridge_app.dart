import '../../design_system/interaction/faded_name_tip.dart';
import 'package:flutter/material.dart';

import '../../platform/window/menu_notice.dart';
import '../../design_system/scrolling/starbridge_scroll_behavior.dart';

import '../../features/common/organization_logo_hints.dart';
import '../../features/common/user_interaction.dart';
import '../../features/direct_messages/direct_messages_page.dart';
import '../../features/direct_messages/direct_messages_module.dart';

import 'package:flutter/foundation.dart';

import '../presence/account_presence_scope.dart';

import 'package:flutter_localizations/flutter_localizations.dart';

import '../../design_system/appearance/appearance_layers.dart';
import '../../design_system/appearance/appearance_scope.dart';
import '../../design_system/appearance/holiday_calendar.dart';
import '../appearance/holiday_appearance_controller.dart';
import '../../design_system/style_registry.dart';
import '../../design_system/brand/brand_lockup.dart';
import '../../design_system/brand/brand_lockup_spec.dart';
import '../../design_system/theme/theme_builder.dart';
import '../../design_system/interaction/starbridge_interaction_theme.dart';
import '../../shared/inline_image_cache.dart';
import '../../shared/remote_image.dart';
import '../../shared/release/official_client_profile.dart';
import '../composition/app_composition.dart';
import '../composition/guide_composition.dart';
import '../../shared/guide/guide_scope.dart';
import '../composition/trade_chat_composition.dart';
import '../composition/app_activity_listener.dart';
import '../composition/room_session_listener.dart';
import '../composition/session_warmup_listener.dart';
import '../composition/local_notification_listener.dart';
import '../localization/app_strings.dart';
import '../preferences/app_preferences.dart';
import '../preferences/app_preferences_projection.dart';
import '../runtime/example_scene_control.dart';
import '../runtime/handle_mismatch_flow.dart';
import '../runtime/startup_prompt_queue.dart';
import '../runtime/product_first_use_flow.dart';
import '../../features/onboarding/first_use_setup_entry.dart';
import '../shell/starbridge_shell.dart';
import '../../platform/window/taskbar_attention_binding.dart';
import '../routing/open_destination_intent.dart';
import '../startup/startup_loading_page.dart';
import '../startup/startup_session.dart';
import '../startup/startup_content_gate.dart';

class StarBridgeApp extends StatefulWidget {
  const StarBridgeApp({
    required this.composition,
    this.exampleSceneControl = const ExampleSceneControl.hidden(),
    this.taskbarAttentionScope,
    this.navigatorKey,
    this.navigatorObservers = const [],
    this.promptQueue,
    this.canPresentIdentityPrompt,
    this.navigationRequests,
    this.onRetryConnection,
    this.startupSession,
    this.onRetryStartup,
    this.usageTermsPending = false,
    this.onFirstUseOwnsDeviceChoices,
    this.holidayCalendar,
    this.now,
    this.initialHolidayPreview,
    super.key,
  });

  final AppComposition composition;

  /// 节日日历；不传就用内置的那张表。测试会传假的。
  final HolidayCalendar? holidayCalendar;

  /// 本地时间的来源；不传就是系统时间。测试会传假的。
  final DateTime Function()? now;

  /// 启动时就进入某个节日的预览（调试和看效果用）；null 表示不预览。
  final String? initialHolidayPreview;
  final TaskbarAttentionScope? taskbarAttentionScope;
  final ExampleSceneControl exampleSceneControl;
  final GlobalKey<NavigatorState>? navigatorKey;
  final List<NavigatorObserver> navigatorObservers;
  final StartupPromptQueue? promptQueue;
  final bool Function()? canPresentIdentityPrompt;
  final ValueListenable<OpenDestinationIntent?>? navigationRequests;
  final Future<void> Function()? onRetryConnection;
  final StartupSession? startupSession;
  final Future<void> Function()? onRetryStartup;
  final bool usageTermsPending;

  /// Lets the runtime host hold its standalone startup prompt while first-use
  /// setup will ask startup and close behaviour itself.
  final ValueChanged<bool>? onFirstUseOwnsDeviceChoices;

  @override
  State<StarBridgeApp> createState() => _StarBridgeAppState();
}

class _StarBridgeAppState extends State<StarBridgeApp>
    with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 睡眠唤醒、从后台回来：日期和时区可能都变了，重新判断一次节日。
    if (state == AppLifecycleState.resumed) _appearance?.wake();
  }

  final _userNavigation = UserPageNavigation();
  final _inlineImages = InlineImageCache();
  VoidCallback? _releaseImages;
  void _bindImages() => _releaseImages = widget.composition.imageMaintenance
      .registerCache(_inlineImages);
  final _navigationRequests = ValueNotifier<OpenDestinationIntent?>(null);
  late final StartupPromptQueue _prompts;
  late HandleMismatchFlow _handleMismatch;
  ProductFirstUseFlow? _firstUse;
  void _forwardDestination() =>
      _navigationRequests.value = widget.navigationRequests?.value;
  bool _basePromptReady() =>
      mounted &&
      !widget.exampleSceneControl.active &&
      (widget.startupSession?.complete ?? true) &&
      (widget.canPresentIdentityPrompt?.call() ?? true);
  bool _identityReady() =>
      _basePromptReady() && !(_firstUse?.blocksOptionalPrompts ?? false);
  void _bindFirstUse() {
    _firstUse?.dispose();
    _firstUse = null;
    if (!OfficialClientProfile.firstUseGuide) {
      widget.onFirstUseOwnsDeviceChoices?.call(false);
      return;
    }
    final composition = widget.composition;
    _firstUse = ProductFirstUseFlow(
      composition: composition,
      queue: _prompts,
      ready: _basePromptReady,
      current: () =>
          mounted &&
          identical(widget.composition, composition) &&
          !widget.exampleSceneControl.active,
      onOwnsDeviceChoices: widget.onFirstUseOwnsDeviceChoices,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _firstUse?.wake());
  }

  void _wakeFirstUse() => _firstUse?.wake();
  GuideBinding? _guide;
  void _bindGuide() {
    _guide?.dispose();
    _guide = GuideBinding.compose(
      widget.composition,
      navigate: (route) =>
          _navigationRequests.value = OpenDestinationIntent(route),
    );
  }

  void _bindIdentity() {
    _handleMismatch = HandleMismatchFlow(
      module: widget.composition.handleMismatch,
      queue: _prompts,
      ready: _identityReady,
      onOpenAccount: () => _navigationRequests.value = OpenDestinationIntent(
        '/settings/account',
      ),
    );
  }

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

  HolidayAppearanceController? _appearance;
  void _bindAppearance() {
    _appearance?.dispose();
    _appearance = HolidayAppearanceController(
      calendar: widget.holidayCalendar ?? BuiltInHolidayCalendar(),
      preferences: widget.composition.preferences.projection,
      windowChrome: widget.composition.windowChrome,
      now: widget.now,
    );
    // 调试用：STARBRIDGE_HOLIDAY_PREVIEW=xmas 启动时直接进入预览，便于看外观。
    final forced = widget.initialHolidayPreview;
    if (forced != null && forced.isNotEmpty) {
      _appearance!.previewHoliday(forced);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bindImages();
    _prompts = widget.promptQueue ?? StartupPromptQueue();
    _bindAppearance();
    _bindFirstUse();
    _bindGuide();
    _bindIdentity();
    widget.navigationRequests?.addListener(_forwardDestination);
    widget.startupSession?.addListener(_handleMismatch.wake);
    widget.startupSession?.addListener(_wakeFirstUse);
    _forwardDestination();
    widget.composition.account.projection.addListener(_resetMediaOwner);
    _resetMediaOwner();
  }

  @override
  void didUpdateWidget(covariant StarBridgeApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.navigationRequests != widget.navigationRequests) {
      oldWidget.navigationRequests?.removeListener(_forwardDestination);
      widget.navigationRequests?.addListener(_forwardDestination);
      _forwardDestination();
    }
    if (oldWidget.composition != widget.composition) {
      _releaseImages?.call();
      _bindAppearance();
      _bindFirstUse();
      _bindGuide();
      oldWidget.startupSession?.removeListener(_handleMismatch.wake);
      _handleMismatch.dispose();
      _bindIdentity();
      widget.startupSession?.addListener(_handleMismatch.wake);
      oldWidget.composition.account.projection.removeListener(_resetMediaOwner);
      widget.composition.account.projection.addListener(_resetMediaOwner);
      _inlineImages.clear();
      _resetMediaOwner();
      _bindImages();
    }
    if (oldWidget.composition == widget.composition &&
        oldWidget.startupSession != widget.startupSession) {
      oldWidget.startupSession?.removeListener(_handleMismatch.wake);
      widget.startupSession?.addListener(_handleMismatch.wake);
    }
    if (oldWidget.startupSession != widget.startupSession) {
      oldWidget.startupSession?.removeListener(_wakeFirstUse);
      widget.startupSession?.addListener(_wakeFirstUse);
    }
    _firstUse?.wake();
    _handleMismatch.wake();
  }

  @override
  void dispose() {
    widget.navigationRequests?.removeListener(_forwardDestination);
    widget.startupSession?.removeListener(_handleMismatch.wake);
    widget.startupSession?.removeListener(_wakeFirstUse);
    _firstUse?.dispose();
    _guide?.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _appearance?.dispose();
    _handleMismatch.dispose();
    if (widget.promptQueue == null) _prompts.dispose();
    _navigationRequests.dispose();
    widget.composition.account.projection.removeListener(_resetMediaOwner);
    _releaseImages?.call();
    _inlineImages.dispose();
    widget.composition.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppPreferencesProjection>(
      valueListenable: widget.composition.preferences.projection,
      builder: (context, projection, _) =>
          ValueListenableBuilder<AppearanceLayers>(
            valueListenable: _appearance!.layers,
            builder: (context, layers, _) =>
                _buildApp(context, projection, layers),
          ),
    );
  }

  Widget _buildApp(
    BuildContext context,
    AppPreferencesProjection projection,
    AppearanceLayers layers,
  ) {
    final preferences = projection.effective;
    // 节日生效时换颜色；平时原样。
    final standardTokens = StyleRegistry()
        .resolve(preferences.designStyleId, preferences.appearanceMode)
        .tokens;
    final baseTokens = layers.tokensFor(standardTokens);
    return AppearanceScope(
      layers: layers,
      child: AccountPresenceScope(
        account: widget.composition.account.projection,
        connection: widget.composition.manualPresence,
        child: MaterialApp(
          scrollBehavior: const StarBridgeScrollBehavior(),
          navigatorKey: widget.navigatorKey,
          navigatorObservers: [
            ...widget.navigatorObservers,
            if (!widget.navigatorObservers.contains(_prompts)) _prompts,
          ],
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
          theme: buildStarBridgeTheme(
            baseTokens,
            preferences.locale,
            interactionSuite: interactionSuiteFromName(
              preferences.interactionStyle.name,
            ),
          ),
          builder: (context, child) {
            final systemReduced =
                MediaQuery.maybeOf(context)?.disableAnimations ?? false;
            final userReduced =
                preferences.motionPreference == MotionPreference.reduce;
            final resolvedTokens = baseTokens.withReducedMotion(
              systemReduced || userReduced,
            );
            return FadedNameTip(child: FirstUseSetupEntry(
              open: _firstUse?.supported == true ? _firstUse!.open : null,
              child: AppActivityListener(
                activity: widget.composition.appActivity,
                child: AnimatedTheme(
                  key: const Key('starbridge-theme-transition'),
                  data: buildStarBridgeTheme(
                    resolvedTokens,
                    preferences.locale,
                    interactionSuite: interactionSuiteFromName(
                      preferences.interactionStyle.name,
                    ),
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
                      child: RemoteImageScope(
                        loader: widget.composition.remoteImages,
                        child: StarBridgeInteractionConfiguration(
                          suite: interactionSuiteFromName(
                            preferences.interactionStyle.name,
                          ),
                          reduceMotion: userReduced,
                          child: OrganizationLogoHints(
                            notifier:
                                widget.composition.officialFleet.projection,
                            resolve: (code) {
                              final fleet = widget
                                  .composition
                                  .officialFleet
                                  .projection
                                  .value
                                  .fleet;
                              return fleet != null &&
                                      fleet.sid.toUpperCase() == code
                                  ? fleet.displayLogoUrl
                                  : null;
                            },
                            child: GuideScope(
                              hub: _guide?.hub,
                              child: HolidayExemptThemeScope(
                                data: layers.holidayActive
                                    ? buildStarBridgeTheme(
                                        standardTokens.withReducedMotion(
                                          systemReduced || userReduced,
                                        ),
                                        preferences.locale,
                                        interactionSuite:
                                            interactionSuiteFromName(
                                              preferences
                                                  .interactionStyle
                                                  .name,
                                            ),
                                      )
                                    : null,
                                child: withTradeChat(
                                  widget.composition.tradeChat,
                                  child!,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ));
          },
          home: widget.startupSession != null
              ? StartupContentGate(
                  session: widget.startupSession!,
                  account: widget.composition.account.projection,
                  preferencesConfirmed: projection.confirmed != null,
                  shell: (_) => _shell(),
                  loading: (_) => StartupLoadingPage(
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
      ),
    );
  }

  Widget _shell() => widget.usageTermsPending
      ? const _UsageTermsPendingSurface()
      : SessionWarmupListener(
          composition: widget.composition,
          child: RoomSessionListener(
            module: widget.composition.partyRooms,
            child: LocalNotificationListener(
              events: widget.composition.notificationReminders,
              settings: widget.composition.notificationSettings,
              menuOwnsNotices: () =>
                  switch (widget.composition.overlaySettings.menuPreview) {
                    MenuNoticeDeliveryOwner owner =>
                      owner.menuNoticeDeliveryActive,
                    _ => false,
                  },
              desktop: widget.composition.desktopNotifications,
              visibleConversationKey: () =>
                  widget.composition.friends.visibleConversationKey,
              child: StarBridgeShell(
                taskbarAttentionScope: widget.taskbarAttentionScope,
                userNavigation: _userNavigation,
                navigationRequests: _navigationRequests,
                onHandleMismatch: _handleMismatch.open,
                composition: widget.composition,
                exampleSceneControl: widget.exampleSceneControl,
                onRetryConnection: widget.onRetryConnection,
              ),
            ),
          ),
        );
}

class _UsageTermsPendingSurface extends StatelessWidget {
  const _UsageTermsPendingSurface();

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context);
    return Scaffold(
      key: const Key('usage-terms-pending'),
      body: Center(
        child: Text(
          locale.languageCode == 'en'
              ? 'Review the terms and notices before continuing.'
              : locale.scriptCode == 'Hant' ||
                    const {'TW', 'HK', 'MO'}.contains(locale.countryCode)
              ? '請先確認使用條款與聲明。'
              : '请先确认使用条款与声明。',
        ),
      ),
    );
  }
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
