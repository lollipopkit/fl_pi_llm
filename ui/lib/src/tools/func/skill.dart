part of '../tool.dart';

/// How the model loads a skill: its SKILL.md, then any other file of it the
/// SKILL.md points to. Not one of the tools on the tools page: it is how
/// skills work, offered whenever one is on, and it only reads what the user
/// installed.
final class TfSkill extends ToolFunc {
  static const instance = TfSkill._();

  /// Its group, for [LlmUi.offers].
  static const groupName = 'skill';

  const TfSkill._()
    : super(
        name: 'skill',
        parametersSchema: const {
          'type': 'object',
          'properties': {
            'name': {'type': 'string', 'description': 'The skill, as the list of available skills names it.'},
            'file': {
              'type': 'string',
              'description': 'A file of the skill, by its path relative to the skill. Default: SKILL.md, with the list of its files.',
            },
          },
          'required': ['name'],
        },
      );

  @override
  String get description =>
      'Load an installed skill: its instructions (SKILL.md) and the list of its files, or one of those files.';

  @override
  String get l10nName => llmL10n.skills;

  @override
  String get group => groupName;

  @override
  bool get trusted => true;

  @override
  IconData get icon => Icons.auto_stories_outlined;

  @override
  String summary(_Map args) => [args['name'], ?args['file']].join(' · ');

  @override
  Future<LlmToolResult> run(_Map args, ToolCtx ctx) async {
    final name = args['name'];
    if (name is! String) throw ArgumentError('name is required');
    final skill = Skills.byDir(name) ?? Skills.enabled.firstWhereOrNull((s) => s.name == name);
    if (skill == null || !skill.enabled) {
      throw ArgumentError('No skill "$name". Available: ${Skills.enabled.map((s) => s.dir).join(', ')}');
    }
    final file = args['file'] is String && (args['file'] as String).isNotEmpty ? args['file'] as String : null;
    final text = Skills.read(skill.dir, file ?? 'SKILL.md');
    if (text == null) throw ArgumentError('No text file "${file ?? 'SKILL.md'}" in ${skill.dir}');
    final cut = text.length > Skills.maxReadChars;
    final body = cut ? '${text.substring(0, Skills.maxReadChars)}\n… (truncated)' : text;
    if (file != null) return LlmToolResult.text(body);
    final others = Skills.filesOf(skill.dir).where((f) => f != 'SKILL.md').toList();
    return LlmToolResult.text([
      body,
      if (others.isNotEmpty) '\nFiles of this skill (read one with `file`):\n${others.take(200).map((f) => '- $f').join('\n')}',
    ].join('\n'));
  }
}
