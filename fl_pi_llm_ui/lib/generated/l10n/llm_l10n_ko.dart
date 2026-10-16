// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'llm_l10n.dart';

// ignore_for_file: type=lint

/// The translations for Korean (`ko`).
class LlmLocalizationsKo extends LlmLocalizations {
  LlmLocalizationsKo([String locale = 'ko']) : super(locale);

  @override
  String get addServer => '서버 추가';

  @override
  String get allow => '허용';

  @override
  String get allowAlways => '항상 허용';

  @override
  String get allowedWithoutAsking => '묻지 않고 허용됨';

  @override
  String allowToolFmt(String tool) {
    return '$tool을(를) 허용할까요?';
  }

  @override
  String get allProviders => '모든 제공자';

  @override
  String alreadyExists(String path) {
    return '$path이(가) 이미 있습니다';
  }

  @override
  String get attachment => '첨부 파일';

  @override
  String attachUnsupported(String name) {
    return '$name을(를) 첨부할 수 없습니다: 이미지와 512 KB 이하의 텍스트 파일만 지원됩니다';
  }

  @override
  String get back => '뒤로';

  @override
  String get builtIn => '내장';

  @override
  String get camera => '카메라';

  @override
  String charsFmt(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '문자 $n개',
      one: '문자 1개',
    );
    return '$_temp0';
  }

  @override
  String get chatRead => '채팅 읽기';

  @override
  String get chatSearch => '채팅 검색';

  @override
  String get compacted => '이전 메시지가 요약되었습니다';

  @override
  String get compaction => '긴 채팅 압축';

  @override
  String get compactionTip =>
      '채팅이 모델의 컨텍스트에 더 이상 들어가지 않으면 모델을 위해 이전 메시지를 요약합니다. 모든 메시지는 계속 볼 수 있습니다.';

  @override
  String connectedFmt(int n) {
    return '연결됨 · 도구 $n개';
  }

  @override
  String get copied => '복사됨';

  @override
  String get customProvider => '사용자 지정 제공자';

  @override
  String get defaultModel => '기본 모델';

  @override
  String get deleteKey => '키 삭제';

  @override
  String get deny => '거부';

  @override
  String get discard => '취소';

  @override
  String get disconnected => '연결 끊김';

  @override
  String get endpoint => 'Endpoint';

  @override
  String get extraVars => '추가 변수';

  @override
  String get extraVarsTip =>
      '키 외에 추가 값이 필요한 제공자를 위해 한 줄에 하나씩 KEY=VALUE를 입력하세요(Azure 리소스, Cloudflare 계정).';

  @override
  String get favorite => '즐겨찾기';

  @override
  String get history => '기록';

  @override
  String get historyToolTip => '묻지 않고 다른 채팅 검색 및 읽기';

  @override
  String get httpToolTip => '웹 페이지와 API 가져오기';

  @override
  String get image => '이미지';

  @override
  String invalidLinkFmt(Object uri) {
    return '잘못된 링크: $uri';
  }

  @override
  String get key => '키';

  @override
  String get keyInKeychain => '시스템 keychain에 저장되며 백업에는 포함되지 않습니다.';

  @override
  String get mcpServers => 'MCP 서버';

  @override
  String get memory => '메모리';

  @override
  String get memoryDelete => '메모리 삭제';

  @override
  String get memoryEdit => '메모리 수정';

  @override
  String get memoryMove => '메모리 이동';

  @override
  String get memorySearch => '메모리 검색';

  @override
  String get memoryToolTip => '모델이 채팅 간에 보관하는 파일이며 묻지 않고 읽고 씁니다';

  @override
  String get memoryView => '메모리 읽기';

  @override
  String get memoryWrite => '메모리 저장';

  @override
  String get message => '메시지';

  @override
  String minutesSecondsFmt(int m, int s) {
    return '$m분 $s초';
  }

  @override
  String get model => '모델';

  @override
  String modelsCountFmt(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '모델 $n개',
      one: '모델 1개',
    );
    return '$_temp0';
  }

  @override
  String get modelsListedTip =>
      '선택 사항: endpoint의 /models 목록을 가져옵니다. 목록에 없는 ID를 추가하세요.';

  @override
  String get modelsRequired => '이 API는 모델 목록을 제공하지 않습니다. 모델 ID를 하나 이상 입력하세요.';

  @override
  String moreFmt(int n) {
    return '외 $n개';
  }

  @override
  String get noProviderKey => '아직 키가 등록된 제공자가 없습니다. 채팅을 시작하려면 키를 추가하세요.';

  @override
  String get refreshModels => '모델 새로고침';

  @override
  String get regenerate => '다시 생성';

  @override
  String get replyInterrupted => '응답이 중단되었습니다';

  @override
  String get replyWaits => '응답이 사용자의 답변을 기다립니다.';

  @override
  String get resumeReply => '계속';

  @override
  String get sameAsChat => '채팅과 동일';

  @override
  String get searchModels => '모델 검색';

  @override
  String get searchProviders => '제공자 검색';

  @override
  String secondsFmt(String n) {
    return '$n초';
  }

  @override
  String get send => '보내기';

  @override
  String get systemPrompt => '시스템 프롬프트';

  @override
  String get thought => '생각';

  @override
  String thoughtForFmt(String time) {
    return '$time 동안 생각함';
  }

  @override
  String get titleModel => '제목용 모델';

  @override
  String tokensFmt(String n) {
    return '토큰 $n개';
  }

  @override
  String get tool => '도구';

  @override
  String get toolHttpReqName => 'HTTP 요청';

  @override
  String get unsavedChanges => '나가기 전에 변경 사항을 저장할까요?';

  @override
  String get untitled => '제목 없음';

  @override
  String usableModelsFmt(int n, int m) {
    String _temp0 = intl.Intl.pluralLogic(
      m,
      locale: localeName,
      other: '제공자 $m개',
      one: '제공자 1개',
    );
    return '사용 가능 $n개 · $_temp0';
  }

  @override
  String get useTools => '도구 사용';

  @override
  String get useToolsTip => '아래에서 허용한 경우가 아니면 호출할 때마다 먼저 묻습니다';

  @override
  String get allowInsecure => '일반 HTTP 허용';

  @override
  String get allowInsecureTip =>
      '이 주소는 이 기기 외부에서 http://를 사용합니다. API 키가 암호화되지 않은 상태로 전송되어 네트워크 경로상의 누구나 읽을 수 있습니다. 신뢰할 수 있는 네트워크에서만 허용하세요.';

  @override
  String get configure => '설정';

  @override
  String get supportsThinking => 'Thinking 지원';

  @override
  String get thinkingEffort => 'Thinking 강도';

  @override
  String get mcpHeaders => 'Headers';

  @override
  String get mcpHeadersTip =>
      '선택 사항(예: Bearer <token>을 사용하는 Authorization). 이 기기에만 저장되고 백업되지 않으며 이 서버에만 전송됩니다.';

  @override
  String get mcpHeadersInvalid =>
      'Header 이름은 영문자, 숫자, 하이픈으로 구성되어야 하며 값도 입력해야 합니다.';

  @override
  String get mcpNeedsSignIn => '로그인 필요';

  @override
  String get mcpSigningIn => '브라우저에서 로그인을 완료하세요';

  @override
  String get mcpSignedIn => '로그인되었습니다. 이 페이지를 닫아도 됩니다.';

  @override
  String get mcpSignedInShort => '로그인됨';

  @override
  String get mcpSignInFailed => '로그인에 실패했습니다. 이 페이지를 닫고 다시 시도할 수 있습니다.';

  @override
  String get mcpInsecure => 'https 주소에만 headers를 전송하거나 로그인할 수 있습니다.';

  @override
  String get mcpAddHeader => 'Header 추가';

  @override
  String get mcpNotSignedIn => '로그인되지 않음';

  @override
  String get mcpSignInTip =>
      'OAuth를 사용하는 서버용입니다. 브라우저에서 로그인하면 token이 자동으로 갱신됩니다.';

  @override
  String get mcpConnecting => '연결 중…';

  @override
  String get skills => 'Skills';

  @override
  String get skillsTip =>
      '특정 작업을 위한 지침이며, 작업이 일치하면 모델이 읽습니다. 신뢰할 수 있는 출처에서만 설치하세요. 모델은 Skill의 지침을 따릅니다.';

  @override
  String get skillSourceInvalid =>
      'repository, 링크 또는 `npx skills add` 명령이 아닙니다';

  @override
  String get skillsNotFound => '해당 위치에서 Skill을 찾을 수 없습니다';

  @override
  String get skillsPick => '설치할 Skills';

  @override
  String skillsInstalledFmt(int n) {
    return '$n개 설치됨';
  }

  @override
  String get skillsUpToDate => '최신 상태';

  @override
  String skillsUpdatedFmt(int n) {
    return '$n개 업데이트됨';
  }

  @override
  String get skillsFromFolder => '폴더에서 설치';

  @override
  String get skillsFromZip => '.zip에서 설치';

  @override
  String skillsUpdateFailedFmt(int n) {
    return '$n개 source를 확인할 수 없습니다';
  }

  @override
  String get skillBuiltin => '내장';

  @override
  String keyFromEnvFmt(String name) {
    return '$name에서 가져온 키';
  }

  @override
  String keyFromEnvTipFmt(String name) {
    return '현재 사용 중인 키는 환경 변수 $name에 있습니다. 여기에 입력한 키가 이를 대체합니다.';
  }

  @override
  String get skillUpdateAvailable => '업데이트 사용 가능';

  @override
  String skillsUpdateAllFmt(int n) {
    return '모두 업데이트 ($n)';
  }

  @override
  String get askUser => '사용자에게 묻기';

  @override
  String get fieldRequired => '필수';

  @override
  String get fieldInvalid => '올바르지 않음';

  @override
  String get waitingForYou => '응답 대기 중';

  @override
  String get otherAnswer => '기타';

  @override
  String get otherAnswerHint => '직접 입력한 답변';
}
