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
      'Opsional. Satu \"Nama: nilai\" per baris, misalnya Authorization: Bearer <token>. Hanya disimpan di perangkat ini, tidak pernah dicadangkan, dan hanya dikirim ke server ini.';

  @override
  String get mcpHeadersInvalid =>
      'Setiap baris memerlukan nama, titik dua, dan nilai.';

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
}
