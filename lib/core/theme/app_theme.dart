import 'package:flutter/material.dart';

import '../constants/app_constants.dart';

class AppTheme {
  /// نصوص Material 3 المضغوطة (أصغر من الافتراضي بنحو 10–20%) لتناسب
  /// كثافة بيانات برنامج POS على الشاشة اللوحية — تُطبق على كل النصوص
  /// التي لا تحدد حجمها صراحة (عناوين القوائم، الأزرار، الحوارات...).
  /// الافتراضيات الكبيرة: titleMedium 16 / bodyLarge 16 / headline 32+.
  static TextTheme get _reducedTextTheme {
    final base = ThemeData.light().textTheme;
    return TextTheme(
      displayLarge: _s(base.displayLarge, 19, family: true),
      displayMedium: _s(base.displayMedium, 17, family: true),
      displaySmall: _s(base.displaySmall, 15, family: true),
      headlineLarge: _s(base.headlineLarge, 17, family: true),
      headlineMedium: _s(base.headlineMedium, 16, family: true),
      headlineSmall: _s(base.headlineSmall, 15, family: true),
      titleLarge: _s(base.titleLarge, 15.5, family: true),
      titleMedium: _s(base.titleMedium, 14, family: true),
      titleSmall: _s(base.titleSmall, 13, family: true),
      bodyLarge: _s(base.bodyLarge, 14, family: true),
      bodyMedium: _s(base.bodyMedium, 13, family: true),
      bodySmall: _s(base.bodySmall, 12, family: true),
      labelLarge: _s(base.labelLarge, 13, family: true),
      labelMedium: _s(base.labelMedium, 12, family: true),
      labelSmall: _s(base.labelSmall, 11, family: true),
    ).apply(
      fontFamily: AppTypography.FONT_FAMILY,
      bodyColor: AppColors.TEXT_PRIMARY,
      displayColor: AppColors.TEXT_PRIMARY,
    );
  }

  static TextStyle _s(TextStyle? style, double size, {bool family = false}) =>
      (style ?? const TextStyle()).copyWith(
        fontSize: size,
        fontFamily: family ? AppTypography.FONT_FAMILY : style?.fontFamily,
      );

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      fontFamily: AppTypography.FONT_FAMILY,
      // نظام نصوص Material بصيغة مضغوطة: خطوط M3 الافتراضية كبيرة على
      // التابلت (titleMedium 16sp في عنوانين القوائم مثلًا) — كل نص يعتمد
      // على سمة Material (ListTile، أزرار، Dialogs...) يصغر هنا مرة واحدة
      // بدل تكرار fontSize في كل شاشة.
      textTheme: _reducedTextTheme,
      primaryColor: AppColors.PRIMARY_BLUE,
      scaffoldBackgroundColor: AppColors.NEUTRAL_BG,
      colorScheme: const ColorScheme.light(
        primary: AppColors.PRIMARY_BLUE,
        onPrimary: AppColors.NEUTRAL_SURFACE,
        primaryContainer: AppColors.PRIMARY_BLUE_DARK,
        secondary: AppColors.SUCCESS_GREEN,
        onSecondary: AppColors.NEUTRAL_SURFACE,
        error: AppColors.DANGER_RED,
        surface: AppColors.NEUTRAL_SURFACE,
        onSurface: AppColors.TEXT_PRIMARY,
      ),
      // صفوف القوائم (ListTile) بكثافة مدمجة على كل الشاشات: ارتفاع أقل
      // وتباعد أضيق فتمسك شاشة التابلت صفوف أكثر — طلب صريح من المستخدم.
      listTileTheme: const ListTileThemeData(dense: true),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.PRIMARY_BLUE,
        foregroundColor: AppColors.NEUTRAL_SURFACE,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: AppTypography.FONT_FAMILY,
          fontSize: AppTypography.HEADING_2,
          fontWeight: FontWeight.bold,
          color: AppColors.NEUTRAL_SURFACE,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.NEUTRAL_SURFACE,
        elevation: 1,
        shadowColor: Colors.black.withValues(alpha: 0.04),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppLayout.BORDER_RADIUS),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.PRIMARY_BLUE,
          foregroundColor: AppColors.NEUTRAL_SURFACE,
          minimumSize: const Size(
            AppLayout.MIN_TOUCH_TARGET,
            AppLayout.MIN_TOUCH_TARGET,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppLayout.BORDER_RADIUS),
          ),
          textStyle: const TextStyle(
            fontFamily: AppTypography.FONT_FAMILY,
            fontSize: AppTypography.BASE_SIZE,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.PRIMARY_BLUE,
          side: const BorderSide(color: AppColors.PRIMARY_BLUE, width: 1.5),
          minimumSize: const Size(
            AppLayout.MIN_TOUCH_TARGET,
            AppLayout.MIN_TOUCH_TARGET,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppLayout.BORDER_RADIUS),
          ),
          textStyle: const TextStyle(
            fontFamily: AppTypography.FONT_FAMILY,
            fontSize: AppTypography.BASE_SIZE,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.NEUTRAL_SURFACE,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppLayout.BORDER_RADIUS),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppLayout.BORDER_RADIUS),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppLayout.BORDER_RADIUS),
          borderSide: const BorderSide(color: AppColors.PRIMARY_BLUE, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppLayout.BORDER_RADIUS),
          borderSide: const BorderSide(color: AppColors.DANGER_RED),
        ),
        hintStyle: const TextStyle(
          color: AppColors.TEXT_SECONDARY,
          fontSize: 14,
        ),
      ),
    );
  }
}
