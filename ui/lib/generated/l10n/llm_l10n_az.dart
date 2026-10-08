// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'llm_l10n.dart';

// ignore_for_file: type=lint

/// The translations for Azerbaijani (`az`).
class LlmLocalizationsAz extends LlmLocalizations {
  LlmLocalizationsAz([String locale = 'az']) : super(locale);

  @override
  String get addServer => 'Server əlavə et';

  @override
  String get allow => 'İcazə ver';

  @override
  String get allowAlways => 'Həmişə icazə ver';

  @override
  String get allowedWithoutAsking => 'Soruşmadan icazə verilib';

  @override
  String allowToolFmt(String tool) {
    return '$tool üçün icazə verilsin?';
  }

  @override
  String get allProviders => 'Bütün provayderlər';

  @override
  String alreadyExists(String path) {
    return '$path artıq mövcuddur';
  }

  @override
  String get attachment => 'Əlavə';

  @override
  String attachUnsupported(String name) {
    return '$name əlavə edilə bilməz: yalnız şəkillər və 512 KB-a qədər mətn faylları dəstəklənir';
  }

  @override
  String get back => 'Geri';

  @override
  String get builtIn => 'Daxili';

  @override
  String get camera => 'Kamera';

  @override
  String charsFmt(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n simvol',
      one: '1 simvol',
    );
    return '$_temp0';
  }

  @override
  String get chatRead => 'Söhbəti oxu';

  @override
  String get chatSearch => 'Söhbətlərdə axtar';

  @override
  String get compacted => 'Əvvəlki mesajlar xülasə edildi';

  @override
  String get compaction => 'Uzun söhbətləri yığcamlaşdır';

  @override
  String get compactionTip =>
      'Söhbət modelin kontekstinə artıq sığmadıqda, model üçün əvvəlki mesajlar xülasə edilir. Onların hamısını görməyə davam edirsiniz.';

  @override
  String connectedFmt(int n) {
    return 'Qoşulub · $n alət';
  }

  @override
  String get copied => 'Kopyalandı';

  @override
  String get customProvider => 'Fərdi provayder';

  @override
  String get defaultModel => 'Standart model';

  @override
  String get deleteKey => 'Açarı sil';

  @override
  String get deny => 'Rədd et';

  @override
  String get discard => 'Ləğv et';

  @override
  String get disconnected => 'Bağlantı kəsilib';

  @override
  String get endpoint => 'Endpoint';

  @override
  String get extraVars => 'Əlavə dəyişənlər';

  @override
  String get extraVarsTip =>
      'Açarla yanaşı əlavə məlumat tələb edən provayderlər üçün hər sətirdə bir KEY=VALUE (Azure resursu, Cloudflare hesabı).';

  @override
  String get favorite => 'Seçilmişlər';

  @override
  String get history => 'Tarixçə';

  @override
  String get historyToolTip => 'Soruşmadan digər söhbətləri axtar və oxu';

  @override
  String get httpToolTip => 'Veb səhifələri və API-ləri əldə et';

  @override
  String get image => 'Şəkil';

  @override
  String invalidLinkFmt(Object uri) {
    return 'Yanlış keçid: $uri';
  }

  @override
  String get key => 'Açar';

  @override
  String get keyInKeychain =>
      'Sistemin keychain-ində saxlanılır, ehtiyat nüsxələrə daxil edilmir.';

  @override
  String get mcpServers => 'MCP server-ləri';

  @override
  String get memory => 'Yaddaş';

  @override
  String get memoryDelete => 'Yaddaşı sil';

  @override
  String get memoryEdit => 'Yaddaşı redaktə et';

  @override
  String get memoryMove => 'Yaddaşı köçür';

  @override
  String get memorySearch => 'Yaddaşda axtar';

  @override
  String get memoryToolTip =>
      'Modelin söhbətlər arasında saxladığı, soruşmadan oxuduğu və yazdığı fayllar';

  @override
  String get memoryView => 'Yaddaşı oxu';

  @override
  String get memoryWrite => 'Yaddaşı saxla';

  @override
  String get message => 'Mesaj';

  @override
  String minutesSecondsFmt(int m, int s) {
    return '$m dəq. $s san.';
  }

  @override
  String get model => 'Model';

  @override
  String modelsCountFmt(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n model',
      one: '1 model',
    );
    return '$_temp0';
  }

  @override
  String get modelsListedTip =>
      'İstəyə bağlı: endpoint-in /models siyahısı əldə edilir. Siyahıda olmayan ID-ləri əlavə edin.';

  @override
  String get modelsRequired =>
      'Bu API modellərini siyahıya ala bilmir: ən azı bir model ID-si daxil edin.';

  @override
  String moreFmt(int n) {
    return 'Daha $n';
  }

  @override
  String get noProviderKey =>
      'Hələ heç bir provayderin açarı yoxdur. Söhbətə başlamaq üçün açar əlavə edin.';

  @override
  String get refreshModels => 'Modelləri yenilə';

  @override
  String get regenerate => 'Yenidən yarat';

  @override
  String get replyInterrupted => 'Cavab kəsildi';

  @override
  String get replyWaits => 'Cavab sizin cavabınızı gözləyir.';

  @override
  String get resumeReply => 'Davam et';

  @override
  String get sameAsChat => 'Söhbətdəki kimi';

  @override
  String get searchModels => 'Modellərdə axtar';

  @override
  String get searchProviders => 'Provayderlərdə axtar';

  @override
  String secondsFmt(String n) {
    return '$n san.';
  }

  @override
  String get send => 'Göndər';

  @override
  String get systemPrompt => 'Sistem təlimatı';

  @override
  String get thought => 'Düşüncə';

  @override
  String thoughtForFmt(String time) {
    return '$time düşündü';
  }

  @override
  String get titleModel => 'Başlıqlar üçün model';

  @override
  String tokensFmt(String n) {
    return '$n token';
  }

  @override
  String get tool => 'Alət';

  @override
  String get toolHttpReqName => 'HTTP sorğusu';

  @override
  String get unsavedChanges =>
      'Çıxmazdan əvvəl dəyişiklikləri yadda saxlamaq istəyirsiniz?';

  @override
  String get untitled => 'Adsız';

  @override
  String usableModelsFmt(int n, int m) {
    String _temp0 = intl.Intl.pluralLogic(
      m,
      locale: localeName,
      other: '$m provayder',
      one: '1 provayder',
    );
    return '$n istifadə oluna bilən · $_temp0';
  }

  @override
  String get useTools => 'Alətlərdən istifadə et';

  @override
  String get useToolsTip =>
      'Aşağıda icazə verilməyibsə, hər çağırışdan əvvəl soruşulur';

  @override
  String get allowInsecure => 'Şifrələnməmiş HTTP-yə icazə ver';

  @override
  String get allowInsecureTip =>
      'Bu ünvan cihazdan kənarda http:// istifadə edir: API açarı şifrələnmədən göndərilir və şəbəkə yolundakı hər kəs tərəfindən oxuna bilər. Yalnız etibar etdiyiniz şəbəkədə icazə verin.';

  @override
  String get configure => 'Tənzimlə';

  @override
  String get supportsThinking => 'Düşünmə';

  @override
  String get thinkingEffort => 'Düşünmə intensivliyi';

  @override
  String get mcpHeaders => 'Headers';

  @override
  String get mcpHeadersTip =>
      'İstəyə bağlı, məsələn Bearer <token> ilə Authorization. Yalnız bu cihazda saxlanılır, ehtiyat nüsxəyə daxil edilmir və yalnız bu serverə göndərilir.';

  @override
  String get mcpHeadersInvalid =>
      'Header adı hərflərdən, rəqəmlərdən və defislərdən ibarət olmalı, həmçinin dəyəri olmalıdır.';

  @override
  String get mcpNeedsSignIn => 'Giriş tələb olunur';

  @override
  String get mcpSigningIn => 'Brauzerdə girişi tamamlayın';

  @override
  String get mcpSignedIn => 'Daxil oldunuz. Bu səhifəni bağlaya bilərsiniz.';

  @override
  String get mcpSignedInShort => 'Daxil olub';

  @override
  String get mcpSignInFailed =>
      'Giriş uğursuz oldu. Bu səhifəni bağlayıb yenidən cəhd edə bilərsiniz.';

  @override
  String get mcpInsecure =>
      'Headers yalnız https ünvanına göndərilə və ya giriş yalnız https ünvanında edilə bilər.';

  @override
  String get mcpAddHeader => 'Header əlavə et';

  @override
  String get mcpNotSignedIn => 'Daxil olmayıb';

  @override
  String get mcpSignInTip =>
      'OAuth istifadə edən server üçündür. Brauzerdə daxil olun, token avtomatik yenilənəcək.';

  @override
  String get mcpConnecting => 'Qoşulur…';

  @override
  String get skills => 'Skills';

  @override
  String get skillsTip =>
      'Müəyyən tapşırıqlar üçün təlimatlar; uyğun tapşırıq olduqda model onları oxuyur. Yalnız etibar etdiyiniz mənbələrdən quraşdırın: model Skill-dəki təlimatlara əməl edir.';

  @override
  String get skillSourceInvalid =>
      'Repository, keçid və ya `npx skills add` əmri deyil';

  @override
  String get skillsNotFound => 'Orada heç bir Skill tapılmadı';

  @override
  String get skillsPick => 'Quraşdırılacaq Skills';

  @override
  String skillsInstalledFmt(int n) {
    return '$n quraşdırıldı';
  }

  @override
  String get skillsUpToDate => 'Güncəldir';

  @override
  String skillsUpdatedFmt(int n) {
    return '$n yeniləndi';
  }

  @override
  String get skillsFromFolder => 'Qovluqdan quraşdır';

  @override
  String get skillsFromZip => '.zip-dən quraşdır';

  @override
  String skillsUpdateFailedFmt(int n) {
    return '$n mənbə yoxlanıla bilmədi';
  }

  @override
  String get skillBuiltin => 'Daxili';

  @override
  String keyFromEnvFmt(String name) {
    return 'Açar $name dəyişənindən';
  }

  @override
  String keyFromEnvTipFmt(String name) {
    return 'Hazırda istifadə olunan açar $name mühit dəyişənindəndir. Buraya daxil edilən açar onu əvəz edir.';
  }

  @override
  String get skillUpdateAvailable => 'Yeniləmə mövcuddur';

  @override
  String skillsUpdateAllFmt(int n) {
    return 'Hamısını yenilə ($n)';
  }

  @override
  String get askUser => 'Sizdən soruş';

  @override
  String get fieldRequired => 'Tələb olunur';

  @override
  String get fieldInvalid => 'Yanlışdır';

  @override
  String get waitingForYou => 'Sizi gözləyir';

  @override
  String get otherAnswer => 'Digər';

  @override
  String get otherAnswerHint => 'Öz cavabınız';
}
