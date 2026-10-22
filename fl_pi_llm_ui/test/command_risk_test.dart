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

  group('process substitution', () {
    verdict('cat <(touch x)', CommandRisk.caution);
    verdict('diff <(ls a) <(ls b)', CommandRisk.caution);
  });

  group('read-only by name, not by arguments', () {
    verdict('sort -o out in', CommandRisk.unknown);
    verdict('sort -u in', CommandRisk.readOnly);
    verdict('uniq in out', CommandRisk.unknown);
    verdict('uniq -c in', CommandRisk.readOnly);
    verdict("sed 's/a/b/w out' f", CommandRisk.unknown);
    verdict("sed '1e id' f", CommandRisk.unknown);
    verdict('sed -f script f', CommandRisk.unknown);
    verdict("sed -e 's/a/b/g' f", CommandRisk.readOnly);
    verdict("awk -F: '{print \$1}' /etc/passwd", CommandRisk.readOnly);
    verdict('awk -f prog.awk f', CommandRisk.unknown);
    verdict('awk -i inplace 1 f', CommandRisk.unknown);
    verdict('rg --pre ./x foo', CommandRisk.unknown);
    verdict('find . -fprint out', CommandRisk.unknown);
    verdict('find . -ok id ;', CommandRisk.unknown);
    verdict('file -C -m magic', CommandRisk.unknown);
    verdict('date -s 2020-01-01', CommandRisk.unknown);
    verdict('date 010100002020', CommandRisk.unknown);
    verdict('date -Iseconds', CommandRisk.readOnly);
    verdict('hostname newname', CommandRisk.unknown);
    verdict('hostname -f', CommandRisk.readOnly);
    verdict('ip link set eth0 down', CommandRisk.unknown);
    verdict('ip -br a', CommandRisk.readOnly);
    verdict('ip route get 1.1.1.1', CommandRisk.readOnly);
    verdict('ip -batch cmds', CommandRisk.unknown);
    verdict('ifconfig en0 down', CommandRisk.unknown);
    verdict('ifconfig en0', CommandRisk.readOnly);
    verdict('route add default gw 10.0.0.1', CommandRisk.unknown);
    verdict('route -n', CommandRisk.readOnly);
    verdict('ss -K dst 1.2.3.4', CommandRisk.unknown);
    verdict('ss -tlnp', CommandRisk.readOnly);
    verdict('journalctl --vacuum-size=1G', CommandRisk.unknown);
    verdict('dmesg -C', CommandRisk.unknown);
    verdict('dmesg -T', CommandRisk.readOnly);
    verdict('git diff --output=x', CommandRisk.unknown);
    verdict('git branch new', CommandRisk.unknown);
    verdict('git branch -D old', CommandRisk.unknown);
    verdict('git branch -a', CommandRisk.readOnly);
    verdict('git remote add o url', CommandRisk.unknown);
    verdict('git remote -v', CommandRisk.readOnly);
    verdict('docker compose config -o out.yml', CommandRisk.unknown);
    verdict('kubectl cluster-info dump --output-directory=d', CommandRisk.unknown);
    verdict('Get-ChildItem', CommandRisk.readOnly);
  });
}
