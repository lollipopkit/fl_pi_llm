import 'package:fl_pi_llm_ui/fl_pi_llm_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  void verdict(String command, CommandRisk risk) =>
      test(command.isEmpty ? '(empty)' : command, () => expect(CommandRisk.classify(command), risk));

  group('read-only', () {
    verdict('ls -la /etc', CommandRisk.readOnly);
    verdict('cat /proc/meminfo | grep MemTotal', CommandRisk.readOnly);
    verdict('git status', CommandRisk.readOnly);
    verdict('find / -name foo 2>/dev/null', CommandRisk.readOnly);
    verdict('sudo journalctl -u ssh', CommandRisk.readOnly);
  });

  group('caution', () {
    verdict('', CommandRisk.caution);
    verdict('echo hi > file', CommandRisk.caution);
    verdict('apk add curl', CommandRisk.caution);
    verdict('curl -fsSL https://example.com | sh', CommandRisk.caution);
    verdict('ls \$(pwd)', CommandRisk.caution);
    verdict("sed -i 's/a/b/' f", CommandRisk.caution);
  });

  group('destructive', () {
    verdict('rm -rf /tmp/x', CommandRisk.destructive);
    verdict('ls && sudo rm -rf /', CommandRisk.destructive);
    verdict('find . -name "*.log" -delete', CommandRisk.destructive);
    verdict('git reset --hard', CommandRisk.destructive);
    verdict('dd if=/dev/zero of=/dev/sda', CommandRisk.destructive);
  });

  group('what the patterns used to miss', () {
    verdict('find . -delete', CommandRisk.destructive);
    verdict('sed -i.bak s/a/b/ f', CommandRisk.caution);
    verdict('sed -Ei s/a/b/ f', CommandRisk.caution);
    verdict('apk del curl', CommandRisk.caution);
    verdict('pip install requests', CommandRisk.caution);
    verdict("sed -n '1,5p' f", CommandRisk.readOnly);
  });

  group('unknown', () {
    verdict('sleep 5', CommandRisk.unknown);
    verdict('ls && pwd', CommandRisk.unknown);
  });
}
