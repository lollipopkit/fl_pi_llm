// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'llm_l10n.dart';

// ignore_for_file: type=lint

/// The translations for Italian (`it`).
class LlmLocalizationsIt extends LlmLocalizations {
  LlmLocalizationsIt([String locale = 'it']) : super(locale);

  @override
  String get addServer => 'Aggiungi server';

  @override
  String get allow => 'Consenti';

  @override
  String get allowAlways => 'Consenti sempre';

  @override
  String get allowedWithoutAsking => 'Consentito senza chiedere';

  @override
  String allowToolFmt(String tool) {
    return 'Consentire $tool?';
  }

  @override
  String get allProviders => 'Tutti i provider';

  @override
  String alreadyExists(String path) {
    return '$path esiste già';
  }

  @override
  String get attachment => 'Allegato';

  @override
  String attachUnsupported(String name) {
    return 'Impossibile allegare $name: sono supportati solo immagini e file di testo fino a 512 KB';
  }

  @override
  String get back => 'Indietro';

  @override
  String get builtIn => 'Integrato';

  @override
  String get camera => 'Fotocamera';

  @override
  String charsFmt(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n caratteri',
      one: '1 carattere',
    );
    return '$_temp0';
  }

  @override
  String get chatRead => 'Leggi chat';

  @override
  String get chatSearch => 'Cerca nelle chat';

  @override
  String get compacted => 'I messaggi precedenti sono stati riassunti';

  @override
  String get compaction => 'Compatta le chat lunghe';

  @override
  String get compactionTip =>
      'Quando una chat non entra più nel contesto del modello, i messaggi precedenti vengono riassunti per il modello. Puoi comunque vederli tutti.';

  @override
  String connectedFmt(int n) {
    return 'Connesso · $n strumenti';
  }

  @override
  String get copied => 'Copiato';

  @override
  String get customProvider => 'Provider personalizzato';

  @override
  String get defaultModel => 'Modello predefinito';

  @override
  String get deleteKey => 'Elimina chiave';

  @override
  String get deny => 'Nega';

  @override
  String get discard => 'Scarta';

  @override
  String get disconnected => 'Disconnesso';

  @override
  String get endpoint => 'Endpoint';

  @override
  String get extraVars => 'Variabili aggiuntive';

  @override
  String get extraVarsTip =>
      'Una KEY=VALUE per riga, per i provider che necessitano di più di una chiave (risorsa Azure, account Cloudflare).';

  @override
  String get favorite => 'Preferiti';

  @override
  String get history => 'Cronologia';

  @override
  String get historyToolTip => 'Cerca e leggi le altre chat senza chiedere';

  @override
  String get httpToolTip => 'Recupera pagine web e API';

  @override
  String get image => 'Immagine';

  @override
  String invalidLinkFmt(Object uri) {
    return 'Link non valido: $uri';
  }

  @override
  String get key => 'Chiave';

  @override
  String get keyInKeychain =>
      'Salvata nel portachiavi di sistema, mai nei backup.';

  @override
  String get mcpServers => 'Server MCP';

  @override
  String get memory => 'Memoria';

  @override
  String get memoryDelete => 'Elimina memoria';

  @override
  String get memoryEdit => 'Modifica memoria';

  @override
  String get memoryMove => 'Sposta memoria';

  @override
  String get memorySearch => 'Cerca nella memoria';

  @override
  String get memoryToolTip =>
      'File che il modello conserva tra le chat, letti e scritti senza chiedere';

  @override
  String get memoryView => 'Leggi memoria';

  @override
  String get memoryWrite => 'Salva memoria';

  @override
  String get message => 'Messaggio';

  @override
  String minutesSecondsFmt(int m, int s) {
    return '$m min $s s';
  }

  @override
  String get model => 'Modello';

  @override
  String modelsCountFmt(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n modelli',
      one: '1 modello',
    );
    return '$_temp0';
  }

  @override
  String get modelsListedTip =>
      'Facoltativo: viene recuperato l\'elenco /models dell\'endpoint. Aggiungi gli ID che non vi compaiono.';

  @override
  String get modelsRequired =>
      'Questa API non può elencare i propri modelli: inserisci almeno un ID modello.';

  @override
  String moreFmt(int n) {
    return 'Altri $n';
  }

  @override
  String get noProviderKey =>
      'Nessun provider ha ancora una chiave. Aggiungine una per iniziare a chattare.';

  @override
  String get refreshModels => 'Aggiorna modelli';

  @override
  String get regenerate => 'Rigenera';

  @override
  String get replyInterrupted => 'La risposta è stata interrotta';

  @override
  String get replyWaits => 'La risposta attende una tua risposta.';

  @override
  String get resumeReply => 'Continua';

  @override
  String get sameAsChat => 'Come nella chat';

  @override
  String get searchModels => 'Cerca modelli';

  @override
  String get searchProviders => 'Cerca provider';

  @override
  String secondsFmt(String n) {
    return '$n s';
  }

  @override
  String get send => 'Invia';

  @override
  String get systemPrompt => 'Prompt di sistema';

  @override
  String get thought => 'Pensiero';

  @override
  String thoughtForFmt(String time) {
    return 'Ragionato per $time';
  }

  @override
  String get titleModel => 'Modello per i titoli';

  @override
  String tokensFmt(String n) {
    return '$n token';
  }

  @override
  String get tool => 'Strumento';

  @override
  String get toolHttpReqName => 'Richiesta HTTP';

  @override
  String get unsavedChanges => 'Salvare le modifiche prima di uscire?';

  @override
  String get untitled => 'Senza titolo';

  @override
  String usableModelsFmt(int n, int m) {
    String _temp0 = intl.Intl.pluralLogic(
      m,
      locale: localeName,
      other: '$m provider',
      one: '1 provider',
    );
    return '$n utilizzabili · $_temp0';
  }

  @override
  String get useTools => 'Usa strumenti';

  @override
  String get useToolsTip =>
      'Ogni chiamata richiede conferma, a meno che non sia consentita qui sotto';

  @override
  String get allowInsecure => 'Consenti HTTP non crittografato';

  @override
  String get allowInsecureTip =>
      'Questo indirizzo usa http:// al di fuori di questo dispositivo: la chiave API viene inviata senza crittografia ed è leggibile da chiunque si trovi lungo il percorso di rete. Consentilo solo su una rete di cui ti fidi.';

  @override
  String get configure => 'Configura';

  @override
  String get supportsThinking => 'Capacità di ragionamento';

  @override
  String get thinkingEffort => 'Intensità del ragionamento';

  @override
  String get mcpHeaders => 'Intestazioni';

  @override
  String get mcpHeadersTip =>
      'Facoltativo, ad esempio Authorization con Bearer <token>. Conservate solo su questo dispositivo, mai incluse nei backup e inviate solo a questo server.';

  @override
  String get mcpHeadersInvalid =>
      'Un\'intestazione deve avere un nome composto da lettere, cifre e trattini e un valore.';

  @override
  String get mcpNeedsSignIn => 'Accesso richiesto';

  @override
  String get mcpSigningIn => 'Completa l\'accesso nel browser';

  @override
  String get mcpSignedIn => 'Accesso effettuato. Puoi chiudere questa pagina.';

  @override
  String get mcpSignedInShort => 'Accesso effettuato';

  @override
  String get mcpSignInFailed =>
      'Accesso non riuscito. Puoi chiudere questa pagina e riprovare.';

  @override
  String get mcpInsecure =>
      'Solo a un indirizzo https è possibile inviare intestazioni o effettuare l\'accesso.';

  @override
  String get mcpAddHeader => 'Aggiungi intestazione';

  @override
  String get mcpNotSignedIn => 'Accesso non effettuato';

  @override
  String get mcpSignInTip =>
      'Per un server che usa OAuth. Effettua l\'accesso nel browser e il token si rinnova automaticamente.';

  @override
  String get mcpConnecting => 'Connessione in corso…';

  @override
  String get skills => 'Skills';

  @override
  String get skillsTip =>
      'Istruzioni per attività specifiche, che il modello legge quando un\'attività corrisponde. Installale solo da fonti attendibili: il modello segue le istruzioni di una Skill.';

  @override
  String get skillSourceInvalid =>
      'Non è un repository, un link o un comando `npx skills add`';

  @override
  String get skillsNotFound => 'Nessuna Skill trovata';

  @override
  String get skillsPick => 'Skills da installare';

  @override
  String skillsInstalledFmt(int n) {
    return '$n installate';
  }

  @override
  String get skillsUpToDate => 'Aggiornate';

  @override
  String skillsUpdatedFmt(int n) {
    return '$n aggiornate';
  }

  @override
  String get skillsFromFolder => 'Installa da una cartella';

  @override
  String get skillsFromZip => 'Installa da un file .zip';

  @override
  String skillsUpdateFailedFmt(int n) {
    return 'Impossibile controllare $n fonti';
  }

  @override
  String get skillBuiltin => 'Integrata';

  @override
  String keyFromEnvFmt(String name) {
    return 'Chiave da $name';
  }

  @override
  String keyFromEnvTipFmt(String name) {
    return 'La chiave attualmente in uso è la variabile d\'ambiente $name. Una chiave inserita qui la sostituisce.';
  }

  @override
  String get skillUpdateAvailable => 'Aggiornamento disponibile';

  @override
  String skillsUpdateAllFmt(int n) {
    return 'Aggiorna tutto ($n)';
  }

  @override
  String get askUser => 'Chiedi all\'utente';

  @override
  String get fieldRequired => 'Obbligatorio';

  @override
  String get fieldInvalid => 'Non valido';

  @override
  String get waitingForYou => 'In attesa di te';

  @override
  String get otherAnswer => 'Altro';

  @override
  String get otherAnswerHint => 'La tua risposta';
}
