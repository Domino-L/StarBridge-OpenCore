import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import 'menu_read_feedback.dart';

/// The original handler still validates opening, grants and payload. This
/// context expires synchronously; only an admitted read can capture it.
Future<dynamic> Function(MethodCall) menuReadMethodHandler(
  Future<dynamic> Function(MethodCall) handler,
) =>
    (call) => withMenuReadOrigin(
      isMenuReadIntent(call.method, call.arguments)
          ? (call.arguments as Map)['motionSource']
          : null,
      () => handler(call),
    );

String encodeMenuWindowView(Map<String, Object?> view) {
  final payload = jsonEncode(view);
  return utf8.encode(payload).length <= 1048576
      ? payload
      : '{"state":"unavailable"}';
}

Future<void> sendMenuWindowView(
  MethodChannel channel,
  String method,
  Map<String, Object?> view, {
  required VoidCallback unavailable,
}) async {
  try {
    await channel.invokeMethod<void>(method, view);
  } on PlatformException {
    unavailable();
  } on MissingPluginException {
    unavailable();
  }
}

Future<void> detachMenuWindow(MethodChannel channel, int? request) async {
  try {
    await channel.invokeMethod<void>('detach', {'request': request});
  } on PlatformException {
    /* Native lifetime ended. */
  } on MissingPluginException {
    /* No native window. */
  }
}

/// How long an opening waits for the Host to acknowledge its window phase.
///
/// The acknowledgement is ordered by its own queue, so a later visible/closed
/// report can never overtake it. But that queue first drains hotkey attach and
/// settings work (each a Host request with a 3s timeout), which is typically
/// busy right after startup or an account attach. Opening the menu must not
/// sit behind it: wait briefly, then continue while delivery proceeds.
const menuHostAckWait = Duration(milliseconds: 250);

Future<void> boundedHostAck(Future<void> acknowledgement) =>
    acknowledgement.timeout(menuHostAckWait, onTimeout: () {});
