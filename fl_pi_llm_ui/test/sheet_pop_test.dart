// A sheet's button that closes it with `context.pop` closes whatever the
// nearest navigator shows instead: `showSheet` puts the sheet on the
// root navigator, and an app that lays its settings out in panes (Server
// Box) has a navigator of its own in the pane. The sheet then stays, and
// its OK does nothing. `context.popSheet` is the one that reaches it.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('buttons and fields close sheets with popSheet', () {
    final offending = RegExp(r'(onTap|onSubmitted|onPressed):\s*(\(\)\s*=>\s*)?context\.pop\b');
    final hits = [
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>())
        if (f.path.endsWith('.dart') && !f.path.contains('/generated/'))
          for (final (i, line) in f.readAsLinesSync().indexed)
            if (offending.hasMatch(line)) '${f.path}:${i + 1}: ${line.trim()}',
    ];
    expect(hits, isEmpty);
  });
}
