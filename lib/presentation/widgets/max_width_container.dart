import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';

/// يُحيط محتوى الشاشة بحد أقصى للعرض ويوسّطه، لمنع تمدّد النماذج والقوائم
/// بشكل مفرط على شاشات التابات والديسكتوب العريضة، مع الحفاظ على عرض
/// كامل على الهاتف.
class MaxWidthContainer extends StatelessWidget {
  final Widget child;
  final double maxWidth;

  const MaxWidthContainer({
    super.key,
    required this.child,
    this.maxWidth = AppLayout.MAX_CONTENT_WIDTH,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
