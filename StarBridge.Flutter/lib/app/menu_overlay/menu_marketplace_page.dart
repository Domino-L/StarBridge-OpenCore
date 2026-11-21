import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design_system/interaction/starbridge_interaction_theme.dart';
import '../../design_system/styles/future_restraint_style.dart';
import '../../design_system/theme/theme_builder.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../../features/marketplace/marketplace_chat_controller.dart';
import '../../features/marketplace/marketplace_controller.dart';
import '../../features/marketplace/marketplace_dialog_scope.dart';
import '../../features/marketplace/marketplace_feature.dart' show bindTradeChat;
import '../../features/marketplace/marketplace_page.dart';
import '../../features/marketplace/marketplace_port.dart';
import '../../platform/bridge/bridge_client_session.dart';
import '../../platform/bridge/native_remote_image_disk_cache.dart';
import '../../shared/inline_image_cache.dart';
import '../../shared/remote_image.dart';
import '../../shared/remote_image_loader.dart';
import '../localization/app_strings.dart';
import 'menu_loading.dart';
import 'menu_page_relay.dart';
import 'menu_trade_chat_host.dart';

/// Owns the hall across menu openings: the workspace rebuilds its panels every
/// opening, while a trade answer may still arrive and the user's place in the
/// hall should survive a quick look back at the game.
final class MenuMarketplaceOwner extends ChangeNotifier {
  MenuMarketplaceOwner(this.relay) {
    relay.addListener(_changed);
    _removeExit = relay.registerExit(() async => _images?.exited());
  }
  late final void Function() _removeExit;
  final MenuPageRelay relay;

  /// A hall no one is looking at stays for a quick return, then lets go.
  static const releaseAfter = Duration(minutes: 10);
  static const imageCacheBytes = 64 * 1024 * 1024;

  MarketplaceController? _controller;
  MarketplaceChatController? _chat;
  RemoteImageLoader? _images;
  BridgeClientSession? _session;
  final _inlineImages = InlineImageCache();
  Timer? _release;
  bool _wasWanted = false, _failed = false, _disposed = false;

  /// Retained content shows only after this opening's greeting proved the same
  /// session and account; until then the panel shows loading.
  bool _verified = false;
  int _shown = 0, _context = 0, _navigation = 0, _starts = 0;

  bool get _wanted => _shown > 0 && relay.active;

  void attach() {
    _shown++;
    final cache = PaintingBinding.instance.imageCache;
    cache.maximumSizeBytes = math.min(cache.maximumSizeBytes, imageCacheBytes);
    _changed();
    // A retry after the recovery prompt, which remounts the panel.
    if (_failed && _wanted) unawaited(_start());
    _keepTradesVisible();
  }

  /// The page that is leaving says "not visible" after its successor said
  /// "visible". The last word belongs to whichever page is still here.
  void _keepTradesVisible() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_disposed && _shown > 0) _controller?.trades.setVisible(true);
    });
  }

  void detach() {
    _shown--;
    _changed();
  }

  void _changed() {
    if (_disposed) return;
    if (!relay.enabled) {
      _wasWanted = false;
      _release?.cancel();
      _letGo();
      return;
    }
    final wanted = _wanted;
    if (wanted && !_wasWanted) {
      _release?.cancel();
      unawaited(_start());
    } else if (!wanted && _wasWanted) {
      _verified = false;
      _release = Timer(releaseAfter, _letGo);
    }
    _wasWanted = wanted;
    if (_context != relay.contextRevision) {
      _clearContext();
      if (_shown > 0) scheduleMicrotask(_notify);
    }
  }

  /// Another account: its dialogs go with the old navigator.
  void _clearContext() {
    _context = relay.contextRevision;
    _navigation++;
    _controller?.contextChanged();
    _chat?.reset();
    _keepTradesVisible();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _start() async {
    final start = ++_starts;
    _failed = false;
    final session = await relay.connect(holder: this);
    if (_disposed || !_wanted || start != _starts) return;
    if (session == null) {
      _failed = true;
      notifyListeners();
      return;
    }
    final existing = _controller;
    if (existing != null && identical(session, _session)) {
      if (_context != relay.contextRevision) _clearContext();
      unawaited(existing.refreshHall());
      // No pushes reached a hidden menu: read the trade messages it missed.
      unawaited(_chat?.catchUp());
      _verified = true;
      notifyListeners();
      return;
    }
    if (existing != null) _dropOwned();
    _session = session;
    _context = relay.contextRevision;
    final controller = MarketplaceController(
      BridgeMarketplacePort(session, relay),
    );
    controller.openScm = (_) async {
      await session.request(
        'helpSupport.openScm',
        payload: {'schemaVersion': 1},
      );
    };
    controller.profileEditedInClient = true;
    final chat = MarketplaceChatController(
      controller.port as MarketplaceChatPort,
    );
    bindTradeChat(controller, chat, session);
    _controller = controller;
    _chat = chat;
    _images = RemoteImageLoader(
      diskCache: NativeRemoteImageDiskCache.forSession(session),
      mode: relay,
      session: session,
      // The session's own mode change pauses this loader; nothing to re-read.
      reconcileMode: () async {},
    );
    _verified = true;
    _keepTradesVisible();
    notifyListeners();
  }

  void _dropOwned() {
    final controller = _controller, images = _images, chat = _chat;
    _controller = null;
    _chat = null;
    _images = null;
    _session = null;
    _verified = false;
    _inlineImages.clear();
    _navigation++;
    PaintingBinding.instance.imageCache.clear();
    if (controller != null) {
      scheduleMicrotask(_notify);
      unawaited(_afterPagesLeft(controller, images, chat));
    }
  }

  void _letGo() {
    _dropOwned();
    unawaited(relay.releaseFor(this));
  }

  /// A mounted page must stop listening first, but a hidden engine may draw no
  /// frame for a long time, so the wait is bounded.
  Future<void> _afterPagesLeft(
    MarketplaceController controller,
    RemoteImageLoader? images,
    MarketplaceChatController? chat,
  ) async {
    if (_shown > 0) {
      await Future.any<void>([
        WidgetsBinding.instance.endOfFrame,
        Future<void>.delayed(const Duration(seconds: 5)),
      ]);
    }
    chat?.dispose();
    controller.dispose();
    images?.dispose();
  }

  @override
  void dispose() {
    _release?.cancel();
    relay.removeListener(_changed);
    _removeExit();
    _letGo();
    _disposed = true;
    relay.dispose();
    super.dispose();
  }
}

/// The client's trading hall in a menu panel. The panel is the page's window:
/// its size is what the page measures and its dialogs stay inside it.
class MenuMarketplacePage extends StatefulWidget {
  const MenuMarketplacePage({super.key, required this.owner});
  final MenuMarketplaceOwner owner;

  @override
  State<MenuMarketplacePage> createState() => _MenuMarketplacePageState();
}

class _MenuMarketplacePageState extends State<MenuMarketplacePage> {
  @override
  void initState() {
    super.initState();
    widget.owner.attach();
  }

  @override
  void dispose() {
    widget.owner.detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context);
    final interaction = resolveStarBridgeInteraction(context);
    final tokens = FutureRestraintStyle.resolve(AppearanceMode.dark)
        .withReducedMotion(interaction.reduceMotion);
    return Theme(
      data: buildStarBridgeTheme(
        tokens,
        locale,
        interactionSuite: interaction.suite,
      ),
      child: Builder(
        builder: (context) => ColoredBox(
          color: context.tokens.surfaces.ground.fill,
          child: ListenableBuilder(
            listenable: widget.owner,
            builder: (context, _) => _content(context),
          ),
        ),
      ),
    );
  }

  Widget _content(BuildContext context) {
    final owner = widget.owner;
    final controller = owner._controller, images = owner._images;
    if (controller == null || images == null || !owner._verified) {
      return Center(
        child: owner._failed
            ? Text(
                AppStrings.of(context)
                    .text('menu.overlay.window.marketplaceUnavailable'),
              )
            : const MenuLoading(),
      );
    }
    return LayoutBuilder(
      builder: (context, box) => MediaQuery(
        data: MediaQuery.of(context).copyWith(size: box.biggest),
        child: InlineImageCacheScope(
          cache: owner._inlineImages,
          child: RemoteImageScope(
            loader: images,
            child: MarketplaceDialogScope(
              child: CallbackShortcuts(
                bindings: {
                  const SingleActivator(
                    LogicalKeyboardKey.keyK,
                    control: true,
                  ): () =>
                      unawaited(controller.focusSearch()),
                },
                child: Navigator(
                  key: ValueKey(owner._navigation),
                  onGenerateRoute: (_) => PageRouteBuilder<void>(
                    pageBuilder: (_, _, _) => Scaffold(
                      backgroundColor: Colors.transparent,
                      body: MenuTradeChatHost(
                        chat: owner._chat,
                        child: MarketplacePage(controller),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
