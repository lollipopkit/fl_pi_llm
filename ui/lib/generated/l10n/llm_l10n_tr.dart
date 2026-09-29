// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'llm_l10n.dart';

// ignore_for_file: type=lint

/// The translations for Turkish (`tr`).
class LlmLocalizationsTr extends LlmLocalizations {
  LlmLocalizationsTr([String locale = 'tr']) : super(locale);

  @override
  String get addServer => 'Sunucu ekle';

  @override
  String get allow => 'İzin ver';

  @override
  String get allowAlways => 'Her zaman izin ver';

  @override
  String get allowedWithoutAsking => 'Sormadan izin verilenler';

  @override
  String allowToolFmt(String tool) {
    return '$tool izin verilsin mi?';
  }

  @override
  String get allProviders => 'Tüm sağlayıcılar';

  @override
  String alreadyExists(String path) {
    return '$path zaten var';
  }

  @override
  String get attachment => 'Ek';

  @override
  String attachUnsupported(String name) {
    return '$name eklenemiyor: yalnızca görseller ve 512 KB\'a kadar metin dosyaları';
  }

  @override
  String get back => 'Geri';

  @override
  String get builtIn => 'Yerleşik';

  @override
  String get camera => 'Kamera';

  @override
  String charsFmt(int n) {
    return '$n karakter';
  }

  @override
  String get chatRead => 'Sohbeti oku';

  @override
  String get chatSearch => 'Sohbetlerde ara';

  @override
  String get compacted => 'Önceki mesajlar özetlendi';

  @override
  String get compaction => 'Uzun sohbetleri sıkıştır';

  @override
  String get compactionTip =>
      'Bir sohbet modelin bağlamına artık sığmadığında, önceki mesajlar model için özetlenir. Siz hepsini görmeye devam edersiniz.';

  @override
  String connectedFmt(int n) {
    return 'Bağlı · $n araç';
  }

  @override
  String get copied => 'Kopyalandı';

  @override
  String get customProvider => 'Özel sağlayıcı';

  @override
  String get defaultModel => 'Varsayılan model';

  @override
  String get deleteKey => 'Anahtarı sil';

  @override
  String get deny => 'Reddet';

  @override
  String get discard => 'Vazgeç';

  @override
  String get disconnected => 'Bağlı değil';

  @override
  String get endpoint => 'Uç nokta';

  @override
  String get extraVars => 'Ek değişkenler';

  @override
  String get extraVarsTip =>
      'Satır başına bir KEY=VALUE; anahtardan fazlasını isteyen sağlayıcılar için (Azure kaynağı, Cloudflare hesabı).';

  @override
  String get favorite => 'Favoriler';

  @override
  String get history => 'Geçmiş';

  @override
  String get historyToolTip => 'Diğer sohbetlerinizde sormadan arar ve okur';

  @override
  String get httpToolTip => 'Web sayfalarını ve API\'leri getir';

  @override
  String get image => 'Resim';

  @override
  String invalidLinkFmt(Object uri) {
    return 'Bilinmeyen bağlantı: $uri';
  }

  @override
  String get key => 'Anahtar';

  @override
  String get keyInKeychain =>
      'Sistem anahtar zincirinde saklanır, yedeklere asla girmez.';

  @override
  String get mcpServers => 'MCP sunucuları';

  @override
  String get memory => 'Hafıza';

  @override
  String get memoryDelete => 'Bellekten sil';

  @override
  String get memoryEdit => 'Belleği düzenle';

  @override
  String get memoryMove => 'Belleği taşı';

  @override
  String get memorySearch => 'Bellekte ara';

  @override
  String get memoryToolTip =>
      'Modelin sohbetler arasında sakladığı dosyalar; sormadan okur ve yazar';

  @override
  String get memoryView => 'Belleği oku';

  @override
  String get memoryWrite => 'Belleğe kaydet';

  @override
  String get message => 'Mesaj';

  @override
  String minutesSecondsFmt(int m, int s) {
    return '$m dk $s sn';
  }

  @override
  String get model => 'Model';

  @override
  String modelsCountFmt(int n) {
    return '$n model';
  }

  @override
  String get modelsListedTip =>
      'İsteğe bağlı: uç noktanın /models listesi alınır. Listede olmayan kimlikleri ekleyin.';

  @override
  String get modelsRequired =>
      'Bu API modellerini listeleyemez: en az bir model kimliği girin.';

  @override
  String moreFmt(int n) {
    return '$n tane daha';
  }

  @override
  String get noProviderKey =>
      'Henüz hiçbir sağlayıcının anahtarı yok. Sohbete başlamak için bir tane ekleyin.';

  @override
  String get refreshModels => 'Modelleri yenile';

  @override
  String get regenerate => 'Yeniden oluştur';

  @override
  String get replyInterrupted => 'Yanıt yarıda kesildi';

  @override
  String get replyWaits => 'Yanıt kararınızı bekliyor.';

  @override
  String get resumeReply => 'Devam et';

  @override
  String get sameAsChat => 'Sohbetle aynı';

  @override
  String get searchModels => 'Model ara';

  @override
  String get searchProviders => 'Sağlayıcı ara';

  @override
  String secondsFmt(String n) {
    return '$n sn';
  }

  @override
  String get send => 'Gönder';

  @override
  String get systemPrompt => 'Sistem istemi';

  @override
  String get thought => 'Düşünce';

  @override
  String thoughtForFmt(String time) {
    return '$time düşündü';
  }

  @override
  String get titleModel => 'Başlık modeli';

  @override
  String tokensFmt(String n) {
    return '$n token';
  }

  @override
  String get tool => 'Araç';

  @override
  String get toolHttpReqName => 'HTTP isteği';

  @override
  String get unsavedChanges => 'Çıkmadan önce değişiklikler kaydedilsin mi?';

  @override
  String get untitled => 'Başlıksız';

  @override
  String usableModelsFmt(int n, int m) {
    return '$n kullanılabilir · $m sağlayıcı';
  }

  @override
  String get useTools => 'Araçları kullan';

  @override
  String get useToolsTip => 'Aşağıda izin verilmedikçe her çağrı önce sorar';
}
