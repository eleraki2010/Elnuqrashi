import 'package:flutter/material.dart';

import '../constants/app_constants.dart';

/// يوفّر عرض المحتوى المتاح فعلياً للواجهة (باستثناء الشريط الجانبي أو
/// أي عناصر أخرى تشغل حيزاً أفقياً) لتُحسب على أساسه الأحجام المتجاوبة
/// بدقة، بدلاً من استخدام عرض الشاشة بالكامل.
///
/// يُوضع حول منطقة المحتوى في `MainLayoutScreen`، ويقرأ أي عنصر سليل
/// القيمة عبر [widthOf] فيتكيف حجم الخطوط والأيقونات والمسافات تلقائياً.
class ResponsiveScope extends InheritedWidget {
  /// عرض المحتوى الأفقي المتاح للواجهة بالـ dp.
  final double contentWidth;

  const ResponsiveScope({
    super.key,
    required this.contentWidth,
    required super.child,
  });

  /// عرض المحتوى المتاح للواجهة؛ يسقط على عرض الشاشة عند غياب النطاق
  /// (مثلاً في الاختبارات أو الشاشات المفتوحة في صفحات مستقلة).
  static double widthOf(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ResponsiveScope>();
    return scope?.contentWidth ?? MediaQuery.sizeOf(context).width;
  }

  /// عامل التكبير/التصغير المُحتسب من عرض المحتوى المتاح.
  static double scaleOf(BuildContext context) =>
      ResponsiveUtils.scaleForWidth(widthOf(context));

  @override
  bool updateShouldNotify(ResponsiveScope oldWidget) =>
      contentWidth != oldWidget.contentWidth;
}
