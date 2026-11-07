import 'dart:convert';

import 'rust/api/permissions.dart' as rs;

/// What a chat or task runs in: `manual` asks, `auto` has a model judge,
/// `bypass` runs — see [LlmPermissionRules.decide].
enum LlmPermissionMode {
  auto,
  manual,
  bypass;

  /// Null for none and for a mode this build does not know.
  static LlmPermissionMode? maybe(Object? name) {
    for (final m in values) {
      if (m.name == name) return m;
    }
    return null;
  }

  /// [manual] for none and for a mode this build does not know: the safe one.
  static LlmPermissionMode of(Object? name) => maybe(name) ?? manual;
}

/// One of the auto mode judge's prose lists, by its key in `autoMode`.
enum LlmAutoRuleKind {
  environment('environment'),
  allow('allow'),
  softDeny('soft_deny'),
  hardDeny('hard_deny');

  const LlmAutoRuleKind(this.key);
  final String key;
}

/// What a call does: the higher of the model's claim and what the call
/// looks like.
enum LlmEffect { read, change, danger }

/// What a shell command is worth by its shape alone.
enum LlmCommandRisk { readOnly, unknown, caution, destructive }

/// How tool calls are approved: the mode new chats and tasks start in, the
/// command rules and the auto mode judge's, in the shape a monitor's
/// `/agent/permissions` has. Sent back whole: a field or mode this build does
/// not know survives through [raw].
final class LlmPermissions {
  const LlmPermissions({
    this.defaultMode = LlmPermissionMode.manual,
    this.disableBypass = false,
    this.allow = const [],
    this.ask = const [],
    this.deny = const [],
    this.autoMode = const {},
    this.raw = const {},
  });

  factory LlmPermissions.fromJson(Map<String, dynamic> j) {
    final rules = j['rules'] as Map? ?? const {};
    final auto = j['autoMode'] as Map? ?? const {};
    final mode = j['defaultMode'];
    return LlmPermissions(
      defaultMode: mode == null ? LlmPermissionMode.manual : LlmPermissionMode.maybe(mode),
      disableBypass: j['disableBypass'] == true,
      allow: _strings(rules['allow']),
      ask: _strings(rules['ask']),
      deny: _strings(rules['deny']),
      autoMode: {
        for (final k in LlmAutoRuleKind.values)
          if (auto[k.key] is List) k: _strings(auto[k.key]),
      },
      raw: j,
    );
  }

  /// Null for a mode this build does not know, which is sent back as it came.
  final LlmPermissionMode? defaultMode;
  final bool disableBypass;
  final List<String> allow;
  final List<String> ask;
  final List<String> deny;

  /// A list absent is the built-in one.
  final Map<LlmAutoRuleKind, List<String>> autoMode;

  /// What was read, so a field this build does not know survives a save.
  final Map<String, dynamic> raw;

  /// The mode new chats run in: [defaultMode], never a bypass turned off.
  LlmPermissionMode get mode {
    final m = defaultMode ?? LlmPermissionMode.manual;
    return m == LlmPermissionMode.bypass && disableBypass ? LlmPermissionMode.manual : m;
  }

  LlmPermissions copyWith({
    LlmPermissionMode? defaultMode,
    bool? disableBypass,
    List<String>? allow,
    List<String>? ask,
    List<String>? deny,
    Map<LlmAutoRuleKind, List<String>>? autoMode,
  }) => LlmPermissions(
    defaultMode: defaultMode ?? this.defaultMode,
    disableBypass: disableBypass ?? this.disableBypass,
    allow: allow ?? this.allow,
    ask: ask ?? this.ask,
    deny: deny ?? this.deny,
    autoMode: autoMode ?? this.autoMode,
    raw: raw,
  );

  Map<String, dynamic> toJson() {
    final rules = raw['rules'] is Map ? Map<String, dynamic>.of((raw['rules'] as Map).cast()) : <String, dynamic>{};
    final auto = raw['autoMode'] is Map ? Map<String, dynamic>.of((raw['autoMode'] as Map).cast()) : <String, dynamic>{};
    for (final k in LlmAutoRuleKind.values) {
      auto.remove(k.key);
    }
    return {
      ...raw,
      'defaultMode': defaultMode?.name ?? raw['defaultMode'],
      'disableBypass': disableBypass,
      'rules': {...rules, 'allow': allow, 'ask': ask, 'deny': deny},
      'autoMode': {...auto, for (final e in autoMode.entries) e.key.key: e.value},
    };
  }
}

/// [LlmPermissions] with the built-in auto mode lists.
final class LlmPermissionsView {
  const LlmPermissionsView({required this.permissions, required this.defaults});

  factory LlmPermissionsView.fromJson(Map<String, dynamic> j) {
    final defaults = j['defaults'] as Map? ?? const {};
    return LlmPermissionsView(
      permissions: LlmPermissions.fromJson((j['permissions'] as Map?)?.cast() ?? const {}),
      defaults: {for (final k in LlmAutoRuleKind.values) k: _strings(defaults[k.key])},
    );
  }

  final LlmPermissions permissions;
  final Map<LlmAutoRuleKind, List<String>> defaults;
}

/// What becomes of one call — see [LlmPermissionRules.decide].
sealed class LlmDecision {
  const LlmDecision();
}

final class LlmRun extends LlmDecision {
  const LlmRun();
}

/// The person decides; [danger] is a call that loses something for good.
/// [allowRule] would cover it, to offer.
final class LlmAsk extends LlmDecision {
  const LlmAsk({required this.danger, this.allowRule});

  final bool danger;
  final String? allowRule;
}

/// The auto mode judge decides; no verdict asks.
final class LlmJudge extends LlmDecision {
  const LlmJudge();
}

/// A deny rule refused it; [message] is what the model is told.
final class LlmDeny extends LlmDecision {
  const LlmDeny({required this.rule, required this.message});

  final String rule;
  final String message;
}

/// `fl_pi_llm::permissions`, the one logic every agent on fl_pi_llm decides
/// by: deny, ask and allow rules first; then what is known to read; then the
/// mode.
abstract final class LlmPermissionRules {
  static LlmCommandRisk classify(String command) => switch (rs.permissionsClassify(command: command)) {
    'readOnly' => LlmCommandRisk.readOnly,
    'caution' => LlmCommandRisk.caution,
    'destructive' => LlmCommandRisk.destructive,
    _ => LlmCommandRisk.unknown,
  };

  /// Why [p] cannot be stored; null when it can.
  static String? check(LlmPermissions p) => rs.permissionsCheck(permissions: jsonEncode(p.toJson()));

  /// The built-in auto mode lists, around [environment]: where the calls run
  /// and what is sensitive there.
  static Map<LlmAutoRuleKind, List<String>> defaults(List<String> environment) {
    final j = jsonDecode(rs.permissionsDefaults(environment: environment)) as Map;
    return {for (final k in LlmAutoRuleKind.values) k: _strings(j[k.key])};
  }

  /// What becomes of a call in [mode]: [command] is the shell command it
  /// runs, none for a tool that runs none; [claimed] what it is said to do,
  /// raised to the command's shape.
  static LlmDecision decide(
    LlmPermissions p,
    LlmPermissionMode mode, {
    String? command,
    required LlmEffect claimed,
  }) {
    final j = jsonDecode(
      rs.permissionsDecide(permissions: jsonEncode(p.toJson()), mode: mode.name, command: command, claimed: claimed.name),
    ) as Map;
    return switch (j['decision']) {
      'run' => const LlmRun(),
      'judge' => const LlmJudge(),
      'deny' => LlmDeny(rule: j['rule'] as String, message: j['message'] as String),
      _ => LlmAsk(danger: j['danger'] == true, allowRule: j['allowRule'] as String?),
    };
  }

  /// The judge's instructions.
  static String judgePrompt(LlmPermissions p, List<String> environment) =>
      rs.permissionsJudgePrompt(permissions: jsonEncode(p.toJson()), environment: environment);

  /// What the judge is shown: the person's words and the commands that ran,
  /// from [entries], then [subject].
  static String judgeInput(List<Map<String, Object?>> entries, String subject, {String title = '', LlmEffect claimed = LlmEffect.change}) =>
      rs.permissionsJudgeInput(entries: jsonEncode(entries), command: subject, title: title, claimed: claimed.name);

  /// The judge's answer: allowed, or blocked with what the model is told;
  /// null when it said nothing usable.
  static ({bool allowed, String? message})? judgment(String text) {
    final s = rs.permissionsJudgment(text: text);
    if (s == null) return null;
    final j = jsonDecode(s) as Map;
    return j['decision'] == 'allow' ? (allowed: true, message: null) : (allowed: false, message: j['message'] as String?);
  }
}

List<String> _strings(Object? raw) => [
  for (final s in raw as List? ?? const [])
    if (s is String) s,
];
