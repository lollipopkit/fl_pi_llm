// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'llm_l10n.dart';

// ignore_for_file: type=lint

/// The translations for Ukrainian (`uk`).
class LlmLocalizationsUk extends LlmLocalizations {
  LlmLocalizationsUk([String locale = 'uk']) : super(locale);

  @override
  String get addServer => 'Додати сервер';

  @override
  String get allow => 'Дозволити';

  @override
  String get allowAlways => 'Завжди дозволяти';

  @override
  String get allowedWithoutAsking => 'Дозволені без запиту';

  @override
  String allowToolFmt(String tool) {
    return 'Дозволити $tool?';
  }

  @override
  String get allProviders => 'Усі провайдери';

  @override
  String alreadyExists(String path) {
    return '$path вже існує';
  }

  @override
  String get attachment => 'Вкладення';

  @override
  String attachUnsupported(String name) {
    return 'Не вдалося прикріпити $name: лише зображення й текстові файли до 512 КБ';
  }

  @override
  String get back => 'Назад';

  @override
  String get builtIn => 'Вбудовані';

  @override
  String get camera => 'Камера';

  @override
  String charsFmt(int n) {
    return 'Символів: $n';
  }

  @override
  String get chatRead => 'Прочитати чат';

  @override
  String get chatSearch => 'Пошук у чатах';

  @override
  String get compacted => 'Ранні повідомлення стиснуто в підсумок';

  @override
  String get compaction => 'Стискати довгі чати';

  @override
  String get compactionTip =>
      'Коли чат більше не вміщається в контекст моделі, ранні повідомлення підсумовуються для моделі. Ви й далі бачите їх усі.';

  @override
  String connectedFmt(int n) {
    return 'Підключено · інструментів: $n';
  }

  @override
  String get copied => 'Скопійовано';

  @override
  String get customProvider => 'Власний провайдер';

  @override
  String get defaultModel => 'Модель за замовчуванням';

  @override
  String get deleteKey => 'Видалити ключ';

  @override
  String get deny => 'Заборонити';

  @override
  String get discard => 'Скасувати зміни';

  @override
  String get disconnected => 'Відключено';

  @override
  String get endpoint => 'Ендпоінт';

  @override
  String get extraVars => 'Додаткові змінні';

  @override
  String get extraVarsTip =>
      'Одна KEY=VALUE на рядок — для провайдерів, яким потрібно більше, ніж ключ (ресурс Azure, акаунт Cloudflare).';

  @override
  String get favorite => 'Обране';

  @override
  String get history => 'Історія';

  @override
  String get historyToolTip => 'Шукати й читати інші чати без запиту';

  @override
  String get httpToolTip => 'Завантажувати вебсторінки та API';

  @override
  String get image => 'Зображення';

  @override
  String invalidLinkFmt(Object uri) {
    return 'Невідоме посилання: $uri';
  }

  @override
  String get key => 'Ключ';

  @override
  String get keyInKeychain =>
      'Зберігається в системній вʼязці ключів, ніколи не потрапляє в резервні копії.';

  @override
  String get mcpServers => 'Сервери MCP';

  @override
  String get memory => 'Пам\'ять';

  @override
  String get memoryDelete => 'Видалити з пам\'яті';

  @override
  String get memoryEdit => 'Змінити пам\'ять';

  @override
  String get memoryMove => 'Перемістити в пам\'яті';

  @override
  String get memorySearch => 'Пошук у пам\'яті';

  @override
  String get memoryToolTip =>
      'Файли, які модель зберігає між чатами; читає й пише їх без запиту';

  @override
  String get memoryView => 'Прочитати пам\'ять';

  @override
  String get memoryWrite => 'Зберегти в пам\'ять';

  @override
  String get message => 'Повідомлення';

  @override
  String minutesSecondsFmt(int m, int s) {
    return '$m хв $s с';
  }

  @override
  String get model => 'Модель';

  @override
  String modelsCountFmt(int n) {
    return 'Моделей: $n';
  }

  @override
  String get modelsListedTip =>
      'Необовʼязково: список /models ендпоінта завантажується автоматично. Додайте ID, яких у ньому немає.';

  @override
  String get modelsRequired =>
      'Цей API не вміє перелічувати моделі: вкажіть щонайменше один ID моделі.';

  @override
  String moreFmt(int n) {
    return 'Ще $n';
  }

  @override
  String get noProviderKey =>
      'Жоден провайдер ще не має ключа. Додайте ключ, щоб почати чат.';

  @override
  String get refreshModels => 'Оновити моделі';

  @override
  String get regenerate => 'Згенерувати знову';

  @override
  String get replyInterrupted => 'Відповідь було перервано';

  @override
  String get replyWaits => 'Відповідь чекає на ваше рішення.';

  @override
  String get resumeReply => 'Продовжити';

  @override
  String get sameAsChat => 'Як у чаті';

  @override
  String get searchModels => 'Пошук моделей';

  @override
  String get searchProviders => 'Пошук провайдерів';

  @override
  String secondsFmt(String n) {
    return '$n с';
  }

  @override
  String get send => 'Надіслати';

  @override
  String get systemPrompt => 'Системний промпт';

  @override
  String get thought => 'Роздуми';

  @override
  String thoughtForFmt(String time) {
    return 'Розмірковував $time';
  }

  @override
  String get titleModel => 'Модель для заголовків';

  @override
  String tokensFmt(String n) {
    return 'Токенів: $n';
  }

  @override
  String get tool => 'Інструмент';

  @override
  String get toolHttpReqName => 'HTTP-запит';

  @override
  String get unsavedChanges => 'Зберегти зміни перед виходом?';

  @override
  String get untitled => 'Без назви';

  @override
  String usableModelsFmt(int n, int m) {
    return 'Доступно: $n · провайдерів: $m';
  }

  @override
  String get useTools => 'Використовувати інструменти';

  @override
  String get useToolsTip =>
      'Кожен виклик спершу питає, якщо його не дозволено нижче';

  @override
  String get allowInsecure => 'Дозволити незашифрований HTTP';

  @override
  String get allowInsecureTip =>
      'Ця адреса — http:// поза цим пристроєм: ключ API надсилається без шифрування і доступний будь-кому на мережевому шляху. Дозволяйте лише в довіреній мережі.';

  @override
  String get configure => 'Налаштувати';

  @override
  String get supportsThinking => 'Підтримує міркування';

  @override
  String get thinkingEffort => 'Глибина міркувань';

  @override
  String get mcpHeaders => 'Заголовки';

  @override
  String get mcpHeadersTip =>
      'Необов’язково, наприклад Authorization зі значенням Bearer <token>. Зберігаються лише на цьому пристрої, не потрапляють у резервні копії й надсилаються лише цьому серверу.';

  @override
  String get mcpHeadersInvalid =>
      'Заголовку потрібні назва з літер, цифр і дефісів та значення.';

  @override
  String get mcpNeedsSignIn => 'Потрібен вхід';

  @override
  String get mcpSigningIn => 'Завершіть вхід у браузері';

  @override
  String get mcpSignedIn => 'Вхід виконано. Цю сторінку можна закрити.';

  @override
  String get mcpSignedInShort => 'Вхід виконано';

  @override
  String get mcpSignInFailed =>
      'Не вдалося увійти. Закрийте сторінку й спробуйте ще раз.';

  @override
  String get mcpInsecure => 'Заголовки та вхід доступні лише для адреси https.';

  @override
  String get mcpAddHeader => 'Додати заголовок';

  @override
  String get mcpNotSignedIn => 'Вхід не виконано';

  @override
  String get mcpSignInTip =>
      'Для сервера з OAuth. Вхід виконується в браузері, токен оновлюється автоматично.';

  @override
  String get mcpConnecting => 'Підключення…';

  @override
  String get skills => 'Skills';

  @override
  String get skillsTip =>
      'Інструкції для певних завдань: модель читає їх, коли завдання підходить. Встановлюйте лише з надійних джерел: модель дотримується того, що написано в skill.';

  @override
  String get skillSourceInvalid =>
      'Це не репозиторій, посилання чи команда `npx skills add`';

  @override
  String get skillsNotFound => 'Там не знайдено skills';

  @override
  String get skillsPick => 'Які skills встановити';

  @override
  String skillsInstalledFmt(int n) {
    return 'Встановлено: $n';
  }

  @override
  String get skillsUpToDate => 'Усе актуально';

  @override
  String skillsUpdatedFmt(int n) {
    return 'Оновлено: $n';
  }

  @override
  String get skillsFromFolder => 'Встановити з теки';

  @override
  String get skillsFromZip => 'Встановити з .zip';

  @override
  String skillsUpdateFailedFmt(int n) {
    return 'Не вдалося перевірити джерела: $n';
  }

  @override
  String get skillBuiltin => 'Вбудований';

  @override
  String keyFromEnvFmt(String name) {
    return 'Ключ із $name';
  }

  @override
  String keyFromEnvTipFmt(String name) {
    return 'Зараз використовується ключ зі змінної середовища $name. Ключ, введений тут, має пріоритет.';
  }

  @override
  String get skillUpdateAvailable => 'Є оновлення';

  @override
  String skillsUpdateAllFmt(int n) {
    return 'Оновити все ($n)';
  }

  @override
  String get askUser => 'Запитати вас';

  @override
  String get fieldRequired => 'Обовʼязково';

  @override
  String get fieldInvalid => 'Неправильний формат';

  @override
  String get waitingForYou => 'Чекає на вас';

  @override
  String get otherAnswer => 'Інше';

  @override
  String get otherAnswerHint => 'Власна відповідь';

  @override
  String get commandRiskReadOnly => 'Лише читання';

  @override
  String get commandRiskUnknown => 'Не визначено';

  @override
  String get commandRiskCaution => 'Змінює систему';

  @override
  String get commandRiskDestructive => 'Високий ризик';

  @override
  String get permMode => 'Режим дозволів';

  @override
  String get permModeAuto => 'Авто';

  @override
  String get permModeManual => 'Вручну';

  @override
  String get permModeBypass => 'Дозволити все';

  @override
  String get permModeBypassOff => 'Вимкнено на цьому сервері';

  @override
  String get permTitle => 'Дозволи команд';

  @override
  String get permDefaultMode => 'Типовий режим нових завдань';

  @override
  String get permManualNote =>
      'Нові завдання запитують про кожен крок, який не дозволено правилами.';

  @override
  String get permAutoNote =>
      'У нових завданнях кожен крок, не дозволений правилами, оцінює модель за правилами автоматичного режиму нижче: дозволене виконується, про заблоковане агенту повідомляється причина; без вердикту запитують вас.';

  @override
  String get permBypassNote =>
      'Усі кроки виконуються без запитань, зокрема видалення, перезапуск і зміна конфігурації. Правила заборони й запиту й далі діють.';

  @override
  String get permDisableBypass => 'Вимкнути «Дозволити все»';

  @override
  String get permDisableBypassSub =>
      'Завдання не можуть працювати в «Дозволити все»; запущене так завдання запитує, як у ручному режимі.';

  @override
  String get permDangerAsks =>
      'Окрім завдань із «Дозволити все», незворотна команда (видалення даних, розділи) вимагає ввести ім’я сервера.';

  @override
  String get permRules => 'Правила команд';

  @override
  String get permDeny => 'Заборонити';

  @override
  String get permAsk => 'Питати';

  @override
  String get permAllow => 'Дозволити';

  @override
  String get permRulesHint =>
      'По одному в рядку. * — будь-який текст, наприклад systemctl status * або apt-get install *; :* у кінці рівнозначне « *». Складена команда перевіряється частинами: заборона й запит діють, якщо збіглася будь-яка частина, дозвіл — лише якщо покрита кожна. Правила порівнюють написаний текст (/bin/rm не збігається з rm *) і не є межею безпеки.';

  @override
  String get permAutoRules => 'Правила автоматичного режиму';

  @override
  String get permAutoHint =>
      'Правила звичайною мовою, за якими судить модель. Порожньо — вбудований список; рядок \$defaults зберігає його й додає ваші. Порядок: жорстка заборона, потім м’яка (знімається правилом дозволу чи вашим явним проханням), потім дозвіл.';

  @override
  String get permEnvironment => 'Оточення';

  @override
  String get permSoftDeny => 'М’яка заборона';

  @override
  String get permHardDeny => 'Жорстка заборона';

  @override
  String get permBuiltIn => 'Вбудовані правила';

  @override
  String permShowDefaults(int n) {
    return 'Вбудовані правила ($n)';
  }

  @override
  String get discardUnsaved => 'Скасувати незбережені зміни?';
}
