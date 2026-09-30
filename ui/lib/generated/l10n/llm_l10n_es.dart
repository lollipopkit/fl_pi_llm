// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'llm_l10n.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class LlmLocalizationsEs extends LlmLocalizations {
  LlmLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get addServer => 'Añadir servidor';

  @override
  String get allow => 'Permitir';

  @override
  String get allowAlways => 'Permitir siempre';

  @override
  String get allowedWithoutAsking => 'Permitidas sin preguntar';

  @override
  String allowToolFmt(String tool) {
    return '¿Permitir $tool?';
  }

  @override
  String get allProviders => 'Todos los proveedores';

  @override
  String alreadyExists(String path) {
    return '$path ya existe';
  }

  @override
  String get attachment => 'Adjunto';

  @override
  String attachUnsupported(String name) {
    return 'No se puede adjuntar $name: solo imágenes y archivos de texto de hasta 512 KB';
  }

  @override
  String get back => 'Atrás';

  @override
  String get builtIn => 'Integradas';

  @override
  String get camera => 'Cámara';

  @override
  String charsFmt(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n caracteres',
      one: '1 carácter',
    );
    return '$_temp0';
  }

  @override
  String get chatRead => 'Leer chat';

  @override
  String get chatSearch => 'Buscar chats';

  @override
  String get compacted => 'Los mensajes anteriores se resumieron';

  @override
  String get compaction => 'Compactar chats largos';

  @override
  String get compactionTip =>
      'Cuando un chat ya no cabe en el contexto del modelo, los mensajes anteriores se resumen para el modelo. Tú los sigues viendo todos.';

  @override
  String connectedFmt(int n) {
    return 'Conectado · $n herramientas';
  }

  @override
  String get copied => 'Copiado';

  @override
  String get customProvider => 'Proveedor personalizado';

  @override
  String get defaultModel => 'Modelo predeterminado';

  @override
  String get deleteKey => 'Eliminar clave';

  @override
  String get deny => 'Denegar';

  @override
  String get discard => 'Descartar';

  @override
  String get disconnected => 'Desconectado';

  @override
  String get endpoint => 'Endpoint';

  @override
  String get extraVars => 'Variables adicionales';

  @override
  String get extraVarsTip =>
      'Una KEY=VALUE por línea, para proveedores que necesitan algo más que una clave (recurso de Azure, cuenta de Cloudflare).';

  @override
  String get favorite => 'Favoritos';

  @override
  String get history => 'Historial';

  @override
  String get historyToolTip => 'Buscar y leer tus otros chats, sin preguntar';

  @override
  String get httpToolTip => 'Obtener páginas web y APIs';

  @override
  String get image => 'Imagen';

  @override
  String invalidLinkFmt(Object uri) {
    return 'Enlace desconocido: $uri';
  }

  @override
  String get key => 'Clave';

  @override
  String get keyInKeychain =>
      'Guardada en el llavero del sistema, nunca en las copias de seguridad.';

  @override
  String get mcpServers => 'Servidores MCP';

  @override
  String get memory => 'Memoria';

  @override
  String get memoryDelete => 'Eliminar memoria';

  @override
  String get memoryEdit => 'Editar memoria';

  @override
  String get memoryMove => 'Mover memoria';

  @override
  String get memorySearch => 'Buscar en la memoria';

  @override
  String get memoryToolTip =>
      'Archivos que el modelo conserva entre chats; los lee y escribe sin preguntar';

  @override
  String get memoryView => 'Leer memoria';

  @override
  String get memoryWrite => 'Guardar memoria';

  @override
  String get message => 'Mensaje';

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
      'Opcional: se obtiene la lista /models del endpoint. Añade los ID que no aparezcan.';

  @override
  String get modelsRequired =>
      'Esta API no puede listar sus modelos: introduce al menos un ID de modelo.';

  @override
  String moreFmt(int n) {
    return '$n más';
  }

  @override
  String get noProviderKey =>
      'Ningún proveedor tiene clave todavía. Añade una para empezar a chatear.';

  @override
  String get refreshModels => 'Actualizar modelos';

  @override
  String get regenerate => 'Regenerar';

  @override
  String get replyInterrupted => 'La respuesta se interrumpió';

  @override
  String get replyWaits => 'La respuesta espera tu decisión.';

  @override
  String get resumeReply => 'Continuar';

  @override
  String get sameAsChat => 'Igual que el chat';

  @override
  String get searchModels => 'Buscar modelos';

  @override
  String get searchProviders => 'Buscar proveedores';

  @override
  String secondsFmt(String n) {
    return '$n s';
  }

  @override
  String get send => 'Enviar';

  @override
  String get systemPrompt => 'Prompt del sistema';

  @override
  String get thought => 'Razonamiento';

  @override
  String thoughtForFmt(String time) {
    return 'Pensó $time';
  }

  @override
  String get titleModel => 'Modelo para títulos';

  @override
  String tokensFmt(String n) {
    return '$n tokens';
  }

  @override
  String get tool => 'Herramienta';

  @override
  String get toolHttpReqName => 'Solicitud HTTP';

  @override
  String get unsavedChanges => '¿Guardar los cambios antes de salir?';

  @override
  String get untitled => 'Sin título';

  @override
  String usableModelsFmt(int n, int m) {
    return '$n disponibles · $m proveedores';
  }

  @override
  String get useTools => 'Usar herramientas';

  @override
  String get useToolsTip =>
      'Cada llamada pregunta primero salvo que esté permitida abajo';

  @override
  String get allowInsecure => 'Permitir HTTP sin cifrar';

  @override
  String get allowInsecureTip =>
      'Esta dirección es http:// fuera de este dispositivo: la clave de API se envía sin cifrar y cualquiera en la ruta de red puede leerla. Permítelo solo en una red de confianza.';

  @override
  String get configure => 'Configurar';

  @override
  String get supportsThinking => 'Admite razonamiento';

  @override
  String get thinkingEffort => 'Esfuerzo de razonamiento';

  @override
  String get mcpHeaders => 'Encabezados';

  @override
  String get mcpHeadersTip =>
      'Opcional, como Authorization con Bearer <token>. Se guarda solo en este dispositivo, nunca en copias de seguridad, y solo se envía a este servidor.';

  @override
  String get mcpHeadersInvalid =>
      'Un encabezado necesita un nombre de letras, dígitos y guiones, y un valor.';

  @override
  String get mcpNeedsSignIn => 'Requiere iniciar sesión';

  @override
  String get mcpSigningIn => 'Termina de iniciar sesión en el navegador';

  @override
  String get mcpSignedIn => 'Sesión iniciada. Puedes cerrar esta página.';

  @override
  String get mcpSignedInShort => 'Sesión iniciada';

  @override
  String get mcpSignInFailed =>
      'No se pudo iniciar sesión. Cierra esta página e inténtalo de nuevo.';

  @override
  String get mcpInsecure =>
      'Solo una dirección https puede recibir encabezados o iniciar sesión.';

  @override
  String get mcpAddHeader => 'Añadir encabezado';

  @override
  String get mcpNotSignedIn => 'Sin iniciar sesión';

  @override
  String get mcpSignInTip =>
      'Para un servidor que usa OAuth. Inicias sesión en el navegador y el token se renueva solo.';

  @override
  String get mcpConnecting => 'Conectando…';

  @override
  String get skills => 'Skills';

  @override
  String get skillsTip =>
      'Instrucciones para tareas concretas que el modelo lee cuando una tarea encaja. Instala solo desde fuentes de confianza: el modelo sigue lo que dice un skill.';

  @override
  String get skillSourceInvalid =>
      'No es un repositorio, enlace ni comando `npx skills add`';

  @override
  String get skillsNotFound => 'No se encontraron skills ahí';

  @override
  String get skillsPick => 'Skills para instalar';

  @override
  String skillsInstalledFmt(int n) {
    return '$n instalados';
  }

  @override
  String get skillsUpToDate => 'Al día';

  @override
  String skillsUpdatedFmt(int n) {
    return '$n actualizados';
  }

  @override
  String get skillsFromFolder => 'Instalar desde una carpeta';

  @override
  String get skillsFromZip => 'Instalar desde un .zip';

  @override
  String skillsUpdateFailedFmt(int n) {
    return 'No se pudieron comprobar $n fuentes';
  }

  @override
  String get skillBuiltin => 'Integrado';

  @override
  String keyFromEnvFmt(String name) {
    return 'Clave de $name';
  }

  @override
  String keyFromEnvTipFmt(String name) {
    return 'Se usa la clave de la variable de entorno $name. Una clave introducida aquí tiene prioridad.';
  }

  @override
  String get skillUpdateAvailable => 'Actualización disponible';

  @override
  String skillsUpdateAllFmt(int n) {
    return 'Actualizar todo ($n)';
  }

  @override
  String get askUser => 'Preguntarte';

  @override
  String get fieldRequired => 'Obligatorio';

  @override
  String get fieldInvalid => 'No válido';

  @override
  String get waitingForYou => 'Te espera';

  @override
  String get otherAnswer => 'Otra';

  @override
  String get otherAnswerHint => 'Tu propia respuesta';
}
