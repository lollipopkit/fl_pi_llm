import 'dart:io';
import 'dart:typed_data';

import 'package:meta/meta.dart';

/// The [HttpClient] a runtime makes for itself: one whose connections carry
/// TCP keepalive, so a connection that died unseen — dropped by a NAT or the
/// server while the app was suspended — fails within a minute or so of
/// silence, rather than leaving a reply waiting on it for good. A model
/// thinking without a word is not mistaken for that: the peer still answers
/// the probes.
HttpClient keepAliveHttpClient() => HttpClient()
  ..connectionTimeout = const Duration(seconds: 30)
  ..connectionFactory = keepAliveConnect;

/// [HttpClient.connectionFactory]: a direct `https` connection is secured
/// here, as the client leaves that to the factory; through a proxy, the
/// client tunnels and secures it itself.
@visibleForTesting
Future<ConnectionTask<Socket>> keepAliveConnect(Uri uri, String? proxyHost, int? proxyPort) async {
  final direct = proxyHost == null;
  final task = await Socket.startConnect(proxyHost ?? uri.host, proxyPort ?? uri.port);
  Socket? connected;
  return ConnectionTask.fromSocket(
    task.socket.then((s) {
      connected = s;
      keepAlive(s);
      return direct && uri.isScheme('https') ? SecureSocket.secure(s, host: uri.host) : s;
    }),
    // A timeout may end it in the handshake, past what the task cancels.
    () {
      task.cancel();
      connected?.destroy();
    },
  );
}

/// Probes after [_idle] of silence, every [_interval], [_count] times.
const _idle = Duration(seconds: 30);
const _interval = Duration(seconds: 10);
const _count = 3;

/// `SO_KEEPALIVE`, then the idle, interval and count `IPPROTO_TCP` options,
/// as each platform numbers them.
final _options = switch (Platform.operatingSystem) {
  'linux' || 'android' => (9, 4, 5, 6),
  'macos' || 'ios' => (0x8, 0x10, 0x101, 0x102),
  'windows' => (0x8, 3, 17, 16),
  _ => null,
};

/// Turns on TCP keepalive on [s], where the platform has it.
@visibleForTesting
bool keepAlive(Socket s) {
  final o = _options;
  if (o == null) return false;
  final (on, idleOpt, intervalOpt, countOpt) = o;
  try {
    s.setRawOption(RawSocketOption.fromInt(RawSocketOption.levelSocket, on, 1));
    s.setRawOption(RawSocketOption.fromInt(RawSocketOption.levelTcp, idleOpt, _idle.inSeconds));
    s.setRawOption(RawSocketOption.fromInt(RawSocketOption.levelTcp, intervalOpt, _interval.inSeconds));
    s.setRawOption(RawSocketOption.fromInt(RawSocketOption.levelTcp, countOpt, _count));
    return true;
  } on SocketException {
    // An older kernel without one of them: what was set stays.
    return false;
  }
}

/// Whether [s] has keepalive on: for a test.
@visibleForTesting
bool keepAliveOn(Socket s) {
  final o = _options;
  if (o == null) return false;
  final v = s.getRawOption(RawSocketOption(RawSocketOption.levelSocket, o.$1, Uint8List(4)));
  return v.any((b) => b != 0);
}
