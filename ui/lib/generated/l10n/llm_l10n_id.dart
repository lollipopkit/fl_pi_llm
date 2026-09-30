// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'llm_l10n.dart';

// ignore_for_file: type=lint

/// The translations for Indonesian (`id`).
class LlmLocalizationsId extends LlmLocalizations {
  LlmLocalizationsId([String locale = 'id']) : super(locale);

  @override
  String get addServer => 'Tambah server';

  @override
  String get allow => 'Izinkan';

  @override
  String get allowAlways => 'Selalu izinkan';

  @override
  String get allowedWithoutAsking => 'Diizinkan tanpa bertanya';

  @override
  String allowToolFmt(String tool) {
    return 'Izinkan $tool?';
  }

  @override
  String get allProviders => 'Semua penyedia';

  @override
  String alreadyExists(String path) {
    return '$path sudah ada';
  }

  @override
  String get attachment => 'Lampiran';

  @override
  String attachUnsupported(String name) {
    return 'Tidak dapat melampirkan $name: hanya gambar dan file teks hingga 512 KB';
  }

  @override
  String get back => 'Kembali';

  @override
  String get builtIn => 'Bawaan';

  @override
  String get camera => 'Kamera';

  @override
  String charsFmt(int n) {
    return '$n karakter';
  }

  @override
  String get chatRead => 'Baca chat';

  @override
  String get chatSearch => 'Cari chat';

  @override
  String get compacted => 'Pesan sebelumnya telah diringkas';

  @override
  String get compaction => 'Padatkan obrolan panjang';

  @override
  String get compactionTip =>
      'Saat obrolan tidak lagi muat dalam konteks model, pesan sebelumnya diringkas untuk model. Anda tetap melihat semuanya.';

  @override
  String connectedFmt(int n) {
    return 'Terhubung · $n alat';
  }

  @override
  String get copied => 'Disalin';

  @override
  String get customProvider => 'Penyedia kustom';

  @override
  String get defaultModel => 'Model bawaan';

  @override
  String get deleteKey => 'Hapus kunci';

  @override
  String get deny => 'Tolak';

  @override
  String get discard => 'Buang';

  @override
  String get disconnected => 'Terputus';

  @override
  String get endpoint => 'Endpoint';

  @override
  String get extraVars => 'Variabel tambahan';

  @override
  String get extraVarsTip =>
      'Satu KEY=VALUE per baris, untuk penyedia yang butuh lebih dari kunci (resource Azure, akun Cloudflare).';

  @override
  String get favorite => 'Favorit';

  @override
  String get history => 'Riwayat';

  @override
  String get historyToolTip => 'Cari dan baca chat lain, tanpa bertanya';

  @override
  String get httpToolTip => 'Ambil halaman web dan API';

  @override
  String get image => 'Gambar';

  @override
  String invalidLinkFmt(Object uri) {
    return 'Tautan tidak dikenal: $uri';
  }

  @override
  String get key => 'Kunci';

  @override
  String get keyInKeychain =>
      'Disimpan di keychain sistem, tidak pernah di cadangan.';

  @override
  String get mcpServers => 'Server MCP';

  @override
  String get memory => 'Memori';

  @override
  String get memoryDelete => 'Hapus memori';

  @override
  String get memoryEdit => 'Edit memori';

  @override
  String get memoryMove => 'Pindahkan memori';

  @override
  String get memorySearch => 'Cari di memori';

  @override
  String get memoryToolTip =>
      'File yang disimpan model antar chat; dibaca dan ditulis tanpa bertanya';

  @override
  String get memoryView => 'Baca memori';

  @override
  String get memoryWrite => 'Simpan memori';

  @override
  String get message => 'Pesan';

  @override
  String minutesSecondsFmt(int m, int s) {
    return '$m mnt $s dtk';
  }

  @override
  String get model => 'Model';

  @override
  String modelsCountFmt(int n) {
    return '$n model';
  }

  @override
  String get modelsListedTip =>
      'Opsional: daftar /models dari endpoint akan diambil. Tambahkan ID yang tidak tercantum.';

  @override
  String get modelsRequired =>
      'API ini tidak dapat mencantumkan modelnya: masukkan setidaknya satu ID model.';

  @override
  String moreFmt(int n) {
    return '$n lainnya';
  }

  @override
  String get noProviderKey =>
      'Belum ada penyedia yang memiliki kunci. Tambahkan satu untuk mulai mengobrol.';

  @override
  String get refreshModels => 'Muat ulang model';

  @override
  String get regenerate => 'Buat ulang';

  @override
  String get replyInterrupted => 'Balasan terputus';

  @override
  String get replyWaits => 'Balasan menunggu jawaban Anda.';

  @override
  String get resumeReply => 'Lanjutkan';

  @override
  String get sameAsChat => 'Sama seperti obrolan';

  @override
  String get searchModels => 'Cari model';

  @override
  String get searchProviders => 'Cari penyedia';

  @override
  String secondsFmt(String n) {
    return '$n dtk';
  }

  @override
  String get send => 'Kirim';

  @override
  String get systemPrompt => 'Prompt sistem';

  @override
  String get thought => 'Pemikiran';

  @override
  String thoughtForFmt(String time) {
    return 'Berpikir $time';
  }

  @override
  String get titleModel => 'Model untuk judul';

  @override
  String tokensFmt(String n) {
    return '$n token';
  }

  @override
  String get tool => 'Alat';

  @override
  String get toolHttpReqName => 'Permintaan Http';

  @override
  String get unsavedChanges => 'Simpan perubahan sebelum keluar?';

  @override
  String get untitled => 'Tanpa judul';

  @override
  String usableModelsFmt(int n, int m) {
    return '$n tersedia · $m penyedia';
  }

  @override
  String get useTools => 'Gunakan alat';

  @override
  String get useToolsTip =>
      'Setiap panggilan bertanya dulu kecuali diizinkan di bawah';

  @override
  String get allowInsecure => 'Izinkan HTTP tanpa enkripsi';

  @override
  String get allowInsecureTip =>
      'Alamat ini http:// di luar perangkat ini: kunci API dikirim tanpa enkripsi dan dapat dibaca siapa pun di jalur jaringan. Izinkan hanya di jaringan tepercaya.';

  @override
  String get configure => 'Atur';

  @override
  String get supportsThinking => 'Mendukung penalaran';

  @override
  String get thinkingEffort => 'Upaya penalaran';

  @override
  String get mcpHeaders => 'Header';

  @override
  String get mcpHeadersTip =>
      'Opsional, misalnya Authorization dengan Bearer <token>. Hanya disimpan di perangkat ini, tidak pernah dicadangkan, dan hanya dikirim ke server ini.';

  @override
  String get mcpHeadersInvalid =>
      'Header memerlukan nama berupa huruf, angka, dan tanda hubung, serta sebuah nilai.';

  @override
  String get mcpNeedsSignIn => 'Perlu masuk';

  @override
  String get mcpSigningIn => 'Selesaikan proses masuk di browser';

  @override
  String get mcpSignedIn => 'Sudah masuk. Halaman ini boleh ditutup.';

  @override
  String get mcpSignedInShort => 'Sudah masuk';

  @override
  String get mcpSignInFailed => 'Gagal masuk. Tutup halaman ini dan coba lagi.';

  @override
  String get mcpInsecure =>
      'Hanya alamat https yang dapat dikirimi header atau digunakan untuk masuk.';

  @override
  String get mcpAddHeader => 'Tambah header';

  @override
  String get mcpNotSignedIn => 'Belum masuk';

  @override
  String get mcpSignInTip =>
      'Untuk server yang memakai OAuth. Masuk dilakukan di browser, dan token diperbarui otomatis.';

  @override
  String get mcpConnecting => 'Menghubungkan…';

  @override
  String get skills => 'Skills';

  @override
  String get skillsTip =>
      'Petunjuk untuk tugas tertentu yang dibaca model saat tugasnya cocok. Pasang hanya dari sumber tepercaya: model mengikuti isi skill.';

  @override
  String get skillSourceInvalid =>
      'Bukan repositori, tautan, atau perintah `npx skills add`';

  @override
  String get skillsNotFound => 'Tidak ada skill di sana';

  @override
  String get skillsPick => 'Skill yang akan dipasang';

  @override
  String skillsInstalledFmt(int n) {
    return '$n dipasang';
  }

  @override
  String get skillsUpToDate => 'Sudah terbaru';

  @override
  String skillsUpdatedFmt(int n) {
    return '$n diperbarui';
  }

  @override
  String get skillsFromFolder => 'Pasang dari folder';

  @override
  String get skillsFromZip => 'Pasang dari .zip';

  @override
  String skillsUpdateFailedFmt(int n) {
    return '$n sumber tidak dapat diperiksa';
  }

  @override
  String get skillBuiltin => 'Bawaan';

  @override
  String keyFromEnvFmt(String name) {
    return 'Kunci dari $name';
  }

  @override
  String keyFromEnvTipFmt(String name) {
    return 'Kunci yang dipakai berasal dari variabel lingkungan $name. Kunci yang diisi di sini akan diutamakan.';
  }

  @override
  String get skillUpdateAvailable => 'Ada pembaruan';

  @override
  String skillsUpdateAllFmt(int n) {
    return 'Perbarui semua ($n)';
  }

  @override
  String get askUser => 'Bertanya padamu';

  @override
  String get fieldRequired => 'Wajib';

  @override
  String get fieldInvalid => 'Tidak valid';

  @override
  String get waitingForYou => 'Menunggumu';

  @override
  String get otherAnswer => 'Lainnya';

  @override
  String get otherAnswerHint => 'Jawabanmu sendiri';
}
