// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'llm_l10n.dart';

// ignore_for_file: type=lint

/// The translations for Portuguese (`pt`).
class LlmLocalizationsPt extends LlmLocalizations {
  LlmLocalizationsPt([String locale = 'pt']) : super(locale);

  @override
  String get addServer => 'Adicionar servidor';

  @override
  String get allow => 'Permitir';

  @override
  String get allowAlways => 'Sempre permitir';

  @override
  String get allowedWithoutAsking => 'Permitidas sem perguntar';

  @override
  String allowToolFmt(String tool) {
    return 'Permitir $tool?';
  }

  @override
  String get allProviders => 'Todos os provedores';

  @override
  String alreadyExists(String path) {
    return '$path já existe';
  }

  @override
  String get attachment => 'Anexo';

  @override
  String attachUnsupported(String name) {
    return 'Não é possível anexar $name: apenas imagens e arquivos de texto até 512 KB';
  }

  @override
  String get back => 'Voltar';

  @override
  String get builtIn => 'Integradas';

  @override
  String get camera => 'Câmera';

  @override
  String charsFmt(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n caracteres',
      one: '1 caractere',
    );
    return '$_temp0';
  }

  @override
  String get chatRead => 'Ler chat';

  @override
  String get chatSearch => 'Pesquisar chats';

  @override
  String get compacted => 'As mensagens anteriores foram resumidas';

  @override
  String get compaction => 'Compactar conversas longas';

  @override
  String get compactionTip =>
      'Quando uma conversa não cabe mais no contexto do modelo, as mensagens anteriores são resumidas para o modelo. Você continua vendo todas.';

  @override
  String connectedFmt(int n) {
    return 'Conectado · $n ferramentas';
  }

  @override
  String get copied => 'Copiado';

  @override
  String get customProvider => 'Provedor personalizado';

  @override
  String get defaultModel => 'Modelo padrão';

  @override
  String get deleteKey => 'Excluir chave';

  @override
  String get deny => 'Negar';

  @override
  String get discard => 'Descartar';

  @override
  String get disconnected => 'Desconectado';

  @override
  String get endpoint => 'Endpoint';

  @override
  String get extraVars => 'Variáveis extras';

  @override
  String get extraVarsTip =>
      'Uma KEY=VALUE por linha, para provedores que precisam de mais que uma chave (recurso do Azure, conta do Cloudflare).';

  @override
  String get favorite => 'Favoritos';

  @override
  String get history => 'Histórico';

  @override
  String get historyToolTip =>
      'Pesquisar e ler seus outros chats, sem perguntar';

  @override
  String get httpToolTip => 'Buscar páginas web e APIs';

  @override
  String get image => 'Imagem';

  @override
  String invalidLinkFmt(Object uri) {
    return 'Link desconhecido: $uri';
  }

  @override
  String get key => 'Chave';

  @override
  String get keyInKeychain =>
      'Guardada no chaveiro do sistema, nunca nos backups.';

  @override
  String get mcpServers => 'Servidores MCP';

  @override
  String get memory => 'Memória';

  @override
  String get memoryDelete => 'Excluir memória';

  @override
  String get memoryEdit => 'Editar memória';

  @override
  String get memoryMove => 'Mover memória';

  @override
  String get memorySearch => 'Pesquisar na memória';

  @override
  String get memoryToolTip =>
      'Arquivos que o modelo mantém entre chats; lê e escreve sem perguntar';

  @override
  String get memoryView => 'Ler memória';

  @override
  String get memoryWrite => 'Guardar memória';

  @override
  String get message => 'Mensagem';

  @override
  String minutesSecondsFmt(int m, int s) {
    return '$m min $s s';
  }

  @override
  String get model => 'Modelo';

  @override
  String modelsCountFmt(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n modelos',
      one: '1 modelo',
    );
    return '$_temp0';
  }

  @override
  String get modelsListedTip =>
      'Opcional: a lista /models do endpoint é obtida. Adicione os IDs que não estiverem nela.';

  @override
  String get modelsRequired =>
      'Esta API não consegue listar seus modelos: informe pelo menos um ID de modelo.';

  @override
  String moreFmt(int n) {
    return 'mais $n';
  }

  @override
  String get noProviderKey =>
      'Nenhum provedor tem chave ainda. Adicione uma para começar a conversar.';

  @override
  String get refreshModels => 'Atualizar modelos';

  @override
  String get regenerate => 'Gerar novamente';

  @override
  String get replyInterrupted => 'A resposta foi interrompida';

  @override
  String get replyWaits => 'A resposta aguarda sua decisão.';

  @override
  String get resumeReply => 'Continuar';

  @override
  String get sameAsChat => 'Igual à conversa';

  @override
  String get searchModels => 'Buscar modelos';

  @override
  String get searchProviders => 'Buscar provedores';

  @override
  String secondsFmt(String n) {
    return '$n s';
  }

  @override
  String get send => 'Enviar';

  @override
  String get systemPrompt => 'Prompt do sistema';

  @override
  String get thought => 'Raciocínio';

  @override
  String thoughtForFmt(String time) {
    return 'Pensou por $time';
  }

  @override
  String get titleModel => 'Modelo para títulos';

  @override
  String tokensFmt(String n) {
    return '$n tokens';
  }

  @override
  String get tool => 'Ferramenta';

  @override
  String get toolHttpReqName => 'Solicitação HTTP';

  @override
  String get unsavedChanges => 'Salvar as alterações antes de sair?';

  @override
  String get untitled => 'Sem título';

  @override
  String usableModelsFmt(int n, int m) {
    return '$n disponíveis · $m provedores';
  }

  @override
  String get useTools => 'Usar ferramentas';

  @override
  String get useToolsTip =>
      'Cada chamada pergunta antes, a menos que esteja permitida abaixo';
}
