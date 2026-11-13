import 'dart:io';

import 'package:fl_pi_llm/src/http.dart';
import 'package:test/test.dart';

void main() {
  test('a connection the runtime makes carries TCP keepalive', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    final task = await keepAliveConnect(Uri.parse('http://127.0.0.1:${server.port}/'), null, null);
    final s = await task.socket;
    addTearDown(s.destroy);
    expect(keepAliveOn(s), isTrue);
  });

  test('a plain socket has none until it is set', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    final s = await Socket.connect(InternetAddress.loopbackIPv4, server.port);
    addTearDown(s.destroy);
    expect(keepAliveOn(s), isFalse);
    expect(keepAlive(s), isTrue);
    expect(keepAliveOn(s), isTrue);
  });

  test('a direct https connection is secured here', () async {
    final c = keepAliveHttpClient();
    addTearDown(c.close);
    final res = await (await c.getUrl(Uri.parse('https://example.com/'))).close();
    expect(res.statusCode, lessThan(500));
    await res.drain<void>();
  }, skip: Platform.environment['FL_PI_LLM_NETWORK'] == null ? 'needs the network: FL_PI_LLM_NETWORK=1' : false);
}
