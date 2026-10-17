import 'package:flutter/material.dart';

class AppColors {
  // SPECKIT Design Tokens - Never change these values
  static const Color PRIMARY_BLUE = Color(0xFF1E5FBF);
  static const Color PRIMARY_BLUE_DARK = Color(0xFF123E80);
  static const Color SUCCESS_GREEN = Color(0xFF1FAA59);
  static const Color DANGER_RED = Color(0xFFE23B3B);
  static const Color NEUTRAL_BG = Color(0xFFF5F7FA);
  static const Color NEUTRAL_SURFACE = Color(0xFFFFFFFF);
  static const Color TEXT_PRIMARY = Color(0xFF1A1A1A);
  static const Color TEXT_SECONDARY = Color(0xFF6B7280);
  static const Color WARNING_AMBER = Color(0xFFF5A623);
}

class AppTypography {
  static const String FONT_FAMILY = 'Cairo';

  /// القيم بعد سلسلة تخفيضات متتالية (كان BASE 15 / H1 20 وما زالت
  /// «كبيرة جداً» على التابلت). القاعدة: أحجام مضبوطة على الهاتف
  /// (390dp) ثابتة على التابلت/الديسكتوب — العرض الواسع يُستغل في
  /// أعمدة أكثر لا في خط أكبر.
  static const double BASE_SIZE = 14.0;
  static const double HEADING_1 = 17.0;
  static const double HEADING_2 = 15.0;
  static const double HEADING_3 = 13.5;
  static const double HEADING_4 = 12.0;
}

class AppLayout {
  static const TextDirection DIRECTION = TextDirection.rtl;
  static const double MIN_TOUCH_TARGET = 48.0;
  static const double BORDER_RADIUS = 12.0;
  static const double SPACING_UNIT = 8.0;

  /// نقاط التوقف (Breakpoints) — Material Design 3 window size classes.
  /// compact: هاتف عمودي (< 600dp)
  /// medium: هاتف أفقي / تابلت صغير (600–840dp)
  /// expanded: تابلت كبير / ديسكتوب (≥ 840dp)
  static const double BREAKPOINT_COMPACT = 600.0;
  static const double BREAKPOINT_MEDIUM = 840.0;

  /// أقصى عرض لمحتوى الشاشات الطويلة (نماذج، قوائم) قبل تثبيته في المنتصف
  /// لمنع تمدّد النصوص والجداول بشكل مفرط على الشاشات العريضة.
  /// (1100dp: يستغل التابلت عرض الشاشة — كان 840 فيصغر المحتوى على التابلت.)
  static const double MAX_CONTENT_WIDTH = 1100.0;

  /// عرض الشريط الجانبي موسّعاً / مطوياً (مكبّر قليلاً لأيقونات أوضح على التابلت).
  static const double SIDEBAR_EXPANDED_WIDTH = 236.0;
  static const double SIDEBAR_COLLAPSED_WIDTH = 72.0;
}

/// مساعدات استجابة الشاشات — تحديد فئة الجهاز من العرض المتاح.
class ResponsiveUtils {
  /// خط الأساس لتصميم الواجهة: عرض هاتف نموذجي بالـ dp.
  static const double designBaselineWidth = 390.0;

  /// الحد الأدنى لعامل التكبير (هواتف صغيرة تحت خط الأساس).
  static const double minScale = 0.85;

  /// سقف نطاق الهاتف: من خط الأساس (390dp) فما فوق لا نتجاوز 1.0 —
  /// مقاسات الهاتف كما صُمِّمت بلا أي تكبير.
  static const double phoneMaxScale = 1.0;

  /// نطاق التابلت (موجود للتوثيق): هذا التطبيق يعمل أساساً على الجهاز
  /// اللوحي أندرويد، وعامل التكبير فيه ثابت عند 1.0 تماماً (لا نمو)
  /// — العرض الأوسع يُستغل في أعمدة أكثر لا في خطوط أكبر.
  static const double tabletBandStart = 600.0;
  static const double tabletBandEnd = 1000.0;

  /// السقف الكلي: تابلت واسع أفقي / ديسكتوب — مع تحسين بسيط للمسات والكفاءة البصرية
  /// على الشاشات الكبيرة جداً (فوق 1200dp) لتحسين تجربة الاستخدام دون التضحية بكثافة المعلومات
  /// على الشاشات اللوحية القياسية.
  static const double maxScale = 1.0;
  static const double largeScreenStart = 1200.0;
  static const double largeScreenScale = 1.05; // تحسن طفيف جداً للشاشات الكبيرة

  /// معدل نمو عامل التكبير لكل dp بعد خط الأساس (معتل على الصفر:
  /// لا تكبير بعد الهاتف).
  static const double scaleGrowthRate = 0.0;

  static bool isCompact(double width) => width < AppLayout.BREAKPOINT_COMPACT;
  static bool isMedium(double width) =>
      width >= AppLayout.BREAKPOINT_COMPACT &&
      width < AppLayout.BREAKPOINT_MEDIUM;
  static bool isExpanded(double width) => width >= AppLayout.BREAKPOINT_MEDIUM;

  /// عامل تكبير/تصغير سلس لعناصر الواجهة (خطوط، أيقونات، مسافات) بناءً
  /// على العرض المتاح فعلياً:
  ///  - تحت 390dp: تصغير تدريجي (هواتف صغيرة) حتى الحد الأدنى 0.85.
  ///  - 390dp فأعلى (هاتف عادي / تابلت / ديسكتوب): ثابت عند 1.0 تماماً.
  ///    التطبيق يعمل على اللوحي أندرويد، والخطوط المكبَّرة على التابلت
  ///    كانت «كبيرة جداً» وتطغى على البيانات في كل الصفحات — العرض
  ///    الأوسع يُستغل في أعمدة/بطاقات أكثر (statGridColumns،
  ///    posGridColumns) لا في تكبير الخط.
  ///  - الشاشات الكبيرة جداً (>1200dp): تحسين بسيط جداً للمسات والوضوح
  ///    دون التأثير على كثافة المعلومات على الشاشات اللوحية القياسية.
  static double scaleForWidth(double width) {
    if (width <= designBaselineWidth) {
      return (width / designBaselineWidth).clamp(minScale, 1.0);
    }
    if (width >= largeScreenStart) {
      // تحسين بسيط جداً للشاشات الكبيرة جداً لتحسين تجربة اللمس
      // دون التأثير على الشاشات اللوحية القياسية (600-1200dp)
      return (1.0 + ((width - largeScreenStart) / 2000) * (largeScreenScale - 1.0)).clamp(1.0, maxScale);
    }
    return 1.0;
  }

  /// حجم خط متجاوب: يضرب القاعدة في عامل التكبير.
  static double scaledFont(double base, double width) =>
      base * scaleForWidth(width);

  /// حجم أيقونة متجاوب.
  static double scaledIcon(double base, double width) =>
      base * scaleForWidth(width);

  /// مسافة (padding/spacing) متجاوبة مع تحسين طفيف للشاشات الأكبر
  /// لتحسين hiérarchie البصرية والمسافات البينية.
  static double scaledSpacing(double base, double width) {
    // تطبيق نفس مقياس التكبير على المسافات مع تحسين طفيف للشاشات الكبيرة
    double scale = scaleForWidth(width);
    // إضافة تحسين طفيف للمسافات على الشاشات الكبيرة لتحسين القراءة
    if (width >= largeScreenStart) {
      scale = scale * (1.0 + ((width - largeScreenStart) / 3000) * 0.1); // עד 10% improvement
    }
    return base * scale;
  }

  /// نقطة التعداد لاستخدام الشريط الجانبي بدلاً من شريط التنقل السفلي.
  static bool showSidebar(double width) => width >= 600.0;

  /// عدد أعمدة شبكة البطاقات الإحصائية حسب عرض المحتوى المتاح:
  /// - شاشات عريضة (ديسكتوب / تابلت أفقي >= 950dp): 4 أعمدة.
  /// - أجهزة لوحية في الوضع الرأسي (480–949dp): عمودان (2 أعمدة)،
  ///   ليتسع كرت الإحصائية للعنوان والقيمة والتفاصيل كاملة دون قص أو تداخل.
  /// - هواتف ضيقة (< 480dp): عمود واحد.
  static int statGridColumns(double width) {
    if (width >= 950) return 4;
    if (width >= 480) return 2;
    return 1;
  }

  /// عدد أعمدة شبكة منتجات نقطة البيع حسب العرض المتاح للجزء.
  /// مبنية على عرض بلاطة (~95–130dp) لتكون الخلايا مدمجة وتظهر أصناف
  /// أكثر على شاشة التابلت الواحدة — لا بلاطات واسعة قليلة الأعداد.
  /// تم تحسين نقاط التوقف لتوزيع أفضل على الأجهزة اللوحية الشائعة.
  static int posGridColumns(double width) {
    if (width >= 1300) return 7;   // شاشات كبيرة جداً
    if (width >= 1100) return 6;   // شاشات كبيرة
    if (width >= 900) return 5;    // تابلت عريض
    if (width >= 700) return 4;    // تابلت قياسي
    if (width >= 500) return 3;    // تابلت صغير أو هاتف أفقي
    if (width >= 320) return 2;    // هاتف ضيق
    return 1;
  }
}

class AppStrings {
  /// 1. العلامة التجارية للنظام (Software Brand)
  static const String APP_NAME = 'دُكّان POS';
  static const String APP_TITLE = 'دُكّان - نظام إدارة المحلات والمبيعات';
  static const String APP_SLOGAN = 'النظام الشامل لإدارة نقاط البيع والمخزون والمحاسبة';
  static const String APP_VERSION = '1.0.0 Pro';

  /// 2. هوية المطور والجهة المصممة (Developer & Vendor Identity)
  static const String DEVELOPER_NAME = 'م/ محمد العراقي';
  static const String DEVELOPER_TITLE = 'مهندس ومطور برمجيات';
  static const String DEVELOPER_PHONE = '+201032231330';
  static const String DEVELOPER_WHATSAPP = '201032231330';
  static const String DEVELOPER_RIGHTS = 'جميع الحقوق البرمجية محفوظة © 2026';

  /// 3. بيانات المتجر الافتراضية (Default Store Profile)
  static const String DEFAULT_STORE_NAME = 'متجري / اسم المحل';
  static const String DEFAULT_STORE_ACTIVITY = 'تجارة عامة ومبيعات';
  static const String STORE_NAME = DEFAULT_STORE_NAME;

  static const String CURRENCY = 'ج.م';
  static const String CURRENCY_CODE = 'EGP';

  /// معدل الضريبة الافتراضي (القيمة المضافة) — يمكن جعله قابلاً للتعديل من الإعدادات لاحقاً.
  static const double TAX_RATE = 0.14; // 14%

  /// مبلغ منسق مع قرشين (أصغر وحدة للعملة).
  /// `money(154.5)` → «154.50 ج.م».
  static String money(double value) => '${value.toStringAsFixed(2)} $CURRENCY';

  static const String BTN_NEW_SALE = 'بيع جديد';
  static const String BTN_ADD_PRODUCT = 'إضافة منتج';
  static const String LABEL_TOTAL = 'الإجمالي';
  static const String LABEL_PAID = 'المدفوع';
  static const String LABEL_CHANGE = 'الباقي';
  static const String LABEL_REMAINING_ON_CUSTOMER = 'المتبقي على العميل';
  static const String ALERT_LOW_STOCK = 'المنتج على وشك النفاد';
  static const String ALERT_OUT_OF_STOCK = 'المنتج غير متوفر';
  static const String CONFIRM_DELETE =
      'هل أنت متأكد من الحذف؟ لا يمكن التراجع.';
  static const String TOAST_SALE_SUCCESS = 'تم إتمام عملية البيع بنجاح';
}