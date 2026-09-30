// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'llm_l10n.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class LlmLocalizationsRu extends LlmLocalizations {
  LlmLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get addServer => 'Добавить сервер';

  @override
  String get allow => 'Разрешить';

  @override
  String get allowAlways => 'Всегда разрешать';

  @override
  String get allowedWithoutAsking => 'Разрешены без запроса';

  @override
  String allowToolFmt(String tool) {
    return 'Разрешить $tool?';
  }

  @override
  String get allProviders => 'Все провайдеры';

  @override
  String alreadyExists(String path) {
    return '$path уже существует';
  }

  @override
  String get attachment => 'Вложение';

  @override
  String attachUnsupported(String name) {
    return 'Не удалось прикрепить $name: только изображения и текстовые файлы до 512 КБ';
  }

  @override
  String get back => 'Назад';

  @override
  String get builtIn => 'Встроенные';

  @override
  String get camera => 'Камера';

  @override
  String charsFmt(int n) {
    return 'Символов: $n';
  }

  @override
  String get chatRead => 'Прочитать чат';

  @override
  String get chatSearch => 'Поиск по чатам';

  @override
  String get compacted => 'Ранние сообщения были сжаты в резюме';

  @override
  String get compaction => 'Сжимать длинные чаты';

  @override
  String get compactionTip =>
      'Когда чат перестаёт помещаться в контекст модели, ранние сообщения пересказываются для модели. Вы по-прежнему видите их все.';

  @override
  String connectedFmt(int n) {
    return 'Подключён · инструментов: $n';
  }

  @override
  String get copied => 'Скопировано';

  @override
  String get customProvider => 'Свой провайдер';

  @override
  String get defaultModel => 'Модель по умолчанию';

  @override
  String get deleteKey => 'Удалить ключ';

  @override
  String get deny => 'Запретить';

  @override
  String get discard => 'Отменить изменения';

  @override
  String get disconnected => 'Отключён';

  @override
  String get endpoint => 'Эндпоинт';

  @override
  String get extraVars => 'Дополнительные переменные';

  @override
  String get extraVarsTip =>
      'По одной KEY=VALUE в строке — для провайдеров, которым нужно больше, чем ключ (ресурс Azure, аккаунт Cloudflare).';

  @override
  String get favorite => 'Избранное';

  @override
  String get history => 'История';

  @override
  String get historyToolTip => 'Искать и читать другие чаты без запроса';

  @override
  String get httpToolTip => 'Загружать веб-страницы и API';

  @override
  String get image => 'Изображение';

  @override
  String invalidLinkFmt(Object uri) {
    return 'Неизвестная ссылка: $uri';
  }

  @override
  String get key => 'Ключ';

  @override
  String get keyInKeychain =>
      'Хранится в системной связке ключей, никогда не попадает в резервные копии.';

  @override
  String get mcpServers => 'Серверы MCP';

  @override
  String get memory => 'Память';

  @override
  String get memoryDelete => 'Удалить из памяти';

  @override
  String get memoryEdit => 'Изменить память';

  @override
  String get memoryMove => 'Переместить в памяти';

  @override
  String get memorySearch => 'Поиск в памяти';

  @override
  String get memoryToolTip =>
      'Файлы, которые модель хранит между чатами; читает и пишет их без запроса';

  @override
  String get memoryView => 'Прочитать память';

  @override
  String get memoryWrite => 'Сохранить в память';

  @override
  String get message => 'Сообщение';

  @override
  String minutesSecondsFmt(int m, int s) {
    return '$m мин $s с';
  }

  @override
  String get model => 'Модель';

  @override
  String modelsCountFmt(int n) {
    return 'Моделей: $n';
  }

  @override
  String get modelsListedTip =>
      'Необязательно: список /models эндпоинта загружается автоматически. Добавьте ID, которых в нём нет.';

  @override
  String get modelsRequired =>
      'Этот API не умеет перечислять модели: укажите хотя бы один ID модели.';

  @override
  String moreFmt(int n) {
    return 'Ещё $n';
  }

  @override
  String get noProviderKey =>
      'Ни у одного провайдера пока нет ключа. Добавьте ключ, чтобы начать чат.';

  @override
  String get refreshModels => 'Обновить модели';

  @override
  String get regenerate => 'Сгенерировать заново';

  @override
  String get replyInterrupted => 'Ответ был прерван';

  @override
  String get replyWaits => 'Ответ ждёт вашего решения.';

  @override
  String get resumeReply => 'Продолжить';

  @override
  String get sameAsChat => 'Как в чате';

  @override
  String get searchModels => 'Поиск моделей';

  @override
  String get searchProviders => 'Поиск провайдеров';

  @override
  String secondsFmt(String n) {
    return '$n с';
  }

  @override
  String get send => 'Отправить';

  @override
  String get systemPrompt => 'Системный промпт';

  @override
  String get thought => 'Размышления';

  @override
  String thoughtForFmt(String time) {
    return 'Размышлял $time';
  }

  @override
  String get titleModel => 'Модель для заголовков';

  @override
  String tokensFmt(String n) {
    return 'Токенов: $n';
  }

  @override
  String get tool => 'Инструмент';

  @override
  String get toolHttpReqName => 'HTTP-запрос';

  @override
  String get unsavedChanges => 'Сохранить изменения перед выходом?';

  @override
  String get untitled => 'Без названия';

  @override
  String usableModelsFmt(int n, int m) {
    return 'Доступно: $n · провайдеров: $m';
  }

  @override
  String get useTools => 'Использовать инструменты';

  @override
  String get useToolsTip =>
      'Каждый вызов сначала спрашивает, если он не разрешён ниже';

  @override
  String get allowInsecure => 'Разрешить незашифрованный HTTP';

  @override
  String get allowInsecureTip =>
      'Этот адрес — http:// вне этого устройства: ключ API передаётся без шифрования и доступен любому на сетевом пути. Разрешайте только в доверенной сети.';

  @override
  String get configure => 'Настроить';

  @override
  String get supportsThinking => 'Поддерживает рассуждения';

  @override
  String get thinkingEffort => 'Глубина рассуждений';

  @override
  String get mcpHeaders => 'Заголовки';

  @override
  String get mcpHeadersTip =>
      'Необязательно, например Authorization со значением Bearer <token>. Хранятся только на этом устройстве, не попадают в резервные копии и отправляются только этому серверу.';

  @override
  String get mcpHeadersInvalid =>
      'Заголовку нужны имя из букв, цифр и дефисов и значение.';

  @override
  String get mcpNeedsSignIn => 'Требуется вход';

  @override
  String get mcpSigningIn => 'Завершите вход в браузере';

  @override
  String get mcpSignedIn => 'Вход выполнен. Эту страницу можно закрыть.';

  @override
  String get mcpSignedInShort => 'Вход выполнен';

  @override
  String get mcpSignInFailed =>
      'Не удалось войти. Закройте страницу и попробуйте снова.';

  @override
  String get mcpInsecure =>
      'Заголовки и вход доступны только для адреса https.';

  @override
  String get mcpAddHeader => 'Добавить заголовок';

  @override
  String get mcpNotSignedIn => 'Вход не выполнен';

  @override
  String get mcpSignInTip =>
      'Для сервера с OAuth. Вход выполняется в браузере, токен обновляется автоматически.';

  @override
  String get mcpConnecting => 'Подключение…';

  @override
  String get skills => 'Skills';

  @override
  String get skillsTip =>
      'Инструкции для определённых задач: модель читает их, когда задача подходит. Устанавливайте только из надёжных источников: модель следует тому, что написано в skill.';

  @override
  String get skillSourceInvalid =>
      'Это не репозиторий, ссылка или команда `npx skills add`';

  @override
  String get skillsNotFound => 'Там не найдено skills';

  @override
  String get skillsPick => 'Какие skills установить';

  @override
  String skillsInstalledFmt(int n) {
    return 'Установлено: $n';
  }

  @override
  String get skillsUpToDate => 'Всё актуально';

  @override
  String skillsUpdatedFmt(int n) {
    return 'Обновлено: $n';
  }

  @override
  String get skillsFromFolder => 'Установить из папки';

  @override
  String get skillsFromZip => 'Установить из .zip';

  @override
  String skillsUpdateFailedFmt(int n) {
    return 'Не удалось проверить источники: $n';
  }

  @override
  String get skillBuiltin => 'Встроенный';
}
