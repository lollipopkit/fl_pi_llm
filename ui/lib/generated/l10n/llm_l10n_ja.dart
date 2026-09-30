// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'llm_l10n.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class LlmLocalizationsJa extends LlmLocalizations {
  LlmLocalizationsJa([String locale = 'ja']) : super(locale);

  @override
  String get addServer => 'サーバーを追加';

  @override
  String get allow => '許可';

  @override
  String get allowAlways => '常に許可';

  @override
  String get allowedWithoutAsking => '確認なしで許可';

  @override
  String allowToolFmt(String tool) {
    return '$tool を許可しますか？';
  }

  @override
  String get allProviders => 'すべてのプロバイダー';

  @override
  String alreadyExists(String path) {
    return '$path は既に存在します';
  }

  @override
  String get attachment => '添付ファイル';

  @override
  String attachUnsupported(String name) {
    return '$name を添付できません: 画像と 512 KB までのテキストファイルのみ';
  }

  @override
  String get back => '戻る';

  @override
  String get builtIn => '組み込み';

  @override
  String get camera => 'カメラ';

  @override
  String charsFmt(int n) {
    return '$n 文字';
  }

  @override
  String get chatRead => 'チャットを読む';

  @override
  String get chatSearch => 'チャットを検索';

  @override
  String get compacted => '以前のメッセージは要約されました';

  @override
  String get compaction => '長いチャットを圧縮';

  @override
  String get compactionTip =>
      'チャットがモデルのコンテキストに収まらなくなると、以前のメッセージがモデル向けに要約されます。表示上はすべて残ります。';

  @override
  String connectedFmt(int n) {
    return '接続済み · $n 個のツール';
  }

  @override
  String get copied => 'コピーしました';

  @override
  String get customProvider => 'カスタムプロバイダー';

  @override
  String get defaultModel => 'デフォルトモデル';

  @override
  String get deleteKey => 'キーを削除';

  @override
  String get deny => '拒否';

  @override
  String get discard => '破棄';

  @override
  String get disconnected => '未接続';

  @override
  String get endpoint => 'エンドポイント';

  @override
  String get extraVars => '追加の変数';

  @override
  String get extraVarsTip =>
      '1 行に 1 つの KEY=VALUE。キー以外の設定が必要なプロバイダー向けです（Azure リソース、Cloudflare アカウント）。';

  @override
  String get favorite => 'お気に入り';

  @override
  String get history => '履歴';

  @override
  String get historyToolTip => '確認なしで他のチャットを検索・閲覧';

  @override
  String get httpToolTip => 'Web ページと API を取得';

  @override
  String get image => '画像';

  @override
  String invalidLinkFmt(Object uri) {
    return '不明なリンク：$uri';
  }

  @override
  String get key => 'キー';

  @override
  String get keyInKeychain => 'システムのキーチェーンに保存され、バックアップには含まれません。';

  @override
  String get mcpServers => 'MCP サーバー';

  @override
  String get memory => 'メモリ';

  @override
  String get memoryDelete => 'メモリを削除';

  @override
  String get memoryEdit => 'メモリを編集';

  @override
  String get memoryMove => 'メモリを移動';

  @override
  String get memorySearch => 'メモリを検索';

  @override
  String get memoryToolTip => 'モデルがチャットをまたいで保持するファイル。確認なしで読み書きします';

  @override
  String get memoryView => 'メモリを読む';

  @override
  String get memoryWrite => 'メモリを保存';

  @override
  String get message => 'メッセージ';

  @override
  String minutesSecondsFmt(int m, int s) {
    return '$m 分 $s 秒';
  }

  @override
  String get model => 'モデル';

  @override
  String modelsCountFmt(int n) {
    return '$n 個のモデル';
  }

  @override
  String get modelsListedTip =>
      '任意：エンドポイントの /models 一覧を取得します。一覧にない ID をここに追加してください。';

  @override
  String get modelsRequired => 'この API はモデル一覧を取得できません。モデル ID を 1 つ以上入力してください。';

  @override
  String moreFmt(int n) {
    return '他 $n 個';
  }

  @override
  String get noProviderKey => 'キーが設定されたプロバイダーがまだありません。追加するとチャットを始められます。';

  @override
  String get refreshModels => 'モデルを更新';

  @override
  String get regenerate => '再生成';

  @override
  String get replyInterrupted => '返信が中断されました';

  @override
  String get replyWaits => '返信はあなたの回答を待っています。';

  @override
  String get resumeReply => '続ける';

  @override
  String get sameAsChat => 'チャットと同じ';

  @override
  String get searchModels => 'モデルを検索';

  @override
  String get searchProviders => 'プロバイダーを検索';

  @override
  String secondsFmt(String n) {
    return '$n 秒';
  }

  @override
  String get send => '送信';

  @override
  String get systemPrompt => 'システムプロンプト';

  @override
  String get thought => '思考';

  @override
  String thoughtForFmt(String time) {
    return '$time 思考';
  }

  @override
  String get titleModel => 'タイトル用モデル';

  @override
  String tokensFmt(String n) {
    return '$n トークン';
  }

  @override
  String get tool => 'ツール';

  @override
  String get toolHttpReqName => 'HTTP要求';

  @override
  String get unsavedChanges => '離れる前に変更を保存しますか?';

  @override
  String get untitled => '無題';

  @override
  String usableModelsFmt(int n, int m) {
    return '$n 個使用可能 · $m 個のプロバイダー';
  }

  @override
  String get useTools => 'ツールを使う';

  @override
  String get useToolsTip => '下で許可したもの以外、呼び出しごとに確認します';

  @override
  String get allowInsecure => '平文の HTTP を許可';

  @override
  String get allowInsecureTip =>
      'このアドレスはこの端末以外の http:// です。API キーは暗号化されずに送信され、ネットワーク経路上の誰でも読み取れます。信頼できるネットワークでのみ許可してください。';

  @override
  String get configure => '設定';

  @override
  String get supportsThinking => '思考対応';

  @override
  String get thinkingEffort => '思考レベル';

  @override
  String get mcpHeaders => 'ヘッダー';

  @override
  String get mcpHeadersTip =>
      '任意。例: 名前 Authorization、値 Bearer <token>。この端末にのみ保存され、バックアップされず、このサーバーにのみ送信されます。';

  @override
  String get mcpHeadersInvalid => 'ヘッダーには英数字とハイフンからなる名前と、値が必要です。';

  @override
  String get mcpNeedsSignIn => 'サインインが必要です';

  @override
  String get mcpSigningIn => 'ブラウザでサインインを完了してください';

  @override
  String get mcpSignedIn => 'サインインしました。このページは閉じてかまいません。';

  @override
  String get mcpSignedInShort => 'サインイン済み';

  @override
  String get mcpSignInFailed => 'サインインに失敗しました。このページを閉じてやり直してください。';

  @override
  String get mcpInsecure => 'ヘッダーの送信やサインインは https のアドレスでのみ使えます。';

  @override
  String get mcpAddHeader => 'ヘッダーを追加';

  @override
  String get mcpNotSignedIn => '未サインイン';

  @override
  String get mcpSignInTip => 'OAuth を使うサーバー向けです。サインインはブラウザで行い、トークンは自動で更新されます。';
}
