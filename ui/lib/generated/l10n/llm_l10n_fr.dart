// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'llm_l10n.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class LlmLocalizationsFr extends LlmLocalizations {
  LlmLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get addServer => 'Ajouter un serveur';

  @override
  String get allow => 'Autoriser';

  @override
  String get allowAlways => 'Toujours autoriser';

  @override
  String get allowedWithoutAsking => 'Autorisés sans demander';

  @override
  String allowToolFmt(String tool) {
    return 'Autoriser $tool ?';
  }

  @override
  String get allProviders => 'Tous les fournisseurs';

  @override
  String alreadyExists(String path) {
    return '$path existe déjà';
  }

  @override
  String get attachment => 'Pièce jointe';

  @override
  String attachUnsupported(String name) {
    return 'Impossible de joindre $name : seulement des images et des fichiers texte jusqu\'à 512 Ko';
  }

  @override
  String get back => 'Retour';

  @override
  String get builtIn => 'Intégrés';

  @override
  String get camera => 'Appareil photo';

  @override
  String charsFmt(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n caractères',
      one: '1 caractère',
    );
    return '$_temp0';
  }

  @override
  String get chatRead => 'Lire un chat';

  @override
  String get chatSearch => 'Rechercher des chats';

  @override
  String get compacted => 'Les messages précédents ont été résumés';

  @override
  String get compaction => 'Compacter les longues discussions';

  @override
  String get compactionTip =>
      'Quand une discussion ne tient plus dans le contexte du modèle, les messages précédents sont résumés pour le modèle. Vous les voyez toujours tous.';

  @override
  String connectedFmt(int n) {
    return 'Connecté · $n outils';
  }

  @override
  String get copied => 'Copié';

  @override
  String get customProvider => 'Fournisseur personnalisé';

  @override
  String get defaultModel => 'Modèle par défaut';

  @override
  String get deleteKey => 'Supprimer la clé';

  @override
  String get deny => 'Refuser';

  @override
  String get discard => 'Abandonner';

  @override
  String get disconnected => 'Déconnecté';

  @override
  String get endpoint => 'Point d\'accès';

  @override
  String get extraVars => 'Variables supplémentaires';

  @override
  String get extraVarsTip =>
      'Une KEY=VALUE par ligne, pour les fournisseurs qui demandent plus qu\'une clé (ressource Azure, compte Cloudflare).';

  @override
  String get favorite => 'Favoris';

  @override
  String get history => 'Historique';

  @override
  String get historyToolTip =>
      'Rechercher et lire vos autres chats, sans demander';

  @override
  String get httpToolTip => 'Récupérer des pages web et des API';

  @override
  String get image => 'Image';

  @override
  String invalidLinkFmt(Object uri) {
    return 'Lien inconnu : $uri';
  }

  @override
  String get key => 'Clé';

  @override
  String get keyInKeychain =>
      'Stockée dans le trousseau du système, jamais dans les sauvegardes.';

  @override
  String get mcpServers => 'Serveurs MCP';

  @override
  String get memory => 'Mémoire';

  @override
  String get memoryDelete => 'Supprimer de la mémoire';

  @override
  String get memoryEdit => 'Modifier la mémoire';

  @override
  String get memoryMove => 'Déplacer en mémoire';

  @override
  String get memorySearch => 'Rechercher dans la mémoire';

  @override
  String get memoryToolTip =>
      'Fichiers que le modèle conserve d\'un chat à l\'autre ; il les lit et les écrit sans demander';

  @override
  String get memoryView => 'Lire la mémoire';

  @override
  String get memoryWrite => 'Enregistrer en mémoire';

  @override
  String get message => 'Message';

  @override
  String minutesSecondsFmt(int m, int s) {
    return '$m min $s s';
  }

  @override
  String get model => 'Modèle';

  @override
  String modelsCountFmt(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n modèles',
      one: '1 modèle',
    );
    return '$_temp0';
  }

  @override
  String get modelsListedTip =>
      'Facultatif : la liste /models du point d\'accès est récupérée. Ajoutez les identifiants qu\'elle ne contient pas.';

  @override
  String get modelsRequired =>
      'Cette API ne peut pas lister ses modèles : saisissez au moins un identifiant de modèle.';

  @override
  String moreFmt(int n) {
    return '$n de plus';
  }

  @override
  String get noProviderKey =>
      'Aucun fournisseur n\'a encore de clé. Ajoutez-en une pour commencer à discuter.';

  @override
  String get refreshModels => 'Actualiser les modèles';

  @override
  String get regenerate => 'Régénérer';

  @override
  String get replyInterrupted => 'La réponse a été interrompue';

  @override
  String get replyWaits => 'La réponse attend votre décision.';

  @override
  String get resumeReply => 'Continuer';

  @override
  String get sameAsChat => 'Comme la discussion';

  @override
  String get searchModels => 'Rechercher des modèles';

  @override
  String get searchProviders => 'Rechercher des fournisseurs';

  @override
  String secondsFmt(String n) {
    return '$n s';
  }

  @override
  String get send => 'Envoyer';

  @override
  String get systemPrompt => 'Prompt système';

  @override
  String get thought => 'Réflexion';

  @override
  String thoughtForFmt(String time) {
    return 'Réflexion : $time';
  }

  @override
  String get titleModel => 'Modèle pour les titres';

  @override
  String tokensFmt(String n) {
    return '$n jetons';
  }

  @override
  String get tool => 'Outil';

  @override
  String get toolHttpReqName => 'Requête HTTP';

  @override
  String get unsavedChanges =>
      'Enregistrer les modifications avant de quitter ?';

  @override
  String get untitled => 'Sans titre';

  @override
  String usableModelsFmt(int n, int m) {
    return '$n utilisables · $m fournisseurs';
  }

  @override
  String get useTools => 'Utiliser les outils';

  @override
  String get useToolsTip =>
      'Chaque appel demande d\'abord, sauf s\'il est autorisé ci-dessous';

  @override
  String get allowInsecure => 'Autoriser HTTP non chiffré';

  @override
  String get allowInsecureTip =>
      'Cette adresse est en http:// hors de cet appareil : la clé d\'API est envoyée en clair, lisible par quiconque sur le chemin réseau. À n\'autoriser que sur un réseau de confiance.';

  @override
  String get configure => 'Configurer';

  @override
  String get supportsThinking => 'Raisonnement';

  @override
  String get thinkingEffort => 'Effort de réflexion';

  @override
  String get mcpHeaders => 'En-têtes';

  @override
  String get mcpHeadersTip =>
      'Facultatif, par exemple Authorization avec Bearer <token>. Conservés uniquement sur cet appareil, jamais sauvegardés, et envoyés uniquement à ce serveur.';

  @override
  String get mcpHeadersInvalid =>
      'Un en-tête doit avoir un nom (lettres, chiffres et tirets) et une valeur.';

  @override
  String get mcpNeedsSignIn => 'Connexion requise';

  @override
  String get mcpSigningIn => 'Terminez la connexion dans le navigateur';

  @override
  String get mcpSignedIn => 'Connecté. Vous pouvez fermer cette page.';

  @override
  String get mcpSignedInShort => 'Connecté';

  @override
  String get mcpSignInFailed =>
      'Échec de la connexion. Fermez cette page et réessayez.';

  @override
  String get mcpInsecure =>
      'Seule une adresse https peut recevoir des en-têtes ou une connexion.';

  @override
  String get mcpAddHeader => 'Ajouter un en-tête';

  @override
  String get mcpNotSignedIn => 'Non connecté';

  @override
  String get mcpSignInTip =>
      'Pour un serveur qui utilise OAuth. La connexion se fait dans le navigateur et le jeton est renouvelé automatiquement.';

  @override
  String get mcpConnecting => 'Connexion…';

  @override
  String get skills => 'Skills';

  @override
  String get skillsTip =>
      'Des instructions pour des tâches précises, que le modèle lit quand une tâche correspond. N’installez que depuis des sources de confiance : le modèle suit ce que dit un skill.';

  @override
  String get skillSourceInvalid =>
      'Ni un dépôt, ni un lien, ni une commande `npx skills add`';

  @override
  String get skillsNotFound => 'Aucun skill trouvé à cet endroit';

  @override
  String get skillsPick => 'Skills à installer';

  @override
  String skillsInstalledFmt(int n) {
    return '$n installés';
  }

  @override
  String get skillsUpToDate => 'À jour';

  @override
  String skillsUpdatedFmt(int n) {
    return '$n mis à jour';
  }

  @override
  String get skillsFromFolder => 'Installer depuis un dossier';

  @override
  String get skillsFromZip => 'Installer depuis un .zip';

  @override
  String skillsUpdateFailedFmt(int n) {
    return '$n sources n’ont pas pu être vérifiées';
  }

  @override
  String get skillBuiltin => 'Intégré';

  @override
  String keyFromEnvFmt(String name) {
    return 'Clé depuis $name';
  }

  @override
  String keyFromEnvTipFmt(String name) {
    return 'La clé utilisée est celle de la variable d’environnement $name. Une clé saisie ici la remplace.';
  }

  @override
  String get skillUpdateAvailable => 'Mise à jour disponible';

  @override
  String skillsUpdateAllFmt(int n) {
    return 'Tout mettre à jour ($n)';
  }

  @override
  String get askUser => 'Vous demander';

  @override
  String get fieldRequired => 'Obligatoire';

  @override
  String get fieldInvalid => 'Non valide';

  @override
  String get waitingForYou => 'Vous attend';
}
