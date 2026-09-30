/// The wire protocol a model speaks. One of pi-ai's API implementations.
enum LlmApi {
  /// `/chat/completions`, and everything that copies it: OpenAI, DeepSeek,
  /// OpenRouter, Ollama, vLLM, LM Studio, and most gateways.
  openaiCompletions('openai-completions'),

  /// `/responses`.
  openaiResponses('openai-responses'),

  /// Anthropic's `/messages`, and the gateways that copy it.
  anthropicMessages('anthropic-messages'),

  /// Gemini's `generateContent`.
  googleGenerativeAi('google-generative-ai');

  const LlmApi(this.wire);

  /// The id pi-ai knows it by.
  final String wire;

  /// Whether an endpoint of this API lists its models at `{baseUrl}/models`.
  bool get listsModels => this == openaiCompletions || this == openaiResponses;

  static LlmApi? fromWire(String? s) {
    for (final v in values) {
      if (v.wire == s) return v;
    }
    return null;
  }
}

/// A model, named the way pi-ai names it: a provider and a model id.
final class LlmModelRef {
  const LlmModelRef(this.provider, this.id);

  factory LlmModelRef.fromJson(Map<String, Object?> j) =>
      LlmModelRef(j['provider'] as String, j['id'] as String);

  final String provider;
  final String id;

  Map<String, Object?> toJson() => {'provider': provider, 'id': id};

  @override
  bool operator ==(Object other) =>
      other is LlmModelRef && other.provider == provider && other.id == id;

  @override
  int get hashCode => Object.hash(provider, id);

  @override
  String toString() => '$provider/$id';
}

/// What pi-ai knows about a model.
final class LlmModelInfo {
  const LlmModelInfo(this.json);

  final Map<String, Object?> json;

  LlmModelRef get ref => LlmModelRef(provider, id);
  String get provider => json['provider'] as String;
  String get id => json['id'] as String;
  String get name => json['name'] as String? ?? id;
  LlmApi? get api => LlmApi.fromWire(json['api'] as String?);

  /// Whether it thinks before answering, and so takes a [ThinkingLevel].
  bool get reasoning => json['reasoning'] == true;
  bool get imageInput => (json['input'] as List?)?.contains('image') ?? false;
  int get contextWindow => json['contextWindow'] as int? ?? 0;
  int get maxTokens => json['maxTokens'] as int? ?? 0;

  /// USD per million tokens: `input`, `output`, `cacheRead`, `cacheWrite`.
  Map<String, num> get cost => ((json['cost'] as Map?) ?? const {}).cast<String, num>();

  @override
  String toString() => 'LlmModelInfo($provider/$id)';
}

/// A provider in pi-ai's catalog, or one the user added.
final class LlmProviderInfo {
  const LlmProviderInfo(this.json);

  final Map<String, Object?> json;

  String get id => json['id'] as String;
  String get name => json['name'] as String? ?? id;

  /// Added by the user through [FlPiLlm.setCustomProviders].
  bool get custom => json['custom'] == true;
  String? get baseUrl => json['baseUrl'] as String?;
  bool get apiKeyAuth => (json['auth'] as Map?)?['apiKey'] == true;
  bool get oauthAuth => (json['auth'] as Map?)?['oauth'] == true;

  List<LlmModelInfo> get models => [
    for (final m in (json['models'] as List? ?? const []))
      LlmModelInfo((m as Map).cast<String, Object?>()),
  ];

  @override
  String toString() => 'LlmProviderInfo($id)';
}

/// An endpoint the user adds, speaking one of the [LlmApi]s.
///
/// Its models are listed from `{baseUrl}/models` by
/// [FlPiLlm.refreshModels] and enriched with OpenRouter's metadata, unless
/// [models] names them.
final class LlmCustomProvider {
  const LlmCustomProvider({
    required this.id,
    required this.name,
    required this.api,
    required this.baseUrl,
    this.headers,
    this.models,
    this.allowInsecure = false,
  });

  factory LlmCustomProvider.fromJson(Map<String, Object?> j) => LlmCustomProvider(
    id: j['id'] as String,
    name: j['name'] as String? ?? j['id'] as String,
    api: LlmApi.fromWire(j['api'] as String?) ?? LlmApi.openaiCompletions,
    baseUrl: j['baseUrl'] as String,
    headers: (j['headers'] as Map?)?.cast<String, String>(),
    models: (j['models'] as List?)?.cast<String>(),
    allowInsecure: j['allowInsecure'] as bool? ?? false,
  );

  final String id;
  final String name;
  final LlmApi api;

  /// Including the version segment the API expects, e.g. `.../v1`.
  final String baseUrl;
  final Map<String, String>? headers;

  /// Model ids. An endpoint that [LlmApi.listsModels] adds its own list to
  /// these; for the other APIs they are the only models.
  final List<String>? models;

  /// Whether [baseUrl] may be plain `http` off this device. Without it such a
  /// request is refused: it would carry the API key readable to anyone on the
  /// path — see [FlPiLlm.fetchAllowed].
  final bool allowInsecure;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'api': api.wire,
    'baseUrl': baseUrl,
    'headers': ?headers,
    if (models != null) 'models': [for (final m in models!) {'id': m}],
  };

  /// For storage: [models] as plain ids.
  Map<String, Object?> toStoreJson() => {
    ...toJson(),
    'models': ?models,
    if (allowInsecure) 'allowInsecure': true,
  };
}

/// How much a reasoning model thinks.
enum ThinkingLevel { off, minimal, low, medium, high, xhigh }

/// When the older part of a conversation is summarised.
///
/// Compaction happens once the estimated context exceeds
/// `contextWindow - reserveTokens`; the newest `keepRecentTokens` are kept
/// verbatim and everything before them is replaced by a summary.
final class CompactionSettings {
  const CompactionSettings({
    this.enabled = true,
    this.reserveTokens = 16384,
    this.keepRecentTokens = 20000,
  });

  static const disabled = CompactionSettings(enabled: false);

  final bool enabled;
  final int reserveTokens;
  final int keepRecentTokens;

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'reserveTokens': reserveTokens,
    'keepRecentTokens': keepRecentTokens,
  };
}
