import 'dart:io';

import 'package:fl_pi_llm_ui/src/core/llm.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('chats count as encrypted only when a file is not SQLite in clear', () async {
    final dir = Directory.systemTemp.createTempSync('chat_key').path;
    addTearDown(() => Directory(dir).deleteSync(recursive: true));
    expect(await Llm.encryptedChats(dir), isFalse, reason: 'no chats yet');
    final chats = Directory('$dir/chats')..createSync();
    File('${chats.path}/a.db').writeAsBytesSync([...'SQLite format 3\u0000'.codeUnits, 1, 2, 3]);
    File('${chats.path}/empty.db').writeAsBytesSync([]);
    File('${chats.path}/a.db-wal').writeAsBytesSync(List.filled(32, 9));
    expect(await Llm.encryptedChats(dir), isFalse, reason: 'in clear, new, or not a chat');
    File('${chats.path}/b.db').writeAsBytesSync(List.filled(32, 7));
    expect(await Llm.encryptedChats(dir), isTrue);
  });
}
