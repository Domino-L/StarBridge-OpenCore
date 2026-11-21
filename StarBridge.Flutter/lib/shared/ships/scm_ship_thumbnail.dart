import 'package:flutter/material.dart';

import '../../platform/bridge/bridge_account_access.dart';
import '../../platform/bridge/bridge_client_session.dart';
import '../remote_image.dart';
import '../remote_image_loader.dart';

typedef ShipThumbnailReader = Future<String?> Function(String model);

class ShipThumbnailScope extends InheritedWidget {
  const ShipThumbnailScope({
    required this.read,
    required super.child,
    this.revision = 0,
    super.key,
  });
  final ShipThumbnailReader? read;
  final int revision;
  static ShipThumbnailScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShipThumbnailScope>();
  @override
  bool updateShouldNotify(ShipThumbnailScope oldWidget) =>
      read != oldWidget.read || revision != oldWidget.revision;
}

/// Model lookup uses the existing Host exact-identity catalogue command. Image
/// bytes still belong to RemoteImageScope and its transport/cache policy.
class BridgeShipThumbnailScope extends StatefulWidget {
  const BridgeShipThumbnailScope({
    required this.session,
    required this.child,
    super.key,
  });
  final BridgeClientSession? session;
  final Widget child;
  @override
  State<BridgeShipThumbnailScope> createState() => _BridgeShipThumbnailState();
}

class _BridgeShipThumbnailState extends State<BridgeShipThumbnailScope> {
  final _reads = <String, (DateTime, Future<String?>)>{};
  void Function()? _unobserve;
  RemoteImageLoader? _images;
  bool _online = false;
  int _epoch = 0;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final images = RemoteImageScope.of(context);
    if (identical(images, _images)) return;
    _images?.removeListener(_modeChanged);
    _images = images;
    _online = images?.online == true;
    images?.addListener(_modeChanged);
    _epoch++;
    _reads.clear();
  }

  void _modeChanged() {
    final online = _images?.online == true;
    if (!mounted || online == _online) return;
    setState(() {
      _online = online;
      _epoch++;
      _reads.clear();
    });
  }

  @override
  void initState() {
    super.initState();
    _bind();
  }

  void _bind() {
    final session = widget.session;
    if (session == null || session.isClosed) return;
    _unobserve = session.observeGenerationChanges((_, _) {
      if (!mounted) return;
      setState(() {
        _epoch++;
        _reads.clear();
      });
    });
  }

  @override
  void didUpdateWidget(BridgeShipThumbnailScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session == widget.session) return;
    _unobserve?.call();
    _epoch++;
    _reads.clear();
    _bind();
  }

  Future<String?> _read(String model) {
    final session = widget.session;
    if (session == null ||
        session.connectionModeChanging ||
        !session.hostCapabilities.contains('ships.specifications') ||
        _images?.online != true) {
      return Future.value(null);
    }
    final now = DateTime.now(), cached = _reads[model];
    if (cached != null && now.isBefore(cached.$1)) return cached.$2;
    if (_reads.length >= 128) _reads.remove(_reads.keys.first);
    final future = _fetch(session, model, _epoch);
    _reads[model] = (now.add(const Duration(minutes: 1)), future);
    return future;
  }

  Future<String?> _fetch(
    BridgeClientSession session,
    String model,
    int epoch,
  ) async {
    final generation = session.activeGeneration;
    bool current() =>
        mounted &&
        epoch == _epoch &&
        session == widget.session &&
        generation == session.activeGeneration &&
        !session.connectionModeChanging &&
        _images?.online == true;
    try {
      final account = await session.request(
        'account.getCurrent',
        payload: const {'schemaVersion': 1},
      );
      if (!current() ||
          !hasRelayAccount(account) ||
          account.sessionGeneration != generation) {
        return null;
      }
      final response = await session.request(
        'ships.specifications',
        accountContext: account.accountContext,
        payload: {'schemaVersion': 1, 'model': model},
        timeout: const Duration(seconds: 25),
      );
      if (!current() ||
          response.sessionGeneration != generation ||
          response.accountContext?.environment !=
              account.accountContext?.environment ||
          response.accountContext?.authority !=
              account.accountContext?.authority ||
          response.accountContext?.subject != account.accountContext?.subject ||
          response.payload['schemaVersion'] != 1) {
        return null;
      }
      final facts = response.payload['specifications'];
      if (facts is! Map || facts['state'] != 'ready') return null;
      final url = facts['thumbnailUrl'];
      return url is String && remoteImageUri(url) != null ? url : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) =>
      ShipThumbnailScope(read: _read, revision: _epoch, child: widget.child);

  @override
  void dispose() {
    _epoch++;
    _unobserve?.call();
    _images?.removeListener(_modeChanged);
    _reads.clear();
    super.dispose();
  }
}

/// Mount only after the bundled catalogue image is absent or failed. Private
/// custom-image widgets never use this fallback.
class ScmShipThumbnail extends StatefulWidget {
  const ScmShipThumbnail({
    required this.model,
    required this.placeholder,
    this.fit = BoxFit.contain,
    this.compact = false,
    super.key,
  });
  final String model;
  final Widget placeholder;
  final BoxFit fit;
  final bool compact;
  @override
  State<ScmShipThumbnail> createState() => _ScmShipThumbnailState();
}

class _ScmShipThumbnailState extends State<ScmShipThumbnail> {
  ShipThumbnailReader? _reader;
  String? _url;
  int _epoch = 0, _revision = -1;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = ShipThumbnailScope.of(context);
    if (_reader == scope?.read && _revision == scope?.revision) return;
    _reader = scope?.read;
    _revision = scope?.revision ?? -1;
    _load();
  }

  @override
  void didUpdateWidget(ScmShipThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.model != widget.model) _load();
  }

  Future<void> _load() async {
    final epoch = ++_epoch;
    _url = null;
    final read = _reader;
    if (read == null || widget.model.trim().isEmpty) return;
    String? url;
    try {
      url = await read(widget.model);
    } catch (_) {
      /* Keep placeholder. */
    }
    if (mounted && epoch == _epoch) setState(() => _url = url);
  }

  @override
  Widget build(BuildContext context) => _url == null
      ? widget.placeholder
      : RemoteImage(
          _url!,
          kind: RemoteImageResourceKind.ship,
          followRedirects: false,
          fit: widget.fit,
          excludeFromSemantics: widget.compact,
          errorBuilder: (_, _, _) => widget.placeholder,
        );
}
