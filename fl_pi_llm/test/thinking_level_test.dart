import 'package:fl_pi_llm/fl_pi_llm.dart';
import 'package:test/test.dart';

void main() {
  LlmModelInfo model(List<String>? levels, {bool reasoning = true}) => LlmModelInfo({
    'provider': 'p',
    'id': 'm',
    'reasoning': reasoning,
    'thinkingLevels': ?levels,
  });

  // pi-ai's deepseek/deepseek-flash.
  final deepseek = model(['off', 'low', 'high', 'max']);

  test('the levels pi-ai lists, in order', () {
    expect(deepseek.thinkingLevels, [ThinkingLevel.off, ThinkingLevel.low, ThinkingLevel.high, ThinkingLevel.max]);
  });

  test('a model that does not reason only takes off', () {
    expect(model(['off', 'low'], reasoning: false).thinkingLevels, [ThinkingLevel.off]);
    expect(model(null).thinkingLevels, [ThinkingLevel.off]);
  });

  test('a level it does not take moves up, then down', () {
    expect(deepseek.clampThinking(ThinkingLevel.high), ThinkingLevel.high);
    expect(deepseek.clampThinking(ThinkingLevel.minimal), ThinkingLevel.low);
    expect(deepseek.clampThinking(ThinkingLevel.medium), ThinkingLevel.high);
    expect(deepseek.clampThinking(ThinkingLevel.xhigh), ThinkingLevel.max);
    final noMax = model(['low', 'high']);
    expect(noMax.clampThinking(ThinkingLevel.max), ThinkingLevel.high);
    expect(noMax.clampThinking(ThinkingLevel.off), ThinkingLevel.low);
  });
}
