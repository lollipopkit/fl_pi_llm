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
}
