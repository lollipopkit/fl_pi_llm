import 'package:fl_pi_llm_ui/generated/l10n/llm_l10n.dart';
import 'package:fl_pi_llm_ui/generated/l10n/llm_l10n_en.dart';
import 'package:flutter/widgets.dart';

/// The strings of this package, in the app's locale: set by
/// [LlmL10nX.setLlmL10n] where the app sets its own.
LlmLocalizations llmL10n = LlmLocalizationsEn();

extension LlmL10nX on BuildContext {
  /// English when the app's locale is one this package has no strings for:
  /// [LlmLocalizations.of] would throw there.
  void setLlmL10n() => llmL10n =
      Localizations.of<LlmLocalizations>(this, LlmLocalizations) ??
      LlmLocalizationsEn();
}
