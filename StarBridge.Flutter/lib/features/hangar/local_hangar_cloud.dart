import 'dart:async';

import 'package:flutter/material.dart';

import '../../design_system/tokens/starbridge_tokens.dart';
import 'local_hangar_copy.dart';

/// The account copy of the local hangar (user 11-05: always on, no switch;
/// "存到账号应该是必须的"). Restored on a new computer.
@immutable
final class LocalHangarCloudState {
  const LocalHangarCloudState({
    required this.available,
    this.firstUploadNotice = false,
    this.restoredShips,
    this.lastResult = 'idle',
  });

  /// False for legacy sign-in or when the server switch is off.
  final bool available;
  final bool firstUploadNotice;
  final int? restoredShips;
  final String lastResult;

  static LocalHangarCloudState? parse(Map<String, Object?> payload) {
    final available = payload['available'];
    if (available is! bool) return null;
    final restored = payload['restoredShips'];
    return LocalHangarCloudState(
      available: available,
      firstUploadNotice: payload['firstUploadNotice'] == true,
      restoredShips: restored is int && restored > 0 ? restored : null,
      lastResult: payload['lastResult'] is String
          ? payload['lastResult']! as String
          : 'idle',
    );
  }
}

abstract interface class LocalHangarCloudPort {
  Future<LocalHangarCloudState> readCloud();
  Future<LocalHangarCloudState> acknowledgeCloud(String notice);
}

/// Replaces the "saved on this computer only" line: says where the hangar is
/// kept and shows the one-time notices. There is no switch (user 11-05). Re-reads whenever
/// [revision] changes (a save may have uploaded or the account restored).
class LocalHangarCloudBar extends StatefulWidget {
  const LocalHangarCloudBar({
    required this.port,
    required this.revision,
    this.onRestored,
    super.key,
  });

  final LocalHangarCloudPort port;
  final int revision;

  /// The account copy was written into this (empty) local hangar: re-read it.
  final VoidCallback? onRestored;

  @override
  State<LocalHangarCloudBar> createState() => _LocalHangarCloudBarState();
}

class _LocalHangarCloudBarState extends State<LocalHangarCloudBar> {
  LocalHangarCloudState? _state;
  int _epoch = 0;
  Timer? _followUp;

  /// Notices already shown for this port, so a re-read before the Host has
  /// the acknowledgement never shows the same notice twice.
  final _shown = <String>{};

  @override
  void initState() {
    super.initState();
    _listen(widget.port);
    _read();
    _scheduleFollowUp();
  }

  @override
  void dispose() {
    _followUp?.cancel();
    _unlisten(widget.port);
    super.dispose();
  }

  // A display session switches from a retained read to the live hangar
  // without a new port: read again whenever it changes.
  void _listen(LocalHangarCloudPort port) {
    if (port case final Listenable listenable) listenable.addListener(_read);
  }

  void _unlisten(LocalHangarCloudPort port) {
    if (port case final Listenable listenable) {
      listenable.removeListener(_read);
    }
  }

  /// A save uploads a few seconds later (and a sign-in may restore): look
  /// again once so the one-time notices are not left for the next visit.
  void _scheduleFollowUp() {
    _followUp?.cancel();
    _followUp = Timer(const Duration(seconds: 15), () {
      if (mounted) _read();
    });
  }

  @override
  void didUpdateWidget(LocalHangarCloudBar old) {
    super.didUpdateWidget(old);
    if (!identical(old.port, widget.port)) {
      _unlisten(old.port);
      _listen(widget.port);
      _epoch++;
      _state = null;
      _answered = false;
      _shown.clear();
    }
    if (!identical(old.port, widget.port) || old.revision != widget.revision) {
      _read();
      _scheduleFollowUp();
    }
  }

  bool _reading = false, _readAgain = false;

  /// The first read for this port has answered (or failed).
  bool _answered = false;

  /// One read in flight; a request that arrives meanwhile runs once after it,
  /// so an older answer never lands after a newer one.
  Future<void> _read() async {
    if (_reading) {
      _readAgain = true;
      return;
    }
    _reading = true;
    try {
      do {
        _readAgain = false;
        final epoch = _epoch, port = widget.port;
        try {
          final state = await port.readCloud();
          if (!mounted) return;
          if (epoch != _epoch) continue;
          setState(() {
            _state = state;
            _answered = true;
          });
          _announce(state);
        } on Object {
          if (mounted && epoch == _epoch) {
            setState(() {
              _state = null;
              _answered = true;
            });
          }
        }
      } while (_readAgain && mounted);
    } finally {
      _reading = false;
    }
  }

  void _announce(LocalHangarCloudState state) {
    final c = LocalHangarCopy(context);
    String? message;
    String? notice;
    if (state.restoredShips case final count?) {
      message = c.cloudRestored(count);
      notice = 'restored';
    } else if (state.firstUploadNotice) {
      message = c.cloudFirstUpload;
      notice = 'firstUpload';
    }
    if (message == null || notice == null || !_shown.add(notice)) return;
    if (notice == 'restored') widget.onRestored?.call();
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        key: Key('hangar-cloud-notice-$notice'),
        content: Text(message),
        duration: const Duration(seconds: 10),
      ),
    );
    widget.port.acknowledgeCloud(notice).ignore();
  }

  @override
  Widget build(BuildContext context) {
    final c = LocalHangarCopy(context), t = context.tokens;
    final style = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: t.colors.textSecondary);
    final state = _state;
    final cloud = state != null && state.available;
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 6),
      // Until the first answer the line keeps its place but says nothing,
      // so a first open never shows one state and then the other.
      child: Visibility.maintain(
        visible: _answered,
        child: Text(
          cloud ? c.accountStorage : c.deviceStorage,
          key: const Key('hangar-device-storage'),
          style: style,
        ),
      ),
    );
  }
}
