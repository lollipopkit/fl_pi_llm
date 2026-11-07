// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'llm_l10n.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class LlmLocalizationsEn extends LlmLocalizations {
  LlmLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get addServer => 'Add server';

  @override
  String get allow => 'Allow';

  @override
  String get allowAlways => 'Always allow';

  @override
  String get allowedWithoutAsking => 'Allowed without asking';

  @override
  String allowToolFmt(String tool) {
    return 'Allow $tool?';
  }

  @override
  String get allProviders => 'All providers';

  @override
  String alreadyExists(String path) {
    return '$path already exists';
  }

  @override
  String get attachment => 'Attachment';

  @override
  String attachUnsupported(String name) {
    return 'Cannot attach $name: only images and text files up to 512 KB';
  }

  @override
  String get back => 'Back';

  @override
  String get builtIn => 'Built-in';

  @override
  String get camera => 'Camera';

  @override
  String charsFmt(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n characters',
      one: '1 character',
    );
    return '$_temp0';
  }

  @override
  String get chatRead => 'Read chat';

  @override
  String get chatSearch => 'Search chats';

  @override
  String get compacted => 'Earlier messages were summarised';

  @override
  String get compaction => 'Compact long chats';

  @override
  String get compactionTip =>
      'When a chat no longer fits the model\'s context, earlier messages are summarised for the model. You still see all of them.';

  @override
  String connectedFmt(int n) {
    return 'Connected · $n tools';
  }

  @override
  String get copied => 'Copied';

  @override
  String get customProvider => 'Custom provider';

  @override
  String get defaultModel => 'Default model';

  @override
  String get deleteKey => 'Delete key';

  @override
  String get deny => 'Deny';

  @override
  String get discard => 'Discard';

  @override
  String get disconnected => 'Disconnected';

  @override
  String get endpoint => 'Endpoint';

  @override
  String get extraVars => 'Extra variables';

  @override
  String get extraVarsTip =>
      'KEY=VALUE per line, for providers that need more than a key (Azure resource, Cloudflare account).';

  @override
  String get favorite => 'Favorites';

  @override
  String get history => 'History';

  @override
  String get historyToolTip =>
      'Search and read your other chats, without asking';

  @override
  String get httpToolTip => 'Fetch web pages and APIs';

  @override
  String get image => 'Image';

  @override
  String invalidLinkFmt(Object uri) {
    return 'Invalid link: $uri';
  }

  @override
  String get key => 'Key';

  @override
  String get keyInKeychain =>
      'Stored in the system keychain, never in backups.';

  @override
  String get mcpServers => 'MCP servers';

  @override
  String get memory => 'Memory';

  @override
  String get memoryDelete => 'Delete memory';

  @override
  String get memoryEdit => 'Edit memory';

  @override
  String get memoryMove => 'Move memory';

  @override
  String get memorySearch => 'Search memory';

  @override
  String get memoryToolTip =>
      'Files the model keeps across chats, read and written without asking';

  @override
  String get memoryView => 'Read memory';

  @override
  String get memoryWrite => 'Save memory';

  @override
  String get message => 'Message';

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
      other: '$n models',
      one: '1 model',
    );
    return '$_temp0';
  }

  @override
  String get modelsListedTip =>
      'Optional: the endpoint\'s /models list is fetched. Add ids it does not list.';

  @override
  String get modelsRequired =>
      'This API cannot list its models: enter at least one model id.';

  @override
  String moreFmt(int n) {
    return '$n more';
  }

  @override
  String get noProviderKey =>
      'No provider has a key yet. Add one to start chatting.';

  @override
  String get refreshModels => 'Refresh models';

  @override
  String get regenerate => 'Regenerate';

  @override
  String get replyInterrupted => 'The reply was interrupted';

  @override
  String get replyWaits => 'The reply waits for your answer.';

  @override
  String get resumeReply => 'Continue';

  @override
  String get sameAsChat => 'Same as the chat';

  @override
  String get searchModels => 'Search models';

  @override
  String get searchProviders => 'Search providers';

  @override
  String secondsFmt(String n) {
    return '$n s';
  }

  @override
  String get send => 'Send';

  @override
  String get systemPrompt => 'System prompt';

  @override
  String get thought => 'Thought';

  @override
  String thoughtForFmt(String time) {
    return 'Thought for $time';
  }

  @override
  String get titleModel => 'Model for titles';

  @override
  String tokensFmt(String n) {
    return '$n tokens';
  }

  @override
  String get tool => 'Tool';

  @override
  String get toolHttpReqName => 'HTTP request';

  @override
  String get unsavedChanges => 'Save your changes before leaving?';

  @override
  String get untitled => 'Untitled';

  @override
  String usableModelsFmt(int n, int m) {
    String _temp0 = intl.Intl.pluralLogic(
      m,
      locale: localeName,
      other: '$m providers',
      one: '1 provider',
    );
    return '$n usable · $_temp0';
  }

  @override
  String get useTools => 'Use tools';

  @override
  String get useToolsTip => 'Each call asks first unless it is allowed below';

  @override
  String get allowInsecure => 'Allow plain HTTP';

  @override
  String get allowInsecureTip =>
      'This address is http:// off this device: the API key is sent unencrypted, readable to anyone on the network path. Allow it only on a network you trust.';

  @override
  String get configure => 'Configure';

  @override
  String get supportsThinking => 'Thinking';

  @override
  String get thinkingEffort => 'Thinking effort';

  @override
  String get mcpHeaders => 'Headers';

  @override
  String get mcpHeadersTip =>
      'Optional, such as Authorization with Bearer <token>. Kept on this device only, never backed up, and sent only to this server.';

  @override
  String get mcpHeadersInvalid =>
      'A header needs a name of letters, digits and dashes, and a value.';

  @override
  String get mcpNeedsSignIn => 'Sign-in required';

  @override
  String get mcpSigningIn => 'Finish signing in in the browser';

  @override
  String get mcpSignedIn => 'Signed in. You can close this page.';

  @override
  String get mcpSignedInShort => 'Signed in';

  @override
  String get mcpSignInFailed =>
      'Sign-in failed. You can close this page and try again.';

  @override
  String get mcpInsecure =>
      'Only an https address can be sent headers or signed in to.';

  @override
  String get mcpAddHeader => 'Add header';

  @override
  String get mcpNotSignedIn => 'Not signed in';

  @override
  String get mcpSignInTip =>
      'For a server that uses OAuth. You sign in in the browser, and the token is renewed on its own.';

  @override
  String get mcpConnecting => 'Connecting…';

  @override
  String get skills => 'Skills';

  @override
  String get skillsTip =>
      'Instructions for particular tasks, which the model reads when a task matches one. Install only from sources you trust: the model follows what a skill says.';

  @override
  String get skillSourceInvalid =>
      'Not a repository, link or `npx skills add` command';

  @override
  String get skillsNotFound => 'No skills found there';

  @override
  String get skillsPick => 'Skills to install';

  @override
  String skillsInstalledFmt(int n) {
    return 'Installed $n';
  }

  @override
  String get skillsUpToDate => 'Up to date';

  @override
  String skillsUpdatedFmt(int n) {
    return 'Updated $n';
  }

  @override
  String get skillsFromFolder => 'Install from a folder';

  @override
  String get skillsFromZip => 'Install from a .zip';

  @override
  String skillsUpdateFailedFmt(int n) {
    return '$n sources could not be checked';
  }

  @override
  String get skillBuiltin => 'Built in';

  @override
  String keyFromEnvFmt(String name) {
    return 'Key from $name';
  }

  @override
  String keyFromEnvTipFmt(String name) {
    return 'The key now in use is the environment variable $name. A key entered here takes its place.';
  }

  @override
  String get skillUpdateAvailable => 'Update available';

  @override
  String skillsUpdateAllFmt(int n) {
    return 'Update all ($n)';
  }

  @override
  String get askUser => 'Ask you';

  @override
  String get fieldRequired => 'Required';

  @override
  String get fieldInvalid => 'Not valid';

  @override
  String get waitingForYou => 'Waiting for you';

  @override
  String get otherAnswer => 'Other';

  @override
  String get otherAnswerHint => 'Your own answer';

  @override
  String get commandRiskReadOnly => 'Read-only';

  @override
  String get commandRiskUnknown => 'Unclassified';

  @override
  String get commandRiskCaution => 'Changes system';

  @override
  String get commandRiskDestructive => 'High risk';

  @override
  String get permMode => 'Permission mode';

  @override
  String get permModeAuto => 'Auto';

  @override
  String get permModeManual => 'Manual';

  @override
  String get permModeBypass => 'Allow all';

  @override
  String get permModeBypassOff => 'Turned off on this server';

  @override
  String get permTitle => 'Command permissions';

  @override
  String get permDefaultMode => 'Default mode';

  @override
  String get permManualNote => 'New tasks ask about every step no rule allows.';

  @override
  String get permAutoNote =>
      'New tasks have every step no rule allows judged by the model against the auto mode rules below: allowed runs it, blocked tells the agent why; with no verdict you are asked.';

  @override
  String get permBypassNote =>
      'New tasks run every step unasked, deleting, restarting and config changes included. Deny and ask rules still apply.';

  @override
  String get permDisableBypass => 'Turn off Allow all';

  @override
  String get permDisableBypassSub =>
      'No task runs in Allow all; one started in it asks as in Manual.';

  @override
  String get permDangerAsks =>
      'Unless a task allows all, a command that cannot be undone (deleting data, partitions) asks you to type the server\'s name.';

  @override
  String get permRules => 'Command rules';

  @override
  String get permDeny => 'Deny';

  @override
  String get permAsk => 'Ask';

  @override
  String get permAllow => 'Allow';

  @override
  String get permRulesHint =>
      'One per line. * is any text, as in systemctl status * or apt-get install *; a trailing :* is the same as \" *\". A chained command is checked part by part: deny and ask apply when any part matches, allow only when every part is covered. Rules match the command as written (sh -c \'rm …\' does not match rm *); they are not a security boundary.';

  @override
  String get permAutoRules => 'Auto mode rules';

  @override
  String get permAutoHint =>
      'Plain-language rules the model judges by. Empty uses the built-in list; a line \$defaults keeps it and adds yours. Order: hard deny, then soft deny (an allow rule or your own explicit request clears it), then allow.';

  @override
  String get permEnvironment => 'Environment';

  @override
  String get permSoftDeny => 'Soft deny';

  @override
  String get permHardDeny => 'Hard deny';

  @override
  String get permBuiltIn => 'Built-in rules';

  @override
  String permShowDefaults(int n) {
    return 'Built-in rules ($n)';
  }

  @override
  String get discardUnsaved => 'Discard unsaved changes?';
}
