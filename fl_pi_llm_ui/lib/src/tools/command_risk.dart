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
    // Case kept: an option's meaning can hang on it (`awk -F` against `-f`).
    // The name patterns ignore it.
    RegExp ci(String pattern) => RegExp(pattern, caseSensitive: false);

    var normalized = command.trim();
    if (normalized.isEmpty) return CommandRisk.caution;

    // Read-only inspection commands commonly silence expected errors. Ignore
    // only these exact redirections before checking for writes.
    normalized = normalized.replaceAll(
      RegExp(r'\b[012]?>>?\s*/dev/null\b'),
      '',
    );

    final destructivePatterns = <RegExp>[
      ci(r'(^|[;&|]\s*)(sudo\s+)?rm\s'),
      ci(r'(^|[;&|]\s*)(sudo\s+)?(shred|wipefs|mkfs(\.[a-z0-9]+)?)\b'),
      ci(r'(^|[;&|]\s*)(sudo\s+)?dd\s+.*\bof='),
      // `\s`, not `\b`: a word boundary needs a word character before the
      // dash, so `\b-delete` never matched and `find -delete` read as a find.
      ci(r'\b(find|xargs)\b.*\s-delete\b'),
      ci(r'\b(find|xargs)\b.*\brm\b'),
      ci(r'\b(git\s+reset\s+--hard|git\s+clean\s+-[^\s]*f)\b'),
      ci(r'\b(docker|podman)\s+(system\s+)?prune\b'),
      ci(r'\bkubectl\s+delete\b'),
      ci(r'\b(drop|truncate)\s+(database|table)\b'),
      ci(r'\bdelete\s+from\b'),
      ci(r'(^|[;&|]\s*)(shutdown|reboot|poweroff|halt)\b'),
      ci(r'\b(remove-item|format-volume|clear-disk)\b'),
      ci(r'(^|[;&|]\s*)(del|rmdir)\s'),
      ci(r':\s*\(\s*\)\s*\{\s*:\s*\|\s*:\s*&\s*\}\s*;\s*:'),
    ];
    if (destructivePatterns.any((pattern) => pattern.hasMatch(normalized))) {
      return CommandRisk.destructive;
    }

    final mutatingPatterns = <RegExp>[
      ci(r'(^|[^<])>>?\s*[^&]'),
      ci(
        r'\|\s*(sudo\s+)?(sh|bash|zsh|fish|python\d*|perl|ruby|node|pwsh|powershell|cmd)\b',
      ),
      ci(r'(^|[;&|]\s*)(eval|source)\b|(^|[;&|]\s*)\.\s+'),
      // Command and process substitution: `<(…)` runs what is inside it
      // (`>(…)` is already a redirection above).
      ci(r'\$\(|`|<\('),
      ci(r'(^|[;&|]\s*)(sh|bash|zsh|fish)\s+-c\b'),
      ci(r'\bfind\b.*\s-exec(dir)?\b'),
      ci(r'\bawk\b.*\bsystem\s*\('),
      ci(r'(^|[;&|]\s*)(sudo\s+)?(mv|cp|touch|mkdir|chmod|chown|ln)\s'),
      ci(r'(^|[;&|]\s*)(sudo\s+)?tee\b'),
      // In place, as its own flag or among others (`-i`, `-i.bak`, `-Ei`), first
      // or not.
      ci(r'\bsed\s+([^;&|]*\s)?(-[a-z]*i|--in-place)([.=\s]|$)'),
      ci(
        r'\b(systemctl|service)\s+(start|stop|restart|reload|enable|disable|mask|unmask)\b',
      ),
      ci(r'(^|[;&|]\s*)(sudo\s+)?(kill|pkill|killall)\b'),
      ci(
        r'\b(apt|apt-get|dnf|yum|pacman|zypper|apk|brew|pip3?|npm|pnpm|yarn|cargo|gem)\s+(install|remove|erase|upgrade|update|add|del|purge|autoremove|uninstall)\b',
      ),
      ci(
        r'\b(docker|podman)\s+(start|stop|restart|rm|rmi|pull|push|build|run|exec)\b',
      ),
      ci(r'\b(docker|podman)\s+compose\s+(up|down|restart|pull|build)\b'),
      ci(
        r'\bkubectl\s+(apply|create|edit|patch|replace|scale|rollout|set)\b',
      ),
      ci(
        r'\bgit\s+(add|commit|push|pull|merge|rebase|checkout|switch|restore|tag)\b',
      ),
      ci(
        r'\b(curl|wget)\b.*\s(-o|--output|-x\s+(post|put|patch|delete)|--request\s+(post|put|patch|delete))\b',
      ),
      ci(
        r'\b(set-content|add-content|new-item|copy-item|move-item|rename-item|start-service|stop-service|restart-service)\b',
      ),
    ];
    if (mutatingPatterns.any((pattern) => pattern.hasMatch(normalized))) {
      return CommandRisk.caution;
    }

    // A command name, and the forms of its arguments that keep it a read:
    // [_Read.only] is the shape it must have, [_Read.unless] what writes,
    // sets or runs something. Both match the segment as written.
    final readOnly = <_Read>[
      _Read(ci(r'^(ls|pwd|whoami|id|groups|uname|uptime|cal)\b')),
      // A name, or `-F file`, sets it.
      _Read(
        ci(r'^hostname\b'),
        only: RegExp(r'^hostname(\s+-[a-zA-Z-]+)*\s*$'),
      ),
      // `-s`, `--set` and a bare `MMDDhhmm` set the clock.
      _Read(
        ci(r'^date\b'),
        unless: RegExp(r'\s(-[uR]*s|--set\b)|^date(\s+-\S+)*\s+\d'),
      ),
      _Read(ci(r'^(cat|head|tail|less|more|grep|egrep|fgrep|cut|wc|tr)\b')),
      // `--pre` runs a program on every file.
      _Read(ci(r'^rg\b'), unless: RegExp(r'\s--pre\b')),
      // A program from a file, a library or an extension can do anything;
      // `-i inplace` writes.
      _Read(
        ci(r'^awk\b'),
        unless: RegExp(r'\s(-[fEil]|--(file|exec|include|load)\b)'),
      ),
      // `-o` writes; the compressor is a program it runs.
      _Read(
        ci(r'^sort\b'),
        unless: RegExp(r'\s(-[a-zA-Z]*o|--(output|compress-program)\b)'),
      ),
      // A second operand is the file it writes.
      _Read(ci(r'^uniq\b'), unless: RegExp(r'^uniq\b(.*\s[^-\s]){2}')),
      // In place is caught as a change above. A script from a file, or the
      // `w`, `W` and `e` commands (and `s///w`, `s///e`), write and run.
      _Read(
        ci(r'^sed\b'),
        unless: RegExp(
          r'\s(-[a-zA-Z]*f|--file\b)'
          r'|(^|[^a-zA-Z_-])[wWe]([^a-zA-Z_]|$)'
          r'|/[gpiImM0-9]*[wWe]([^a-zA-Z_]|$)',
        ),
      ),
      _Read(
        ci(
          r'^(df|du|free|vmstat|iostat|mpstat|top|ps|pgrep|lsof|stat|readlink|realpath)\b',
        ),
      ),
      // `-C` compiles a magic file.
      _Read(ci(r'^file\b'), unless: RegExp(r'\s(-[a-zA-Z]*C|--compile\b)')),
      // `-exec` and `-delete` are caught above; these write or run too.
      _Read(
        ci(r'^find\b'),
        unless: RegExp(r'\s-(fprint0?|fprintf|fls|ok|okdir)\b'),
      ),
      _Read(ci(r'^(locate|which|whereis|type|command\s+-v)\b')),
      _Read(ci(r'^(netstat|ping|traceroute|tracepath|dig|nslookup|host)\b')),
      // An object, then nothing or a listing verb; `-b` runs a file of
      // commands.
      _Read(
        ci(r'^ip\b'),
        only: RegExp(
          r'^ip(\s+-[a-zA-Z0-9]+)*(\s+[a-z]+(\s+(show|list|ls|lst|get)\b.*)?)?$',
        ),
        unless: RegExp(r'\s-(b|batch|force)\b'),
      ),
      _Read(
        ci(r'^route\b'),
        only: ci(r'^route(\s+-\S+)*(\s+print\b.*)?$'),
        unless: ci(r'\s-[a-z]*f'),
      ),
      // An interface alone is shown; anything after it configures it.
      _Read(
        ci(r'^ifconfig\b'),
        only: RegExp(r'^ifconfig(\s+-[a-zA-Z]+)*(\s+[^-\s]\S*)?$'),
      ),
      // `-K` kills what it lists; `-D` dumps to a file.
      _Read(ci(r'^ss\b'), unless: RegExp(r'\s(-[a-zA-Z]*[KD]|--(kill|diag)\b)')),
      _Read(
        ci(r'^journalctl\b'),
        unless: RegExp(
          r'\s--(vacuum-|(rotate|flush|sync|relinquish-var|smart-relinquish-var|setup-keys|update-catalog)\b)',
        ),
      ),
      // Clearing the ring buffer, or setting the console.
      _Read(
        ci(r'^dmesg\b'),
        unless: RegExp(r'\s(-[a-zA-Z]*[cCDEn]|--(clear|read-clear|console-))'),
      ),
      _Read(
        ci(
          r'^(systemctl\s+(status|show|is-active|is-enabled|list-)|service\s+[^\s]+\s+status)\b',
        ),
      ),
      _Read(
        ci(r'^(docker|podman)\s+(ps|images|inspect|logs|stats|info|version)\b'),
      ),
      _Read(
        ci(r'^(docker|podman)\s+compose\s+(ps|logs|config|ls)\b'),
        unless: RegExp(r'\s(-o|--output)\b'),
      ),
      _Read(
        ci(
          r'^kubectl\s+(get|describe|logs|api-resources|api-versions|cluster-info|version)\b',
        ),
        unless: RegExp(r'\s--output-directory\b'),
      ),
      _Read(
        ci(r'^git\s+(status|diff|log|show|rev-parse|ls-files|ls-tree)\b'),
        unless: RegExp(r'\s--output(=|\s|$)'),
      ),
      // Listing only: a name creates one, `-d`, `-m`, `-c` delete, rename,
      // copy.
      _Read(
        ci(r'^git\s+branch\b'),
        only: RegExp(
          r'^git\s+branch(\s+(-[arv]+|--(all|remotes|verbose|show-current|no-color)))*\s*$',
        ),
      ),
      _Read(
        ci(r'^git\s+remote\b'),
        only: RegExp(r'^git\s+remote((\s+(-v|--verbose))?\s*$|\s+(show|get-url)\b)'),
      ),
      _Read(
        ci(
          r'^(get-[a-z0-9-]+|test-[a-z0-9-]+|select-[a-z0-9-]+|where-object|measure-object|compare-object|tasklist|systeminfo|dir|type)\b',
        ),
      ),
    ];

    bool isReadOnlySegment(String segment) {
      final stripped = segment
          .trim()
          .replaceFirst(ci(r'^sudo\s+'), '')
          .replaceFirst(ci(r'^(env\s+)?([a-z_][a-z0-9_]*=[^\s]+\s+)+'), '');
      return readOnly.any((read) => read.matches(stripped));
    }

    // Chained commands are not taken apart, so nothing can be established
    // about them — including that they change anything. `ls && pwd` is as
    // unanalysed here as `ls && rm -rf /`, and only the first of those two
    // would be a lie to call a system change.
    final chainCandidate = normalized.replaceAll(ci(r'\d*>&\d+'), '');
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

class _Read {
  _Read(this.name, {this.only, this.unless});

  final RegExp name;
  final RegExp? only;
  final RegExp? unless;

  bool matches(String segment) =>
      name.hasMatch(segment) &&
      (only?.hasMatch(segment) ?? true) &&
      !(unless?.hasMatch(segment) ?? false);
}
