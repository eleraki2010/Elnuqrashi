import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../providers/app_providers.dart';

/// شعار المحل: صورة مخصصة من الإعدادات إن وُجدت وإلا أيقونة افتراضية.
/// يُستخدم أعلى التطبيق (الشريط الجانبي/الداشبورد) وفي ترويسة الفاتورة.
class StoreLogo extends ConsumerWidget {
  final double size;
  final double borderRadius;

  const StoreLogo({
    super.key,
    this.size = 36,
    this.borderRadius = 8,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(shopProfileProvider);
    return profile.when(
      loading: () => _fallback(context),
      error: (_, _) => _fallback(context),
      data: (p) {
        final path = p.logoPath;
        if (path != null && path.isNotEmpty && File(path).existsSync()) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(borderRadius),
            child: Image.file(
              File(path),
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _fallback(context),
            ),
          );
        }
        return _fallback(context);
      },
    );
  }

  Widget _fallback(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Image.asset(
        'assets/images/logo.png',
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: AppColors.PRIMARY_BLUE,
            borderRadius: BorderRadius.circular(borderRadius),
          ),
          child: Icon(
            Icons.storefront,
            color: Colors.white,
            size: size * 0.6,
          ),
        ),
      ),
    );
  }
}
