import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'llm_l10n_de.dart';
import 'llm_l10n_en.dart';
import 'llm_l10n_es.dart';
import 'llm_l10n_fr.dart';
import 'llm_l10n_id.dart';
import 'llm_l10n_ja.dart';
import 'llm_l10n_nl.dart';
import 'llm_l10n_pt.dart';
import 'llm_l10n_ru.dart';
import 'llm_l10n_tr.dart';
import 'llm_l10n_uk.dart';
import 'llm_l10n_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of LlmLocalizations
/// returned by `LlmLocalizations.of(context)`.
///
/// Applications need to include `LlmLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/llm_l10n.dart';
///
/// return MaterialApp(
///   localizationsDelegates: LlmLocalizations.localizationsDelegates,
///   supportedLocales: LlmLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the LlmLocalizations.supportedLocales
/// property.
abstract class LlmLocalizations {
  LlmLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static LlmLocalizations of(BuildContext context) {
    return Localizations.of<LlmLocalizations>(context, LlmLocalizations)!;
  }

  static const LocalizationsDelegate<LlmLocalizations> delegate =
      _LlmLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('de'),
    Locale('en'),
    Locale('es'),
    Locale('fr'),
    Locale('id'),
    Locale('ja'),
    Locale('nl'),
    Locale('pt'),
    Locale('ru'),
    Locale('tr'),
    Locale('uk'),
    Locale('zh'),
    Locale('zh', 'TW'),
  ];

  /// No description provided for @addServer.
  ///
  /// In en, this message translates to:
  /// **'Add server'**
  String get addServer;

  /// No description provided for @allow.
  ///
  /// In en, this message translates to:
  /// **'Allow'**
  String get allow;

  /// No description provided for @allowAlways.
  ///
  /// In en, this message translates to:
  /// **'Always allow'**
  String get allowAlways;

  /// No description provided for @allowedWithoutAsking.
  ///
  /// In en, this message translates to:
  /// **'Allowed without asking'**
  String get allowedWithoutAsking;

  /// No description provided for @allowToolFmt.
  ///
  /// In en, this message translates to:
  /// **'Allow {tool}?'**
  String allowToolFmt(String tool);

  /// No description provided for @allProviders.
  ///
  /// In en, this message translates to:
  /// **'All providers'**
  String get allProviders;

  /// No description provided for @alreadyExists.
  ///
  /// In en, this message translates to:
  /// **'{path} already exists'**
  String alreadyExists(String path);

  /// No description provided for @attachment.
  ///
  /// In en, this message translates to:
  /// **'Attachment'**
  String get attachment;

  /// No description provided for @attachUnsupported.
  ///
  /// In en, this message translates to:
  /// **'Cannot attach {name}: only images and text files up to 512 KB'**
  String attachUnsupported(String name);

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @builtIn.
  ///
  /// In en, this message translates to:
  /// **'Built-in'**
  String get builtIn;

  /// No description provided for @camera.
  ///
  /// In en, this message translates to:
  /// **'Camera'**
  String get camera;

  /// No description provided for @charsFmt.
  ///
  /// In en, this message translates to:
  /// **'{n, plural, =1{1 character} other{{n} characters}}'**
  String charsFmt(int n);

  /// No description provided for @chatRead.
  ///
  /// In en, this message translates to:
  /// **'Read chat'**
  String get chatRead;

  /// No description provided for @chatSearch.
  ///
  /// In en, this message translates to:
  /// **'Search chats'**
  String get chatSearch;

  /// No description provided for @compacted.
  ///
  /// In en, this message translates to:
  /// **'Earlier messages were summarised'**
  String get compacted;

  /// No description provided for @compaction.
  ///
  /// In en, this message translates to:
  /// **'Compact long chats'**
  String get compaction;

  /// No description provided for @compactionTip.
  ///
  /// In en, this message translates to:
  /// **'When a chat no longer fits the model\'s context, earlier messages are summarised for the model. You still see all of them.'**
  String get compactionTip;

  /// No description provided for @connectedFmt.
  ///
  /// In en, this message translates to:
  /// **'Connected · {n} tools'**
  String connectedFmt(int n);

  /// No description provided for @copied.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get copied;

  /// No description provided for @customProvider.
  ///
  /// In en, this message translates to:
  /// **'Custom provider'**
  String get customProvider;

  /// No description provided for @defaultModel.
  ///
  /// In en, this message translates to:
  /// **'Default model'**
  String get defaultModel;

  /// No description provided for @deleteKey.
  ///
  /// In en, this message translates to:
  /// **'Delete key'**
  String get deleteKey;

  /// No description provided for @deny.
  ///
  /// In en, this message translates to:
  /// **'Deny'**
  String get deny;

  /// No description provided for @discard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get discard;

  /// No description provided for @disconnected.
  ///
  /// In en, this message translates to:
  /// **'Disconnected'**
  String get disconnected;

  /// No description provided for @endpoint.
  ///
  /// In en, this message translates to:
  /// **'Endpoint'**
  String get endpoint;

  /// No description provided for @extraVars.
  ///
  /// In en, this message translates to:
  /// **'Extra variables'**
  String get extraVars;

  /// No description provided for @extraVarsTip.
  ///
  /// In en, this message translates to:
  /// **'KEY=VALUE per line, for providers that need more than a key (Azure resource, Cloudflare account).'**
  String get extraVarsTip;

  /// No description provided for @favorite.
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get favorite;

  /// No description provided for @history.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get history;

  /// No description provided for @historyToolTip.
  ///
  /// In en, this message translates to:
  /// **'Search and read your other chats, without asking'**
  String get historyToolTip;

  /// No description provided for @httpToolTip.
  ///
  /// In en, this message translates to:
  /// **'Fetch web pages and APIs'**
  String get httpToolTip;

  /// No description provided for @image.
  ///
  /// In en, this message translates to:
  /// **'Image'**
  String get image;

  /// No description provided for @invalidLinkFmt.
  ///
  /// In en, this message translates to:
  /// **'Invalid link: {uri}'**
  String invalidLinkFmt(Object uri);

  /// No description provided for @key.
  ///
  /// In en, this message translates to:
  /// **'Key'**
  String get key;

  /// No description provided for @keyInKeychain.
  ///
  /// In en, this message translates to:
  /// **'Stored in the system keychain, never in backups.'**
  String get keyInKeychain;

  /// No description provided for @mcpServers.
  ///
  /// In en, this message translates to:
  /// **'MCP servers'**
  String get mcpServers;

  /// No description provided for @memory.
  ///
  /// In en, this message translates to:
  /// **'Memory'**
  String get memory;

  /// No description provided for @memoryDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete memory'**
  String get memoryDelete;

  /// No description provided for @memoryEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit memory'**
  String get memoryEdit;

  /// No description provided for @memoryMove.
  ///
  /// In en, this message translates to:
  /// **'Move memory'**
  String get memoryMove;

  /// No description provided for @memorySearch.
  ///
  /// In en, this message translates to:
  /// **'Search memory'**
  String get memorySearch;

  /// No description provided for @memoryToolTip.
  ///
  /// In en, this message translates to:
  /// **'Files the model keeps across chats, read and written without asking'**
  String get memoryToolTip;

  /// No description provided for @memoryView.
  ///
  /// In en, this message translates to:
  /// **'Read memory'**
  String get memoryView;

  /// No description provided for @memoryWrite.
  ///
  /// In en, this message translates to:
  /// **'Save memory'**
  String get memoryWrite;

  /// No description provided for @message.
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get message;

  /// No description provided for @minutesSecondsFmt.
  ///
  /// In en, this message translates to:
  /// **'{m} min {s} s'**
  String minutesSecondsFmt(int m, int s);

  /// No description provided for @model.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get model;

  /// No description provided for @modelsCountFmt.
  ///
  /// In en, this message translates to:
  /// **'{n, plural, =1{1 model} other{{n} models}}'**
  String modelsCountFmt(int n);

  /// No description provided for @modelsListedTip.
  ///
  /// In en, this message translates to:
  /// **'Optional: the endpoint\'s /models list is fetched. Add ids it does not list.'**
  String get modelsListedTip;

  /// No description provided for @modelsRequired.
  ///
  /// In en, this message translates to:
  /// **'This API cannot list its models: enter at least one model id.'**
  String get modelsRequired;

  /// No description provided for @moreFmt.
  ///
  /// In en, this message translates to:
  /// **'{n} more'**
  String moreFmt(int n);

  /// No description provided for @noProviderKey.
  ///
  /// In en, this message translates to:
  /// **'No provider has a key yet. Add one to start chatting.'**
  String get noProviderKey;

  /// No description provided for @refreshModels.
  ///
  /// In en, this message translates to:
  /// **'Refresh models'**
  String get refreshModels;

  /// No description provided for @regenerate.
  ///
  /// In en, this message translates to:
  /// **'Regenerate'**
  String get regenerate;

  /// No description provided for @replyInterrupted.
  ///
  /// In en, this message translates to:
  /// **'The reply was interrupted'**
  String get replyInterrupted;

  /// No description provided for @replyWaits.
  ///
  /// In en, this message translates to:
  /// **'The reply waits for your answer.'**
  String get replyWaits;

  /// No description provided for @resumeReply.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get resumeReply;

  /// No description provided for @sameAsChat.
  ///
  /// In en, this message translates to:
  /// **'Same as the chat'**
  String get sameAsChat;

  /// No description provided for @searchModels.
  ///
  /// In en, this message translates to:
  /// **'Search models'**
  String get searchModels;

  /// No description provided for @searchProviders.
  ///
  /// In en, this message translates to:
  /// **'Search providers'**
  String get searchProviders;

  /// No description provided for @secondsFmt.
  ///
  /// In en, this message translates to:
  /// **'{n} s'**
  String secondsFmt(String n);

  /// No description provided for @send.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get send;

  /// No description provided for @systemPrompt.
  ///
  /// In en, this message translates to:
  /// **'System prompt'**
  String get systemPrompt;

  /// No description provided for @thought.
  ///
  /// In en, this message translates to:
  /// **'Thought'**
  String get thought;

  /// No description provided for @thoughtForFmt.
  ///
  /// In en, this message translates to:
  /// **'Thought for {time}'**
  String thoughtForFmt(String time);

  /// No description provided for @titleModel.
  ///
  /// In en, this message translates to:
  /// **'Model for titles'**
  String get titleModel;

  /// No description provided for @tokensFmt.
  ///
  /// In en, this message translates to:
  /// **'{n} tokens'**
  String tokensFmt(String n);

  /// No description provided for @tool.
  ///
  /// In en, this message translates to:
  /// **'Tool'**
  String get tool;

  /// No description provided for @toolHttpReqName.
  ///
  /// In en, this message translates to:
  /// **'HTTP request'**
  String get toolHttpReqName;

  /// No description provided for @unsavedChanges.
  ///
  /// In en, this message translates to:
  /// **'Save your changes before leaving?'**
  String get unsavedChanges;

  /// No description provided for @untitled.
  ///
  /// In en, this message translates to:
  /// **'Untitled'**
  String get untitled;

  /// No description provided for @usableModelsFmt.
  ///
  /// In en, this message translates to:
  /// **'{n} usable · {m, plural, =1{1 provider} other{{m} providers}}'**
  String usableModelsFmt(int n, int m);

  /// No description provided for @useTools.
  ///
  /// In en, this message translates to:
  /// **'Use tools'**
  String get useTools;

  /// No description provided for @useToolsTip.
  ///
  /// In en, this message translates to:
  /// **'Each call asks first unless it is allowed below'**
  String get useToolsTip;

  /// Switch on a custom provider whose address is plain http off the device.
  ///
  /// In en, this message translates to:
  /// **'Allow plain HTTP'**
  String get allowInsecure;

  /// Why plain http is refused unless allowed.
  ///
  /// In en, this message translates to:
  /// **'This address is http:// off this device: the API key is sent unencrypted, readable to anyone on the network path. Allow it only on a network you trust.'**
  String get allowInsecureTip;

  /// No description provided for @configure.
  ///
  /// In en, this message translates to:
  /// **'Configure'**
  String get configure;

  /// No description provided for @supportsThinking.
  ///
  /// In en, this message translates to:
  /// **'Thinking'**
  String get supportsThinking;

  /// No description provided for @thinkingEffort.
  ///
  /// In en, this message translates to:
  /// **'Thinking effort'**
  String get thinkingEffort;

  /// No description provided for @mcpHeaders.
  ///
  /// In en, this message translates to:
  /// **'Headers'**
  String get mcpHeaders;

  /// No description provided for @mcpHeadersTip.
  ///
  /// In en, this message translates to:
  /// **'Optional, such as Authorization with Bearer <token>. Kept on this device only, never backed up, and sent only to this server.'**
  String get mcpHeadersTip;

  /// No description provided for @mcpHeadersInvalid.
  ///
  /// In en, this message translates to:
  /// **'A header needs a name of letters, digits and dashes, and a value.'**
  String get mcpHeadersInvalid;

  /// No description provided for @mcpNeedsSignIn.
  ///
  /// In en, this message translates to:
  /// **'Sign-in required'**
  String get mcpNeedsSignIn;

  /// No description provided for @mcpSigningIn.
  ///
  /// In en, this message translates to:
  /// **'Finish signing in in the browser'**
  String get mcpSigningIn;

  /// No description provided for @mcpSignedIn.
  ///
  /// In en, this message translates to:
  /// **'Signed in. You can close this page.'**
  String get mcpSignedIn;

  /// No description provided for @mcpSignedInShort.
  ///
  /// In en, this message translates to:
  /// **'Signed in'**
  String get mcpSignedInShort;

  /// No description provided for @mcpSignInFailed.
  ///
  /// In en, this message translates to:
  /// **'Sign-in failed. You can close this page and try again.'**
  String get mcpSignInFailed;

  /// No description provided for @mcpInsecure.
  ///
  /// In en, this message translates to:
  /// **'Only an https address can be sent headers or signed in to.'**
  String get mcpInsecure;

  /// No description provided for @mcpAddHeader.
  ///
  /// In en, this message translates to:
  /// **'Add header'**
  String get mcpAddHeader;

  /// No description provided for @mcpNotSignedIn.
  ///
  /// In en, this message translates to:
  /// **'Not signed in'**
  String get mcpNotSignedIn;

  /// No description provided for @mcpSignInTip.
  ///
  /// In en, this message translates to:
  /// **'For a server that uses OAuth. You sign in in the browser, and the token is renewed on its own.'**
  String get mcpSignInTip;

  /// No description provided for @mcpConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting…'**
  String get mcpConnecting;

  /// No description provided for @skills.
  ///
  /// In en, this message translates to:
  /// **'Skills'**
  String get skills;

  /// No description provided for @skillsTip.
  ///
  /// In en, this message translates to:
  /// **'Instructions for particular tasks, which the model reads when a task matches one. Install only from sources you trust: the model follows what a skill says.'**
  String get skillsTip;

  /// No description provided for @skillSourceInvalid.
  ///
  /// In en, this message translates to:
  /// **'Not a repository, link or `npx skills add` command'**
  String get skillSourceInvalid;

  /// No description provided for @skillsNotFound.
  ///
  /// In en, this message translates to:
  /// **'No skills found there'**
  String get skillsNotFound;

  /// No description provided for @skillsPick.
  ///
  /// In en, this message translates to:
  /// **'Skills to install'**
  String get skillsPick;

  /// No description provided for @skillsInstalledFmt.
  ///
  /// In en, this message translates to:
  /// **'Installed {n}'**
  String skillsInstalledFmt(int n);

  /// No description provided for @skillsUpToDate.
  ///
  /// In en, this message translates to:
  /// **'Up to date'**
  String get skillsUpToDate;

  /// No description provided for @skillsUpdatedFmt.
  ///
  /// In en, this message translates to:
  /// **'Updated {n}'**
  String skillsUpdatedFmt(int n);

  /// No description provided for @skillsFromFolder.
  ///
  /// In en, this message translates to:
  /// **'Install from a folder'**
  String get skillsFromFolder;

  /// No description provided for @skillsFromZip.
  ///
  /// In en, this message translates to:
  /// **'Install from a .zip'**
  String get skillsFromZip;

  /// No description provided for @skillsUpdateFailedFmt.
  ///
  /// In en, this message translates to:
  /// **'{n} sources could not be checked'**
  String skillsUpdateFailedFmt(int n);

  /// No description provided for @skillBuiltin.
  ///
  /// In en, this message translates to:
  /// **'Built in'**
  String get skillBuiltin;

  /// No description provided for @keyFromEnvFmt.
  ///
  /// In en, this message translates to:
  /// **'Key from {name}'**
  String keyFromEnvFmt(String name);

  /// No description provided for @keyFromEnvTipFmt.
  ///
  /// In en, this message translates to:
  /// **'The key now in use is the environment variable {name}. A key entered here takes its place.'**
  String keyFromEnvTipFmt(String name);

  /// No description provided for @skillUpdateAvailable.
  ///
  /// In en, this message translates to:
  /// **'Update available'**
  String get skillUpdateAvailable;

  /// No description provided for @skillsUpdateAllFmt.
  ///
  /// In en, this message translates to:
  /// **'Update all ({n})'**
  String skillsUpdateAllFmt(int n);

  /// No description provided for @askUser.
  ///
  /// In en, this message translates to:
  /// **'Ask you'**
  String get askUser;

  /// No description provided for @fieldRequired.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get fieldRequired;

  /// No description provided for @fieldInvalid.
  ///
  /// In en, this message translates to:
  /// **'Not valid'**
  String get fieldInvalid;

  /// No description provided for @waitingForYou.
  ///
  /// In en, this message translates to:
  /// **'Waiting for you'**
  String get waitingForYou;
}

class _LlmLocalizationsDelegate
    extends LocalizationsDelegate<LlmLocalizations> {
  const _LlmLocalizationsDelegate();

  @override
  Future<LlmLocalizations> load(Locale locale) {
    return SynchronousFuture<LlmLocalizations>(lookupLlmLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>[
    'de',
    'en',
    'es',
    'fr',
    'id',
    'ja',
    'nl',
    'pt',
    'ru',
    'tr',
    'uk',
    'zh',
  ].contains(locale.languageCode);

  @override
  bool shouldReload(_LlmLocalizationsDelegate old) => false;
}

LlmLocalizations lookupLlmLocalizations(Locale locale) {
  // Lookup logic when language+country codes are specified.
  switch (locale.languageCode) {
    case 'zh':
      {
        switch (locale.countryCode) {
          case 'TW':
            return LlmLocalizationsZhTw();
        }
        break;
      }
  }

  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return LlmLocalizationsDe();
    case 'en':
      return LlmLocalizationsEn();
    case 'es':
      return LlmLocalizationsEs();
    case 'fr':
      return LlmLocalizationsFr();
    case 'id':
      return LlmLocalizationsId();
    case 'ja':
      return LlmLocalizationsJa();
    case 'nl':
      return LlmLocalizationsNl();
    case 'pt':
      return LlmLocalizationsPt();
    case 'ru':
      return LlmLocalizationsRu();
    case 'tr':
      return LlmLocalizationsTr();
    case 'uk':
      return LlmLocalizationsUk();
    case 'zh':
      return LlmLocalizationsZh();
  }

  throw FlutterError(
    'LlmLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
