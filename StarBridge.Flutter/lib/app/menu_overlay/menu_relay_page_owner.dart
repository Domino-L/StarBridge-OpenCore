import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../design_system/interaction/panel_dialog_scope.dart';
import '../../design_system/interaction/starbridge_interaction_theme.dart';
import '../../design_system/styles/future_restraint_style.dart';
import '../../design_system/theme/theme_builder.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../../platform/bridge/bridge_client_session.dart';
import '../../platform/bridge/native_remote_image_disk_cache.dart';
import '../../shared/inline_image_cache.dart';
import '../../shared/remote_image.dart';
import '../../shared/remote_image_loader.dart';
import '../localization/app_strings.dart';
import 'menu_client_only_notice.dart';
import 'menu_loading.dart';
import 'menu_page_relay.dart';

/// What one client page owns in the menu engine for one relayed session.
abstract interface class MenuRelayPageContent {
  /// The menu opened again on the same session: read what was missed.
  void refresh();

  /// Another account or session context: drop what belonged to the old one.
  void contextChanged();
  void dispose();
}

/// Keeps a client page across menu openings. The workspace rebuilds panels
/// every opening, so the page's modules live here. A page no one looks at
/// stays for a quick return, then lets go of its session and images.
abstract class MenuRelayPageOwner<T extends MenuRelayPageContent>
    extends ChangeNotifier {
  MenuRelayPageOwner(this.relay) {
    relay.addListener(_changed);
    _removeExit = relay.registerExit(() async => _images?.exited());
  }
  final MenuPageRelay relay;
  late final void Function() _removeExit;

  static const releaseAfter = Duration(minutes: 10);
  static const imageCacheBytes = 64 * 1024 * 1024;

  /// The client page "do this in the client" opens, by [MenuToolPageOpener]
  /// method; null when there is none.
  String? get clientPage => null;

  /// Whether this page asks for [name] (one of [MenuBridgeRelay.clientOnly]).
  bool asksClientOnly(String name) => false;

  /// Builds the page's modules on a session that greeted this opening.
  T create(BridgeClientSession session, RemoteImageLoader images);

  T? _content;
  RemoteImageLoader? _images;
  BridgeClientSession? _session;
  final _inlineImages = InlineImageCache();
  Timer? _release;
  bool _wasWanted = false, _failed = false, _disposed = false;
  bool _verified = false;
  int _shown = 0, _context = 0, _navigation = 0, _starts = 0;

  bool get _wanted => _shown > 0 && relay.active;
  T? get content => _verified ? _content : null;

  void attach() {
    _shown++;
    final cache = PaintingBinding.instance.imageCache;
    cache.maximumSizeBytes = math.min(cache.maximumSizeBytes, imageCacheBytes);
    _changed();
    if (_failed && _wanted) unawaited(_start());
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

  void _clearContext() {
    _context = relay.contextRevision;
    _navigation++;
    _content?.contextChanged();
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
    final existing = _content;
    if (existing != null && identical(session, _session)) {
      if (_context != relay.contextRevision) _clearContext();
      existing.refresh();
      _verified = true;
      notifyListeners();
      return;
    }
    if (existing != null) _dropOwned();
    _session = session;
    _context = relay.contextRevision;
    final images = _images = RemoteImageLoader(
      diskCache: NativeRemoteImageDiskCache.forSession(session),
      mode: relay,
      session: session,
      // The session's own mode change pauses this loader; nothing to re-read.
      reconcileMode: () async {},
    );
    _content = create(session, images);
    _verified = true;
    notifyListeners();
  }

  void _dropOwned() {
    final content = _content, images = _images;
    _content = null;
    _images = null;
    _session = null;
    _verified = false;
    _inlineImages.clear();
    _navigation++;
    if (content != null) {
      scheduleMicrotask(_notify);
      unawaited(_afterPagesLeft(content, images));
    }
  }

  void _letGo() {
    _dropOwned();
    unawaited(relay.releaseFor(this));
  }

  /// A mounted page must stop listening first, but a hidden engine may draw no
  /// frame for a long time, so the wait is bounded.
  Future<void> _afterPagesLeft(T content, RemoteImageLoader? images) async {
    if (_shown > 0) {
      await Future.any<void>([
        WidgetsBinding.instance.endOfFrame,
        Future<void>.delayed(const Duration(seconds: 5)),
      ]);
    }
    content.dispose();
    images?.dispose();
  }

  @override
  void dispose() {
    _release?.cancel();
    relay.removeListener(_changed);
    _removeExit();
    _letGo();
    _disposed = true;
    super.dispose();
  }
}

/// A client page in a menu panel. The panel is the page's window: its size is
/// what the page measures, and its dialogs stay inside it.
class MenuRelayPage<T extends MenuRelayPageContent> extends StatefulWidget {
  const MenuRelayPage({
    super.key,
    required this.owner,
    required this.unavailableKey,
    required this.build,
  });
  final MenuRelayPageOwner<T> owner;
  final String unavailableKey;
  final Widget Function(BuildContext context, T content) build;

  @override
  State<MenuRelayPage<T>> createState() => _MenuRelayPageState<T>();
}

class _MenuRelayPageState<T extends MenuRelayPageContent>
    extends State<MenuRelayPage<T>> {
  StreamSubscription<String>? _clientOnly;

  @override
  void initState() {
    super.initState();
    widget.owner.attach();
    _clientOnly = widget.owner.relay.clientOnlyAsked.listen(_askedClientOnly);
  }

  @override
  void dispose() {
    unawaited(_clientOnly?.cancel());
    widget.owner.detach();
    super.dispose();
  }

  /// Pages share one session; the one the user touched last asked.
  void _askedClientOnly(String name) {
    final owner = widget.owner, relay = owner.relay;
    final context = _page.currentContext;
    if (!mounted ||
        context == null ||
        !owner.asksClientOnly(name) ||
        relay.lastTouched != null && !identical(relay.lastTouched, owner)) {
      return;
    }
    unawaited(showMenuClientOnlyNotice(context, clientPage: owner.clientPage));
  }

  /// Below the panel's navigator, so the notice stays in the panel.
  final _page = GlobalKey();

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
    final content = owner.content, images = owner._images;
    if (content == null || images == null) {
      return Center(
        child: owner._failed
            ? Text(AppStrings.of(context).text(widget.unavailableKey))
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
            child: PanelDialogScope(
              child: Listener(
                onPointerDown: (_) => owner.relay.lastTouched = owner,
                child: Navigator(
                  key: ValueKey(owner._navigation),
                  onGenerateRoute: (_) => PageRouteBuilder<void>(
                    pageBuilder: (context, _, _) => Scaffold(
                      backgroundColor: Colors.transparent,
                      body: KeyedSubtree(
                        key: _page,
                        child: widget.build(context, content),
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
