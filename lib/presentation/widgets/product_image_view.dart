import 'dart:io';
import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';

/// ويدجت موحدة لعرض صور المنتجات تدعم:
/// 1. مسارات الملفات المحلية المحفوظة على الجهاز (File path).
/// 2. الروابط الخارجية (Network URLs).
/// 3. إظهار أيقونة احتياطية أنيقة في حال عدم وجود صورة أو فشل التحميل.
class ProductImageView extends StatelessWidget {
  final String? imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final double iconSize;
  final BorderRadius? borderRadius;

  const ProductImageView({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.iconSize = 32,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    Widget content;
    final path = imageUrl?.trim();

    if (path == null || path.isEmpty) {
      content = _buildPlaceholder();
    } else if (path.startsWith('http://') || path.startsWith('https://')) {
      content = Image.network(
        path,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (context, error, stackTrace) => _buildPlaceholder(),
      );
    } else {
      final file = File(path);
      content = Image.file(
        file,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (context, error, stackTrace) => _buildPlaceholder(),
      );
    }

    if (borderRadius != null) {
      return ClipRRect(
        borderRadius: borderRadius!,
        child: content,
      );
    }

    return content;
  }

  Widget _buildPlaceholder() {
    return Container(
      width: width,
      height: height,
      color: const Color(0xFFF1F5F9),
      child: Center(
        child: Icon(
          Icons.inventory_2_outlined,
          size: iconSize,
          color: AppColors.TEXT_SECONDARY.withValues(alpha: 0.6),
        ),
      ),
    );
  }
}
