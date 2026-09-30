// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'llm_l10n.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class LlmLocalizationsDe extends LlmLocalizations {
  LlmLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get addServer => 'Server hinzufügen';

  @override
  String get allow => 'Erlauben';

  @override
  String get allowAlways => 'Immer erlauben';

  @override
  String get allowedWithoutAsking => 'Ohne Nachfrage erlaubt';

  @override
  String allowToolFmt(String tool) {
    return '$tool erlauben?';
  }

  @override
  String get allProviders => 'Alle Anbieter';

  @override
  String alreadyExists(String path) {
    return '$path existiert bereits';
  }

  @override
  String get attachment => 'Anhang';

  @override
  String attachUnsupported(String name) {
    return '$name kann nicht angehängt werden: nur Bilder und Textdateien bis 512 KB';
  }

  @override
  String get back => 'Zurück';

  @override
  String get builtIn => 'Integriert';

  @override
  String get camera => 'Kamera';

  @override
  String charsFmt(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n Zeichen',
      one: '1 Zeichen',
    );
    return '$_temp0';
  }

  @override
  String get chatRead => 'Chat lesen';

  @override
  String get chatSearch => 'Chats durchsuchen';

  @override
  String get compacted => 'Frühere Nachrichten wurden zusammengefasst';

  @override
  String get compaction => 'Lange Chats komprimieren';

  @override
  String get compactionTip =>
      'Passt ein Chat nicht mehr in den Kontext des Modells, werden frühere Nachrichten für das Modell zusammengefasst. Du siehst weiterhin alle.';

  @override
  String connectedFmt(int n) {
    return 'Verbunden · $n Werkzeuge';
  }

  @override
  String get copied => 'Kopiert';

  @override
  String get customProvider => 'Eigener Anbieter';

  @override
  String get defaultModel => 'Standardmodell';

  @override
  String get deleteKey => 'Schlüssel löschen';

  @override
  String get deny => 'Ablehnen';

  @override
  String get discard => 'Verwerfen';

  @override
  String get disconnected => 'Getrennt';

  @override
  String get endpoint => 'Endpunkt';

  @override
  String get extraVars => 'Zusätzliche Variablen';

  @override
  String get extraVarsTip =>
      'Eine KEY=VALUE pro Zeile, für Anbieter, die mehr als einen Schlüssel brauchen (Azure-Ressource, Cloudflare-Konto).';

  @override
  String get favorite => 'Favoriten';

  @override
  String get history => 'Verlauf';

  @override
  String get historyToolTip =>
      'Andere Chats durchsuchen und lesen, ohne Rückfrage';

  @override
  String get httpToolTip => 'Webseiten und APIs abrufen';

  @override
  String get image => 'Bild';

  @override
  String invalidLinkFmt(Object uri) {
    return 'Unbekannter Link: $uri';
  }

  @override
  String get key => 'Schlüssel';

  @override
  String get keyInKeychain =>
      'Im Schlüsselbund des Systems gespeichert, nie in Backups.';

  @override
  String get mcpServers => 'MCP-Server';

  @override
  String get memory => 'Gedächtnis';

  @override
  String get memoryDelete => 'Erinnerung löschen';

  @override
  String get memoryEdit => 'Erinnerung bearbeiten';

  @override
  String get memoryMove => 'Erinnerung verschieben';

  @override
  String get memorySearch => 'Erinnerung durchsuchen';

  @override
  String get memoryToolTip =>
      'Dateien, die das Modell über Chats hinweg behält; es liest und schreibt sie ohne Rückfrage';

  @override
  String get memoryView => 'Erinnerung lesen';

  @override
  String get memoryWrite => 'Erinnerung speichern';

  @override
  String get message => 'Nachricht';

  @override
  String minutesSecondsFmt(int m, int s) {
    return '$m Min. $s s';
  }

  @override
  String get model => 'Modell';

  @override
  String modelsCountFmt(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n Modelle',
      one: '1 Modell',
    );
    return '$_temp0';
  }

  @override
  String get modelsListedTip =>
      'Optional: Die /models-Liste des Endpunkts wird abgerufen. Ergänze IDs, die dort fehlen.';

  @override
  String get modelsRequired =>
      'Diese API kann ihre Modelle nicht auflisten: Gib mindestens eine Modell-ID ein.';

  @override
  String moreFmt(int n) {
    return '$n weitere';
  }

  @override
  String get noProviderKey =>
      'Noch kein Anbieter hat einen Schlüssel. Füge einen hinzu, um zu chatten.';

  @override
  String get refreshModels => 'Modelle aktualisieren';

  @override
  String get regenerate => 'Neu generieren';

  @override
  String get replyInterrupted => 'Die Antwort wurde unterbrochen';

  @override
  String get replyWaits => 'Die Antwort wartet auf deine Entscheidung.';

  @override
  String get resumeReply => 'Fortsetzen';

  @override
  String get sameAsChat => 'Wie im Chat';

  @override
  String get searchModels => 'Modelle suchen';

  @override
  String get searchProviders => 'Anbieter suchen';

  @override
  String secondsFmt(String n) {
    return '$n s';
  }

  @override
  String get send => 'Senden';

  @override
  String get systemPrompt => 'Systemprompt';

  @override
  String get thought => 'Nachgedacht';

  @override
  String thoughtForFmt(String time) {
    return '$time nachgedacht';
  }

  @override
  String get titleModel => 'Modell für Titel';

  @override
  String tokensFmt(String n) {
    return '$n Tokens';
  }

  @override
  String get tool => 'Werkzeug';

  @override
  String get toolHttpReqName => 'HTTP-Anfrage';

  @override
  String get unsavedChanges => 'Änderungen vor dem Verlassen speichern?';

  @override
  String get untitled => 'Unbenannt';

  @override
  String usableModelsFmt(int n, int m) {
    return '$n nutzbar · $m Anbieter';
  }

  @override
  String get useTools => 'Werkzeuge verwenden';

  @override
  String get useToolsTip =>
      'Jeder Aufruf fragt zuerst, außer er ist unten erlaubt';

  @override
  String get allowInsecure => 'Unverschlüsseltes HTTP erlauben';

  @override
  String get allowInsecureTip =>
      'Diese Adresse ist http:// außerhalb dieses Geräts: Der API-Schlüssel wird unverschlüsselt gesendet und ist für jeden auf dem Netzwerkpfad lesbar. Nur in einem vertrauenswürdigen Netzwerk erlauben.';

  @override
  String get configure => 'Einrichten';

  @override
  String get supportsThinking => 'Denkfähig';

  @override
  String get thinkingEffort => 'Denkaufwand';

  @override
  String get mcpHeaders => 'Header';

  @override
  String get mcpHeadersTip =>
      'Optional. Ein „Name: Wert“ pro Zeile, z. B. Authorization: Bearer <token>. Nur auf diesem Gerät gespeichert, nie gesichert und nur an diesen Server gesendet.';

  @override
  String get mcpHeadersInvalid =>
      'Jede Zeile braucht einen Namen, einen Doppelpunkt und einen Wert.';

  @override
  String get mcpNeedsSignIn => 'Anmeldung erforderlich';

  @override
  String get mcpSigningIn => 'Anmeldung im Browser abschließen';

  @override
  String get mcpSignedIn => 'Angemeldet. Diese Seite kann geschlossen werden.';

  @override
  String get mcpSignedInShort => 'Angemeldet';

  @override
  String get mcpSignInFailed =>
      'Anmeldung fehlgeschlagen. Seite schließen und erneut versuchen.';

  @override
  String get mcpInsecure =>
      'Nur an eine https-Adresse können Header gesendet oder kann sich angemeldet werden.';
}
