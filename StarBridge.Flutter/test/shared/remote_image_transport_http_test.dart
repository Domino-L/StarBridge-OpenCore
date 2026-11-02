import 'package:starbridge_flutter/shared/remote_image_loader.dart';

import '../support/remote_image_transport_http_fixture.dart';

void main() => imageTransportHttpCases((mode, now, createClient) {
  final loader = RemoteImageLoader(
    mode: mode,
    now: now,
    createClient: createClient,
  );
  return (
    load: (source) => loader.load(source),
    retire: loader.retireAsync,
    dispose: loader.dispose,
  );
});
