// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'llm_l10n.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class LlmLocalizationsZh extends LlmLocalizations {
  LlmLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get addServer => '添加服务器';

  @override
  String get allow => '允许';

  @override
  String get allowAlways => '始终允许';

  @override
  String get allowedWithoutAsking => '无需询问即可使用';

  @override
  String allowToolFmt(String tool) {
    return '允许$tool？';
  }

  @override
  String get allProviders => '全部提供商';

  @override
  String alreadyExists(String path) {
    return '$path 已存在';
  }

  @override
  String get attachment => '附件';

  @override
  String attachUnsupported(String name) {
    return '无法附加 $name:仅支持图片和 512 KB 以内的文本文件';
  }

  @override
  String get back => '返回';

  @override
  String get builtIn => '内置';

  @override
  String get camera => '相机';

  @override
  String charsFmt(int n) {
    return '$n 字符';
  }

  @override
  String get chatRead => '读取对话';

  @override
  String get chatSearch => '搜索对话';

  @override
  String get compacted => '较早的消息已被总结';

  @override
  String get compaction => '压缩长对话';

  @override
  String get compactionTip => '对话超出模型上下文时，较早的消息会被总结后发给模型；你仍然能看到全部消息。';

  @override
  String connectedFmt(int n) {
    return '已连接 · $n 个工具';
  }

  @override
  String get copied => '已复制';

  @override
  String get customProvider => '自定义提供商';

  @override
  String get defaultModel => '默认模型';

  @override
  String get deleteKey => '删除密钥';

  @override
  String get deny => '拒绝';

  @override
  String get discard => '放弃';

  @override
  String get disconnected => '未连接';

  @override
  String get endpoint => '端点';

  @override
  String get extraVars => '额外变量';

  @override
  String get extraVarsTip =>
      '每行一个 KEY=VALUE，用于需要不止一个 key 的提供商（如 Azure 资源、Cloudflare 账号）。';

  @override
  String get favorite => '收藏';

  @override
  String get history => '历史';

  @override
  String get historyToolTip => '搜索和读取其他对话,无需确认';

  @override
  String get httpToolTip => '获取网页和 API';

  @override
  String get image => '图片';

  @override
  String invalidLinkFmt(Object uri) {
    return '未知链接：$uri';
  }

  @override
  String get key => '密钥';

  @override
  String get keyInKeychain => '保存在系统钥匙串中，不会进入备份。';

  @override
  String get mcpServers => 'MCP 服务器';

  @override
  String get memory => '记忆';

  @override
  String get memoryDelete => '删除记忆';

  @override
  String get memoryEdit => '编辑记忆';

  @override
  String get memoryMove => '移动记忆';

  @override
  String get memorySearch => '搜索记忆';

  @override
  String get memoryToolTip => '模型跨对话保存的文件,读写无需确认';

  @override
  String get memoryView => '读取记忆';

  @override
  String get memoryWrite => '保存记忆';

  @override
  String get message => '消息';

  @override
  String minutesSecondsFmt(int m, int s) {
    return '$m 分 $s 秒';
  }

  @override
  String get model => '模型';

  @override
  String modelsCountFmt(int n) {
    return '$n 个模型';
  }

  @override
  String get modelsListedTip => '可选：会自动获取端点 /models 的模型列表，此处补充其中没有的 ID。';

  @override
  String get modelsRequired => '该 API 无法获取模型列表，请至少填写一个模型 ID。';

  @override
  String moreFmt(int n) {
    return '还有 $n 个';
  }

  @override
  String get noProviderKey => '还没有任何提供商配置了 key，添加一个即可开始对话。';

  @override
  String get refreshModels => '刷新模型';

  @override
  String get regenerate => '重新生成';

  @override
  String get replyInterrupted => '回复被中断';

  @override
  String get replyWaits => '回复会等待你的决定。';

  @override
  String get resumeReply => '继续';

  @override
  String get sameAsChat => '与对话相同';

  @override
  String get searchModels => '搜索模型';

  @override
  String get searchProviders => '搜索提供商';

  @override
  String secondsFmt(String n) {
    return '$n 秒';
  }

  @override
  String get send => '发送';

  @override
  String get systemPrompt => '系统提示词';

  @override
  String get thought => '已思考';

  @override
  String thoughtForFmt(String time) {
    return '思考了 $time';
  }

  @override
  String get titleModel => '生成标题的模型';

  @override
  String tokensFmt(String n) {
    return '$n tokens';
  }

  @override
  String get tool => '工具';

  @override
  String get toolHttpReqName => 'Http 请求';

  @override
  String get unsavedChanges => '离开前保存更改?';

  @override
  String get untitled => '未命名';

  @override
  String usableModelsFmt(int n, int m) {
    return '$n 个可用 · $m 个提供商';
  }

  @override
  String get useTools => '使用工具';

  @override
  String get useToolsTip => '每次调用都会先询问，除非已在下方允许';

  @override
  String get allowInsecure => '允许明文 HTTP';

  @override
  String get allowInsecureTip =>
      '该地址是本机以外的 http://，API Key 会以明文发送，网络路径上的任何人都能读取。仅在可信网络中开启。';

  @override
  String get configure => '配置';

  @override
  String get supportsThinking => '支持思考';

  @override
  String get thinkingEffort => '思考强度';

  @override
  String get mcpHeaders => '请求头';

  @override
  String get mcpHeadersTip =>
      '可选，例如名称 Authorization、值 Bearer <token>。只保存在本机，不会备份，只发送给该服务器。';

  @override
  String get mcpHeadersInvalid => '请求头需要名称和值，名称只能包含字母、数字和连字符。';

  @override
  String get mcpNeedsSignIn => '需要登录';

  @override
  String get mcpSigningIn => '请在浏览器中完成登录';

  @override
  String get mcpSignedIn => '已登录，可以关闭此页面。';

  @override
  String get mcpSignedInShort => '已登录';

  @override
  String get mcpSignInFailed => '登录失败，可以关闭此页面后重试。';

  @override
  String get mcpInsecure => '只有 https 地址可以使用请求头或登录。';

  @override
  String get mcpAddHeader => '添加请求头';

  @override
  String get mcpNotSignedIn => '未登录';

  @override
  String get mcpSignInTip => '适用于使用 OAuth 的服务器。在浏览器中完成登录，token 会自动续期。';

  @override
  String get mcpConnecting => '连接中…';

  @override
  String get skills => 'Skills';

  @override
  String get skillsTip => '特定任务的操作说明，任务符合时模型会读取并遵循。只安装你信任的来源：模型会按 skill 的内容执行。';

  @override
  String get skillSourceInvalid => '无法识别：请输入仓库、链接或 `npx skills add` 命令';

  @override
  String get skillsNotFound => '没有找到 skill';

  @override
  String get skillsPick => '选择要安装的 skill';

  @override
  String skillsInstalledFmt(int n) {
    return '已安装 $n 个';
  }

  @override
  String get skillsUpToDate => '已是最新';

  @override
  String skillsUpdatedFmt(int n) {
    return '已更新 $n 个';
  }

  @override
  String get skillsFromFolder => '从文件夹安装';

  @override
  String get skillsFromZip => '从 .zip 安装';

  @override
  String skillsUpdateFailedFmt(int n) {
    return '$n 个来源检查失败';
  }

  @override
  String get skillBuiltin => '内置';

  @override
  String keyFromEnvFmt(String name) {
    return 'key 来自 $name';
  }

  @override
  String keyFromEnvTipFmt(String name) {
    return '当前使用环境变量 $name 中的 key。在此填写的 key 会优先使用。';
  }

  @override
  String get skillUpdateAvailable => '有更新';

  @override
  String skillsUpdateAllFmt(int n) {
    return '全部更新（$n）';
  }
}

/// The translations for Chinese, as used in Taiwan (`zh_TW`).
class LlmLocalizationsZhTw extends LlmLocalizationsZh {
  LlmLocalizationsZhTw() : super('zh_TW');

  @override
  String get addServer => '新增伺服器';

  @override
  String get allow => '允許';

  @override
  String get allowAlways => '一律允許';

  @override
  String get allowedWithoutAsking => '無需詢問即可使用';

  @override
  String allowToolFmt(String tool) {
    return '允許$tool？';
  }

  @override
  String get allProviders => '全部提供者';

  @override
  String alreadyExists(String path) {
    return '$path 已存在';
  }

  @override
  String get attachment => '附件';

  @override
  String attachUnsupported(String name) {
    return '無法附加 $name:僅支援圖片和 512 KB 以內的文字檔';
  }

  @override
  String get back => '返回';

  @override
  String get builtIn => '內建';

  @override
  String get camera => '相機';

  @override
  String charsFmt(int n) {
    return '$n 字元';
  }

  @override
  String get chatRead => '讀取對話';

  @override
  String get chatSearch => '搜尋對話';

  @override
  String get compacted => '較早的訊息已被摘要';

  @override
  String get compaction => '壓縮長對話';

  @override
  String get compactionTip => '當對話超出模型的上下文時，較早的訊息會為模型摘要。你仍可看到全部訊息。';

  @override
  String connectedFmt(int n) {
    return '已連線 · $n 個工具';
  }

  @override
  String get copied => '已複製';

  @override
  String get customProvider => '自訂提供者';

  @override
  String get defaultModel => '預設模型';

  @override
  String get deleteKey => '刪除金鑰';

  @override
  String get deny => '拒絕';

  @override
  String get discard => '捨棄';

  @override
  String get disconnected => '未連線';

  @override
  String get endpoint => '端點';

  @override
  String get extraVars => '額外變數';

  @override
  String get extraVarsTip =>
      '每行一個 KEY=VALUE，用於除金鑰外還需要其他設定的提供者（Azure 資源、Cloudflare 帳號）。';

  @override
  String get favorite => '收藏';

  @override
  String get history => '歷史';

  @override
  String get historyToolTip => '搜尋和讀取其他對話,無需確認';

  @override
  String get httpToolTip => '取得網頁和 API';

  @override
  String get image => '圖片';

  @override
  String invalidLinkFmt(Object uri) {
    return '未知連結：$uri';
  }

  @override
  String get key => '金鑰';

  @override
  String get keyInKeychain => '儲存在系統鑰匙圈中，不會進入備份。';

  @override
  String get mcpServers => 'MCP 伺服器';

  @override
  String get memory => '記憶';

  @override
  String get memoryDelete => '刪除記憶';

  @override
  String get memoryEdit => '編輯記憶';

  @override
  String get memoryMove => '移動記憶';

  @override
  String get memorySearch => '搜尋記憶';

  @override
  String get memoryToolTip => '模型跨對話保存的檔案,讀寫無需確認';

  @override
  String get memoryView => '讀取記憶';

  @override
  String get memoryWrite => '儲存記憶';

  @override
  String get message => '訊息';

  @override
  String minutesSecondsFmt(int m, int s) {
    return '$m 分 $s 秒';
  }

  @override
  String get model => '模型';

  @override
  String modelsCountFmt(int n) {
    return '$n 個模型';
  }

  @override
  String get modelsListedTip => '可選：會自動取得端點 /models 的模型清單，此處補充其中沒有的 ID。';

  @override
  String get modelsRequired => '此 API 無法取得模型清單，請至少填寫一個模型 ID。';

  @override
  String moreFmt(int n) {
    return '還有 $n 個';
  }

  @override
  String get noProviderKey => '還沒有提供者設定了金鑰。新增一個即可開始聊天。';

  @override
  String get refreshModels => '重新整理模型';

  @override
  String get regenerate => '重新生成';

  @override
  String get replyInterrupted => '回覆被中斷';

  @override
  String get replyWaits => '回覆會等待你的決定。';

  @override
  String get resumeReply => '繼續';

  @override
  String get sameAsChat => '與對話相同';

  @override
  String get searchModels => '搜尋模型';

  @override
  String get searchProviders => '搜尋提供者';

  @override
  String secondsFmt(String n) {
    return '$n 秒';
  }

  @override
  String get send => '傳送';

  @override
  String get systemPrompt => '系統提示詞';

  @override
  String get thought => '已思考';

  @override
  String thoughtForFmt(String time) {
    return '思考了 $time';
  }

  @override
  String get titleModel => '標題模型';

  @override
  String tokensFmt(String n) {
    return '$n tokens';
  }

  @override
  String get tool => '工具';

  @override
  String get toolHttpReqName => 'Http 請求';

  @override
  String get unsavedChanges => '離開前儲存變更?';

  @override
  String get untitled => '未命名';

  @override
  String usableModelsFmt(int n, int m) {
    return '$n 個可用 · $m 個提供者';
  }

  @override
  String get useTools => '使用工具';

  @override
  String get useToolsTip => '每次呼叫都會先詢問，除非已在下方允許';

  @override
  String get allowInsecure => '允許明文 HTTP';

  @override
  String get allowInsecureTip =>
      '該位址是本機以外的 http://，API Key 會以明文傳送，網路路徑上的任何人都能讀取。僅在可信網路中開啟。';

  @override
  String get configure => '設定';

  @override
  String get supportsThinking => '支援思考';

  @override
  String get thinkingEffort => '思考強度';

  @override
  String get mcpHeaders => '請求標頭';

  @override
  String get mcpHeadersTip =>
      '選填，例如名稱 Authorization、值 Bearer <token>。只儲存在本機，不會備份，只傳送給此伺服器。';

  @override
  String get mcpHeadersInvalid => '請求標頭需要名稱和值，名稱只能包含字母、數字和連字號。';

  @override
  String get mcpNeedsSignIn => '需要登入';

  @override
  String get mcpSigningIn => '請在瀏覽器中完成登入';

  @override
  String get mcpSignedIn => '已登入，可以關閉此頁面。';

  @override
  String get mcpSignedInShort => '已登入';

  @override
  String get mcpSignInFailed => '登入失敗，可以關閉此頁面後重試。';

  @override
  String get mcpInsecure => '只有 https 位址可以使用請求標頭或登入。';

  @override
  String get mcpAddHeader => '新增請求標頭';

  @override
  String get mcpNotSignedIn => '未登入';

  @override
  String get mcpSignInTip => '適用於使用 OAuth 的伺服器。在瀏覽器中完成登入，token 會自動續期。';

  @override
  String get mcpConnecting => '連線中…';

  @override
  String get skills => 'Skills';

  @override
  String get skillsTip => '特定任務的操作說明，任務符合時模型會讀取並遵循。只安裝你信任的來源：模型會依 skill 的內容執行。';

  @override
  String get skillSourceInvalid => '無法辨識：請輸入儲存庫、連結或 `npx skills add` 指令';

  @override
  String get skillsNotFound => '沒有找到 skill';

  @override
  String get skillsPick => '選擇要安裝的 skill';

  @override
  String skillsInstalledFmt(int n) {
    return '已安裝 $n 個';
  }

  @override
  String get skillsUpToDate => '已是最新';

  @override
  String skillsUpdatedFmt(int n) {
    return '已更新 $n 個';
  }

  @override
  String get skillsFromFolder => '從資料夾安裝';

  @override
  String get skillsFromZip => '從 .zip 安裝';

  @override
  String skillsUpdateFailedFmt(int n) {
    return '$n 個來源檢查失敗';
  }

  @override
  String get skillBuiltin => '內建';

  @override
  String keyFromEnvFmt(String name) {
    return 'key 來自 $name';
  }

  @override
  String keyFromEnvTipFmt(String name) {
    return '目前使用環境變數 $name 中的 key。在此填寫的 key 會優先使用。';
  }

  @override
  String get skillUpdateAvailable => '有更新';

  @override
  String skillsUpdateAllFmt(int n) {
    return '全部更新（$n）';
  }
}
