// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'llm_l10n.dart';

// ignore_for_file: type=lint

/// The translations for Dutch Flemish (`nl`).
class LlmLocalizationsNl extends LlmLocalizations {
  LlmLocalizationsNl([String locale = 'nl']) : super(locale);

  @override
  String get addServer => 'Server toevoegen';

  @override
  String get allow => 'Toestaan';

  @override
  String get allowAlways => 'Altijd toestaan';

  @override
  String get allowedWithoutAsking => 'Toegestaan zonder te vragen';

  @override
  String allowToolFmt(String tool) {
    return '$tool toestaan?';
  }

  @override
  String get allProviders => 'Alle providers';

  @override
  String alreadyExists(String path) {
    return '$path bestaat al';
  }

  @override
  String get attachment => 'Bijlage';

  @override
  String attachUnsupported(String name) {
    return 'Kan $name niet bijvoegen: alleen afbeeldingen en tekstbestanden tot 512 KB';
  }

  @override
  String get back => 'Terug';

  @override
  String get builtIn => 'Ingebouwd';

  @override
  String get camera => 'Camera';

  @override
  String charsFmt(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n tekens',
      one: '1 teken',
    );
    return '$_temp0';
  }

  @override
  String get chatRead => 'Chat lezen';

  @override
  String get chatSearch => 'Chats doorzoeken';

  @override
  String get compacted => 'Eerdere berichten zijn samengevat';

  @override
  String get compaction => 'Lange chats comprimeren';

  @override
  String get compactionTip =>
      'Past een chat niet meer in de context van het model, dan worden eerdere berichten voor het model samengevat. Jij ziet ze nog allemaal.';

  @override
  String connectedFmt(int n) {
    return 'Verbonden · $n tools';
  }

  @override
  String get copied => 'Gekopieerd';

  @override
  String get customProvider => 'Aangepaste provider';

  @override
  String get defaultModel => 'Standaardmodel';

  @override
  String get deleteKey => 'Sleutel verwijderen';

  @override
  String get deny => 'Weigeren';

  @override
  String get discard => 'Verwerpen';

  @override
  String get disconnected => 'Niet verbonden';

  @override
  String get endpoint => 'Endpoint';

  @override
  String get extraVars => 'Extra variabelen';

  @override
  String get extraVarsTip =>
      'Eén KEY=VALUE per regel, voor providers die meer dan een sleutel nodig hebben (Azure-resource, Cloudflare-account).';

  @override
  String get favorite => 'Favorieten';

  @override
  String get history => 'Geschiedenis';

  @override
  String get historyToolTip =>
      'Je andere chats doorzoeken en lezen, zonder te vragen';

  @override
  String get httpToolTip => 'Webpagina\'s en API\'s ophalen';

  @override
  String get image => 'Afbeelding';

  @override
  String invalidLinkFmt(Object uri) {
    return 'Onbekende link: $uri';
  }

  @override
  String get key => 'Sleutel';

  @override
  String get keyInKeychain =>
      'Opgeslagen in de sleutelhanger van het systeem, nooit in back-ups.';

  @override
  String get mcpServers => 'MCP-servers';

  @override
  String get memory => 'Geheugen';

  @override
  String get memoryDelete => 'Geheugen verwijderen';

  @override
  String get memoryEdit => 'Geheugen bewerken';

  @override
  String get memoryMove => 'Geheugen verplaatsen';

  @override
  String get memorySearch => 'Geheugen doorzoeken';

  @override
  String get memoryToolTip =>
      'Bestanden die het model tussen chats bewaart; het leest en schrijft ze zonder te vragen';

  @override
  String get memoryView => 'Geheugen lezen';

  @override
  String get memoryWrite => 'Geheugen opslaan';

  @override
  String get message => 'Bericht';

  @override
  String minutesSecondsFmt(int m, int s) {
    return '$m min $s s';
  }

  @override
  String get model => 'Model';

  @override
  String modelsCountFmt(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n modellen',
      one: '1 model',
    );
    return '$_temp0';
  }

  @override
  String get modelsListedTip =>
      'Optioneel: de /models-lijst van het endpoint wordt opgehaald. Voeg id’s toe die er niet in staan.';

  @override
  String get modelsRequired =>
      'Deze API kan zijn modellen niet opsommen: vul minstens één model-id in.';

  @override
  String moreFmt(int n) {
    return '$n meer';
  }

  @override
  String get noProviderKey =>
      'Nog geen enkele provider heeft een sleutel. Voeg er een toe om te chatten.';

  @override
  String get refreshModels => 'Modellen vernieuwen';

  @override
  String get regenerate => 'Opnieuw genereren';

  @override
  String get replyInterrupted => 'Het antwoord is onderbroken';

  @override
  String get replyWaits => 'Het antwoord wacht op je beslissing.';

  @override
  String get resumeReply => 'Doorgaan';

  @override
  String get sameAsChat => 'Zelfde als de chat';

  @override
  String get searchModels => 'Modellen zoeken';

  @override
  String get searchProviders => 'Providers zoeken';

  @override
  String secondsFmt(String n) {
    return '$n s';
  }

  @override
  String get send => 'Verzenden';

  @override
  String get systemPrompt => 'Systeemprompt';

  @override
  String get thought => 'Nagedacht';

  @override
  String thoughtForFmt(String time) {
    return '$time nagedacht';
  }

  @override
  String get titleModel => 'Model voor titels';

  @override
  String tokensFmt(String n) {
    return '$n tokens';
  }

  @override
  String get tool => 'Tool';

  @override
  String get toolHttpReqName => 'HTTP-verzoek';

  @override
  String get unsavedChanges => 'Wijzigingen opslaan voor het verlaten?';

  @override
  String get untitled => 'Naamloos';

  @override
  String usableModelsFmt(int n, int m) {
    return '$n bruikbaar · $m providers';
  }

  @override
  String get useTools => 'Tools gebruiken';

  @override
  String get useToolsTip =>
      'Elke aanroep vraagt eerst, tenzij hieronder toegestaan';

  @override
  String get allowInsecure => 'Onversleuteld HTTP toestaan';

  @override
  String get allowInsecureTip =>
      'Dit adres is http:// buiten dit apparaat: de API-sleutel wordt onversleuteld verzonden en is leesbaar voor iedereen op het netwerkpad. Sta dit alleen toe op een vertrouwd netwerk.';
}
