import 'package:flutter/services.dart';

const _gameplayFilesChannel = MethodChannel('starbridge/gameplay_files');

/// Opens the app-owned Game.log picker and returns null when cancelled.
///
/// Platform errors propagate to the caller. The Native Host is responsible for
/// validating the selected basename and importing the file.
Future<String?> pickGameplayLog() =>
    _gameplayFilesChannel.invokeMethod<String>('pickGameLog');
