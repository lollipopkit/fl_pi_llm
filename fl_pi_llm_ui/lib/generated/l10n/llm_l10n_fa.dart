// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'llm_l10n.dart';

// ignore_for_file: type=lint

/// The translations for Persian (`fa`).
class LlmLocalizationsFa extends LlmLocalizations {
  LlmLocalizationsFa([String locale = 'fa']) : super(locale);

  @override
  String get addServer => 'افزودن سرور';

  @override
  String get allow => 'مجاز کردن';

  @override
  String get allowAlways => 'همیشه مجاز کردن';

  @override
  String get allowedWithoutAsking => 'مجاز بدون پرسش';

  @override
  String allowToolFmt(String tool) {
    return '$tool مجاز شود؟';
  }

  @override
  String get allProviders => 'همه ارائه‌دهندگان';

  @override
  String alreadyExists(String path) {
    return '$path از قبل وجود دارد';
  }

  @override
  String get attachment => 'پیوست';

  @override
  String attachUnsupported(String name) {
    return 'پیوست کردن $name ممکن نیست: فقط تصاویر و فایل‌های متنی تا 512 KB';
  }

  @override
  String get back => 'بازگشت';

  @override
  String get builtIn => 'توکار';

  @override
  String get camera => 'دوربین';

  @override
  String charsFmt(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n نویسه',
      one: '1 نویسه',
    );
    return '$_temp0';
  }

  @override
  String get chatRead => 'خواندن گفتگو';

  @override
  String get chatSearch => 'جستجوی گفتگوها';

  @override
  String get compacted => 'پیام‌های قبلی خلاصه شدند';

  @override
  String get compaction => 'فشرده‌سازی گفتگوهای طولانی';

  @override
  String get compactionTip =>
      'وقتی گفتگو دیگر در context مدل جا نشود، پیام‌های قبلی برای مدل خلاصه می‌شوند. شما همچنان همه آن‌ها را می‌بینید.';

  @override
  String connectedFmt(int n) {
    return 'متصل · $n ابزار';
  }

  @override
  String get copied => 'کپی شد';

  @override
  String get customProvider => 'ارائه‌دهنده سفارشی';

  @override
  String get defaultModel => 'مدل پیش‌فرض';

  @override
  String get deleteKey => 'حذف کلید';

  @override
  String get deny => 'رد کردن';

  @override
  String get discard => 'صرف‌نظر کردن';

  @override
  String get disconnected => 'قطع‌شده';

  @override
  String get endpoint => 'نقطه پایانی';

  @override
  String get extraVars => 'متغیرهای اضافی';

  @override
  String get extraVarsTip =>
      'در هر خط KEY=VALUE، برای ارائه‌دهندگانی که به چیزی بیش از یک کلید نیاز دارند (منبع Azure، حساب Cloudflare).';

  @override
  String get favorite => 'علاقه‌مندی‌ها';

  @override
  String get history => 'تاریخچه';

  @override
  String get historyToolTip => 'جستجو و خواندن سایر گفتگوهای شما، بدون پرسش';

  @override
  String get httpToolTip => 'دریافت صفحات وب و API‌ها';

  @override
  String get image => 'تصویر';

  @override
  String invalidLinkFmt(Object uri) {
    return 'پیوند نامعتبر: $uri';
  }

  @override
  String get key => 'کلید';

  @override
  String get keyInKeychain =>
      'در Keychain سیستم ذخیره می‌شود و هرگز در نسخه‌های پشتیبان قرار نمی‌گیرد.';

  @override
  String get mcpServers => 'سرورهای MCP';

  @override
  String get memory => 'حافظه';

  @override
  String get memoryDelete => 'حذف حافظه';

  @override
  String get memoryEdit => 'ویرایش حافظه';

  @override
  String get memoryMove => 'جابه‌جایی حافظه';

  @override
  String get memorySearch => 'جستجوی حافظه';

  @override
  String get memoryToolTip =>
      'فایل‌هایی که مدل بین گفتگوها نگه می‌دارد و بدون پرسش خوانده و نوشته می‌شوند';

  @override
  String get memoryView => 'خواندن حافظه';

  @override
  String get memoryWrite => 'ذخیره حافظه';

  @override
  String get message => 'پیام';

  @override
  String minutesSecondsFmt(int m, int s) {
    return '$m دقیقه $s ثانیه';
  }

  @override
  String get model => 'مدل';

  @override
  String modelsCountFmt(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n مدل',
      one: '1 مدل',
    );
    return '$_temp0';
  }

  @override
  String get modelsListedTip =>
      'اختیاری: فهرست /models نقطه پایانی دریافت می‌شود. شناسه‌هایی را که در آن فهرست نیستند اضافه کنید.';

  @override
  String get modelsRequired =>
      'این API نمی‌تواند مدل‌های خود را فهرست کند: دست‌کم یک شناسه مدل وارد کنید.';

  @override
  String moreFmt(int n) {
    return '$n مورد دیگر';
  }

  @override
  String get noProviderKey =>
      'هنوز هیچ ارائه‌دهنده‌ای کلید ندارد. برای شروع گفتگو یکی اضافه کنید.';

  @override
  String get refreshModels => 'تازه‌سازی مدل‌ها';

  @override
  String get regenerate => 'تولید دوباره';

  @override
  String get replyInterrupted => 'پاسخ قطع شد';

  @override
  String get replyWaits => 'پاسخ منتظر جواب شماست.';

  @override
  String get resumeReply => 'ادامه';

  @override
  String get sameAsChat => 'همانند گفتگو';

  @override
  String get searchModels => 'جستجوی مدل‌ها';

  @override
  String get searchProviders => 'جستجوی ارائه‌دهندگان';

  @override
  String secondsFmt(String n) {
    return '$n ثانیه';
  }

  @override
  String get send => 'ارسال';

  @override
  String get systemPrompt => 'پرامپت سیستمی';

  @override
  String get thought => 'تفکر';

  @override
  String thoughtForFmt(String time) {
    return 'تفکر به مدت $time';
  }

  @override
  String get titleModel => 'مدل برای عنوان‌ها';

  @override
  String tokensFmt(String n) {
    return '$n توکن';
  }

  @override
  String get tool => 'ابزار';

  @override
  String get toolHttpReqName => 'درخواست HTTP';

  @override
  String get unsavedChanges => 'پیش از خروج، تغییرات ذخیره شوند؟';

  @override
  String get untitled => 'بدون عنوان';

  @override
  String usableModelsFmt(int n, int m) {
    String _temp0 = intl.Intl.pluralLogic(
      m,
      locale: localeName,
      other: '$m ارائه‌دهنده',
      one: '1 ارائه‌دهنده',
    );
    return '$n قابل استفاده · $_temp0';
  }

  @override
  String get useTools => 'استفاده از ابزارها';

  @override
  String get useToolsTip =>
      'هر فراخوانی ابتدا اجازه می‌گیرد، مگر اینکه در زیر مجاز شده باشد';

  @override
  String get allowInsecure => 'مجاز کردن HTTP ساده';

  @override
  String get allowInsecureTip =>
      'این نشانی http:// و خارج از این دستگاه است: کلید API بدون رمزگذاری ارسال می‌شود و هر کسی در مسیر شبکه می‌تواند آن را بخواند. فقط در شبکه‌ای که به آن اعتماد دارید آن را مجاز کنید.';

  @override
  String get configure => 'پیکربندی';

  @override
  String get supportsThinking => 'تفکر';

  @override
  String get thinkingEffort => 'میزان تفکر';

  @override
  String get mcpHeaders => 'هدرها';

  @override
  String get mcpHeadersTip =>
      'اختیاری، مانند Authorization با Bearer <token>. فقط در این دستگاه نگه داشته می‌شود، هرگز در پشتیبان‌گیری قرار نمی‌گیرد و فقط به این سرور ارسال می‌شود.';

  @override
  String get mcpHeadersInvalid =>
      'هر هدر به یک نام شامل حروف، ارقام و خط تیره، و یک مقدار نیاز دارد.';

  @override
  String get mcpNeedsSignIn => 'ورود الزامی است';

  @override
  String get mcpSigningIn => 'ورود را در مرورگر کامل کنید';

  @override
  String get mcpSignedIn => 'وارد شدید. می‌توانید این صفحه را ببندید.';

  @override
  String get mcpSignedInShort => 'وارد شده';

  @override
  String get mcpSignInFailed =>
      'ورود ناموفق بود. می‌توانید این صفحه را ببندید و دوباره تلاش کنید.';

  @override
  String get mcpInsecure =>
      'فقط به نشانی https می‌توان هدر ارسال کرد یا وارد شد.';

  @override
  String get mcpAddHeader => 'افزودن هدر';

  @override
  String get mcpNotSignedIn => 'وارد نشده';

  @override
  String get mcpSignInTip =>
      'برای سروری که از OAuth استفاده می‌کند. در مرورگر وارد می‌شوید و توکن به‌طور خودکار تمدید می‌شود.';

  @override
  String get mcpConnecting => 'در حال اتصال…';

  @override
  String get skills => 'مهارت‌ها';

  @override
  String get skillsTip =>
      'دستورالعمل‌هایی برای وظایف خاص که مدل هنگام تطابق یک وظیفه با یکی از آن‌ها می‌خواند. فقط از منابعی که به آن‌ها اعتماد دارید نصب کنید: مدل از آنچه مهارت می‌گوید پیروی می‌کند.';

  @override
  String get skillSourceInvalid => 'مخزن، پیوند یا دستور `npx skills add` نیست';

  @override
  String get skillsNotFound => 'هیچ مهارتی در آنجا یافت نشد';

  @override
  String get skillsPick => 'مهارت‌ها برای نصب';

  @override
  String skillsInstalledFmt(int n) {
    return '$n مورد نصب شد';
  }

  @override
  String get skillsUpToDate => 'به‌روز است';

  @override
  String skillsUpdatedFmt(int n) {
    return '$n مورد به‌روزرسانی شد';
  }

  @override
  String get skillsFromFolder => 'نصب از پوشه';

  @override
  String get skillsFromZip => 'نصب از فایل .zip';

  @override
  String skillsUpdateFailedFmt(int n) {
    return 'بررسی $n منبع ممکن نبود';
  }

  @override
  String get skillBuiltin => 'توکار';

  @override
  String keyFromEnvFmt(String name) {
    return 'کلید از $name';
  }

  @override
  String keyFromEnvTipFmt(String name) {
    return 'کلیدی که اکنون استفاده می‌شود متغیر محیطی $name است. کلیدی که اینجا وارد شود جایگزین آن می‌شود.';
  }

  @override
  String get skillUpdateAvailable => 'به‌روزرسانی موجود است';

  @override
  String skillsUpdateAllFmt(int n) {
    return 'به‌روزرسانی همه ($n)';
  }

  @override
  String get askUser => 'پرسش از شما';

  @override
  String get fieldRequired => 'الزامی';

  @override
  String get fieldInvalid => 'نامعتبر';

  @override
  String get waitingForYou => 'منتظر شما';

  @override
  String get otherAnswer => 'سایر';

  @override
  String get otherAnswerHint => 'پاسخ خودتان';

  @override
  String get commandRiskReadOnly => 'فقط‌خواندنی';

  @override
  String get commandRiskUnknown => 'طبقه‌بندی‌نشده';

  @override
  String get commandRiskCaution => 'ایجاد تغییرات در سیستم';

  @override
  String get commandRiskDestructive => 'خطر بالا';
}
