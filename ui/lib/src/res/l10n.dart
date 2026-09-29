import 'package:fl_pi_llm_ui/generated/l10n/llm_l10n.dart';
import 'package:fl_pi_llm_ui/generated/l10n/llm_l10n_en.dart';
import 'package:flutter/widgets.dart';

/// The strings of this package, in the app's locale: set by
/// [LlmL10nX.setLlmL10n] where the app sets its own.
LlmLocalizations llmL10n = LlmLocalizationsEn();

extension LlmL10nX on BuildContext {
  void setLlmL10n() => llmL10n = LlmLocalizations.of(this);
}
