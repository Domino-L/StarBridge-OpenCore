import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../bridge/bridge_client_session.dart';
import '../bridge/bridge_connection.dart';
import '../bridge/bridge_envelope.dart';
import 'native_host_connector.dart';

final class WindowsNativeHostPlatformPort implements NativeHostPlatformPort {
  WindowsNativeHostPlatformPort({
    String? executablePath,
    this.connectTimeout = const Duration(seconds: 10),
  }) : executablePath = executablePath ?? resolvePackagedExecutable();

  final String executablePath;
  final Duration connectTimeout;

  static String resolvePackagedExecutable() {
    final separator = Platform.pathSeparator;
    final executableDirectory = File(Platform.resolvedExecutable).parent.path;
    return '$executableDirectory${separator}native_host${separator}StarBridge.NativeHost.exe';
  }

  @override
  Future<NativeHostPlatformLease> start({required String pipeName}) async {
    if (!Platform.isWindows) {
      throw const NativeHostConnectionException('host.platform_unsupported');
    }
    final executable = File(executablePath);
    if (!await executable.exists()) {
      throw NativeHostConnectionException(
        'host.executable_missing',
        executablePath,
      );
    }

    final Process process;
    try {
      process = await Process.start(
        executable.path,
        ['--pipe-name=$pipeName', '--parent-pid=$pid'],
        mode: ProcessStartMode.normal,
        runInShell: false,
      );
    } on Object catch (error) {
      throw NativeHostConnectionException('host.start_failed', '$error');
    }
    unawaited(process.stdout.drain<void>());
    unawaited(process.stderr.drain<void>());

    final connection = _MethodChannelBridgeConnection();
    try {
      await connection.connect(pipeName, connectTimeout);
      return _WindowsNativeHostPlatformLease(process, connection);
    } on Object {
      await connection.close();
      process.kill();
      try {
        await process.exitCode.timeout(const Duration(seconds: 3));
      } on TimeoutException {
        process.kill(ProcessSignal.sigkill);
      }
      rethrow;
    }
  }
}

final class _WindowsNativeHostPlatformLease implements NativeHostPlatformLease {
  _WindowsNativeHostPlatformLease(this._process, this.connection) {
    _processExit = _process.exitCode.then(
      (code) =>
          NativeHostTermination(code: 'host.process_exited', exitCode: code),
    );
    _terminated = Future.any([_processExit, connection.terminated]);
  }

  final Process _process;

  @override
  final _MethodChannelBridgeConnection connection;
  late final Future<NativeHostTermination> _processExit;
  late final Future<NativeHostTermination> _terminated;
  bool _closed = false;

  @override
  Future<NativeHostTermination> get terminated => _terminated;

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await connection.close();
    _process.kill();
    try {
      await _processExit.timeout(const Duration(seconds: 3));
    } on TimeoutException {
      _process.kill(ProcessSignal.sigkill);
      await _processExit;
    }
  }
}

final class _MethodChannelBridgeConnection implements BridgeConnection {
  static const MethodChannel _channel = MethodChannel('starbridge/native-host');

  final StreamController<BridgeEnvelope> _incoming =
      StreamController<BridgeEnvelope>.broadcast(sync: true);
  final Completer<NativeHostTermination> _termination = Completer();
  int? _nativeGeneration;
  bool _closed = false;

  @override
  Stream<BridgeEnvelope> get incoming => _incoming.stream;

  Future<NativeHostTermination> get terminated => _termination.future;

  Future<void> connect(String pipeName, Duration timeout) async {
    _channel.setMethodCallHandler(_handleNativeMethod);
    try {
      final generation = await _channel.invokeMethod<int>('connect', {
        'pipeName': pipeName,
        'timeoutMilliseconds': timeout.inMilliseconds,
      });
      if (generation == null || generation <= 0) {
        throw const NativeHostConnectionException(
          'host.pipe.invalid_generation',
        );
      }
      _nativeGeneration = generation;
    } on PlatformException catch (error) {
      await _finish(
        NativeHostTermination(code: error.code),
        notifyNative: false,
      );
      throw NativeHostConnectionException(error.code, error.message);
    } on MissingPluginException {
      await _finish(
        const NativeHostTermination(code: 'host.pipe.adapter_missing'),
        notifyNative: false,
      );
      throw const NativeHostConnectionException('host.pipe.adapter_missing');
    }
  }

  @override
  Future<void> send(BridgeEnvelope envelope) async {
    if (_closed || _nativeGeneration == null) {
      throw const BridgeDisconnectedException();
    }
    try {
      await _channel.invokeMethod<void>(
        'send',
        BridgeFrameCodec.encode(envelope),
      );
    } on PlatformException {
      throw const BridgeDisconnectedException();
    }
  }

  Future<void> _handleNativeMethod(MethodCall call) async {
    final arguments = call.arguments;
    if (arguments is! Map || arguments['generation'] != _nativeGeneration) {
      return;
    }
    if (call.method == 'frame') {
      final frame = arguments['frame'];
      if (frame is! Uint8List) {
        await _finish(
          const NativeHostTermination(code: 'host.pipe.invalid_frame'),
          notifyNative: true,
        );
        return;
      }
      try {
        _incoming.add(BridgeFrameCodec.decode(frame));
      } on Object catch (error, stackTrace) {
        _incoming.addError(error, stackTrace);
        await _finish(
          const NativeHostTermination(code: 'host.pipe.invalid_frame'),
          notifyNative: true,
        );
      }
      return;
    }
    if (call.method == 'disconnected') {
      final code = arguments['code'];
      await _finish(
        NativeHostTermination(
          code: code is String ? code : 'host.pipe.disconnected',
        ),
        notifyNative: false,
      );
    }
  }

  @override
  Future<void> close() => _finish(
    const NativeHostTermination(code: 'host.connection_closed'),
    notifyNative: true,
  );

  Future<void> _finish(
    NativeHostTermination termination, {
    required bool notifyNative,
  }) async {
    if (_closed) {
      return;
    }
    _closed = true;
    if (notifyNative) {
      try {
        await _channel.invokeMethod<void>('close');
      } on MissingPluginException {
        // The runner is already gone.
      } on PlatformException {
        // The pipe is already gone.
      }
    }
    _channel.setMethodCallHandler(null);
    if (!_termination.isCompleted) {
      _termination.complete(termination);
    }
    await _incoming.close();
  }
}
