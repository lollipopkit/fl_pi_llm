part of '../tool.dart';

/// How the model loads a skill: its SKILL.md, then any other file of it the
/// SKILL.md points to. Not one of the tools on the tools page: it is how
/// skills work, offered whenever one is on, and it only reads what the user
/// installed. What it is and answers are fl_pi_llm's ([LlmSkills]).
final class TfSkill extends ToolFunc {
  static final instance = TfSkill._();

  /// Its group, for [LlmUi.offers].
  static const groupName = 'skill';

  TfSkill._() : super(name: LlmSkills.tool.name, parametersSchema: LlmSkills.tool.parameters);

  @override
  String get description => LlmSkills.tool.description;

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
    try {
      return LlmToolResult.text(LlmSkills.run(Skills.root, Skills.offered, args));
    } on SkillError catch (e) {
      throw ArgumentError(e.message);
    }
  }
}
