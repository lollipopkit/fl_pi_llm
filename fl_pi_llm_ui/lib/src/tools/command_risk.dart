/// What a shell command can be seen to do, before it runs.
library;

/// How much of a command the local check could actually establish.
///
/// An allowlist, not a blocklist: [readOnly] is the only verdict that says
/// something positive about the command. [unknown] is what nothing matched —
/// which is a reason to withhold auto-running, and not a claim about what the
/// command does. Saying "changes the system" there contradicts the model's own
/// description of a `sleep`, and the contradiction is the app's fault.
///
/// Never serialised: computed from the command every time, so adding a value
/// here migrates nothing.
enum CommandRisk {
  readOnly,
  unknown,
  caution,
  destructive;

  /// The verdict on [command], from its shape alone: a POSIX or PowerShell
  /// command line, matched against what is known to read, change or destroy.
  static CommandRisk classify(String command) {
    var normalized = command.trim().toLowerCase();
    if (normalized.isEmpty) return CommandRisk.caution;

    // Read-only inspection commands commonly silence expected errors. Ignore
    // only these exact redirections before checking for writes.
    normalized = normalized.replaceAll(
      RegExp(r'\b[012]?>>?\s*/dev/null\b'),
      '',
    );

    final destructivePatterns = <RegExp>[
      RegExp(r'(^|[;&|]\s*)(sudo\s+)?rm\s'),
      RegExp(r'(^|[;&|]\s*)(sudo\s+)?(shred|wipefs|mkfs(\.[a-z0-9]+)?)\b'),
      RegExp(r'(^|[;&|]\s*)(sudo\s+)?dd\s+.*\bof='),
      // `\s`, not `\b`: a word boundary needs a word character before the
      // dash, so `\b-delete` never matched and `find -delete` read as a find.
      RegExp(r'\b(find|xargs)\b.*\s-delete\b'),
      RegExp(r'\b(find|xargs)\b.*\brm\b'),
      RegExp(r'\b(git\s+reset\s+--hard|git\s+clean\s+-[^\s]*f)\b'),
      RegExp(r'\b(docker|podman)\s+(system\s+)?prune\b'),
      RegExp(r'\bkubectl\s+delete\b'),
      RegExp(r'\b(drop|truncate)\s+(database|table)\b'),
      RegExp(r'\bdelete\s+from\b'),
      RegExp(r'(^|[;&|]\s*)(shutdown|reboot|poweroff|halt)\b'),
      RegExp(r'\b(remove-item|format-volume|clear-disk)\b'),
      RegExp(r'(^|[;&|]\s*)(del|rmdir)\s'),
      RegExp(r':\s*\(\s*\)\s*\{\s*:\s*\|\s*:\s*&\s*\}\s*;\s*:'),
    ];
    if (destructivePatterns.any((pattern) => pattern.hasMatch(normalized))) {
      return CommandRisk.destructive;
    }

    final mutatingPatterns = <RegExp>[
      RegExp(r'(^|[^<])>>?\s*[^&]'),
      RegExp(
        r'\|\s*(sudo\s+)?(sh|bash|zsh|fish|python\d*|perl|ruby|node|pwsh|powershell|cmd)\b',
      ),
      RegExp(r'(^|[;&|]\s*)(eval|source)\b|(^|[;&|]\s*)\.\s+'),
      RegExp(r'\$\(|`'),
      RegExp(r'(^|[;&|]\s*)(sh|bash|zsh|fish)\s+-c\b'),
      RegExp(r'\bfind\b.*\s-exec(dir)?\b'),
      RegExp(r'\bawk\b.*\bsystem\s*\('),
      RegExp(r'(^|[;&|]\s*)(sudo\s+)?(mv|cp|touch|mkdir|chmod|chown|ln)\s'),
      RegExp(r'(^|[;&|]\s*)(sudo\s+)?tee\b'),
      // In place, as its own flag or among others (`-i`, `-i.bak`, `-Ei`), first
      // or not.
      RegExp(r'\bsed\s+([^;&|]*\s)?(-[a-z]*i|--in-place)([.=\s]|$)'),
      RegExp(
        r'\b(systemctl|service)\s+(start|stop|restart|reload|enable|disable|mask|unmask)\b',
      ),
      RegExp(r'(^|[;&|]\s*)(sudo\s+)?(kill|pkill|killall)\b'),
      RegExp(
        r'\b(apt|apt-get|dnf|yum|pacman|zypper|apk|brew|pip3?|npm|pnpm|yarn|cargo|gem)\s+(install|remove|erase|upgrade|update|add|del|purge|autoremove|uninstall)\b',
      ),
      RegExp(
        r'\b(docker|podman)\s+(start|stop|restart|rm|rmi|pull|push|build|run|exec)\b',
      ),
      RegExp(r'\b(docker|podman)\s+compose\s+(up|down|restart|pull|build)\b'),
      RegExp(
        r'\bkubectl\s+(apply|create|edit|patch|replace|scale|rollout|set)\b',
      ),
      RegExp(
        r'\bgit\s+(add|commit|push|pull|merge|rebase|checkout|switch|restore|tag)\b',
      ),
      RegExp(
        r'\b(curl|wget)\b.*\s(-o|--output|-x\s+(post|put|patch|delete)|--request\s+(post|put|patch|delete))\b',
      ),
      RegExp(
        r'\b(set-content|add-content|new-item|copy-item|move-item|rename-item|start-service|stop-service|restart-service)\b',
      ),
    ];
    if (mutatingPatterns.any((pattern) => pattern.hasMatch(normalized))) {
      return CommandRisk.caution;
    }

    final readOnlyStarts = <RegExp>[
      RegExp(r'^(ls|pwd|whoami|id|groups|uname|hostname|uptime|date|cal)\b'),
      RegExp(
        // `sed` in place is caught as a change above; the lookahead that tried
        // to exclude it here also excluded every `sed`, since `\b` after
        // `sed ` needs a word character next.
        r'^(cat|head|tail|less|more|grep|egrep|fgrep|rg|awk|cut|sort|uniq|wc|tr|sed)\b',
      ),
      RegExp(
        r'^(df|du|free|vmstat|iostat|mpstat|top|ps|pgrep|lsof|stat|file|readlink|realpath)\b',
      ),
      RegExp(r'^(find|locate|which|whereis|type|command\s+-v)\b'),
      RegExp(
        r'^(ip|ss|netstat|ifconfig|route|ping|traceroute|tracepath|dig|nslookup|host)\b',
      ),
      RegExp(
        r'^(journalctl|dmesg|systemctl\s+(status|show|is-active|is-enabled|list-)|service\s+[^\s]+\s+status)\b',
      ),
      RegExp(
        r'^(docker|podman)\s+(ps|images|inspect|logs|stats|info|version)\b',
      ),
      RegExp(r'^(docker|podman)\s+compose\s+(ps|logs|config|ls)\b'),
      RegExp(
        r'^kubectl\s+(get|describe|logs|api-resources|api-versions|cluster-info|version)\b',
      ),
      RegExp(
        r'^git\s+(status|diff|log|show|branch|remote|rev-parse|ls-files|ls-tree)\b',
      ),
      RegExp(
        r'^(get-[a-z0-9-]+|test-[a-z0-9-]+|select-[a-z0-9-]+|where-object|measure-object|compare-object|tasklist|systeminfo|dir|type)\b',
      ),
    ];

    bool isReadOnlySegment(String segment) {
      final stripped = segment
          .trim()
          .replaceFirst(RegExp(r'^sudo\s+'), '')
          .replaceFirst(RegExp(r'^(env\s+)?([a-z_][a-z0-9_]*=[^\s]+\s+)+'), '');
      return readOnlyStarts.any((pattern) => pattern.hasMatch(stripped));
    }

    // Chained commands are not taken apart, so nothing can be established
    // about them — including that they change anything. `ls && pwd` is as
    // unanalysed here as `ls && rm -rf /`, and only the first of those two
    // would be a lie to call a system change.
    final chainCandidate = normalized.replaceAll(RegExp(r'\d*>&\d+'), '');
    if (RegExp(r'&&|\|\||[;\r\n]|&').hasMatch(chainCandidate)) {
      return CommandRisk.unknown;
    }

    final pipelineSegments = normalized.split('|');
    if (pipelineSegments.every(
      (segment) => segment.trim().isNotEmpty && isReadOnlySegment(segment),
    )) {
      return CommandRisk.readOnly;
    }
    // Matched nothing at all — not a known mutation, not a known read. `sleep`
    // lands here, and so does anything the lists have never heard of.
    return CommandRisk.unknown;
  }
}
