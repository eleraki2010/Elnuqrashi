import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';

class StatCard extends StatelessWidget {
  final String title;
  final String value;
  final String? subtitle;
  final IconData icon;
  final Color iconColor;
  final Color? backgroundColor;
  final VoidCallback? onTap;

  const StatCard({
    super.key,
    required this.title,
    required this.value,
    this.subtitle,
    required this.icon,
    required this.iconColor,
    this.backgroundColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // أحجام متجاوبة تُحسب من عرض البطاقة نفسها (لا من عرض الشاشة)،
    // فيتناسب محتواها مع حجمها دائماً دون فيضان مهما كان عدد الأعمدة.
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = ResponsiveUtils.scaleForWidth(constraints.maxWidth);
        final padding = AppLayout.SPACING_UNIT * 2 * scale;
        final iconBox = 8 * scale;
        final iconSize = 22 * scale;

        return InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppLayout.BORDER_RADIUS),
          child: Container(
            padding: EdgeInsets.all(padding),
            decoration: BoxDecoration(
              color: backgroundColor ?? AppColors.NEUTRAL_SURFACE,
              borderRadius: BorderRadius.circular(AppLayout.BORDER_RADIUS),
              border: Border.all(color: const Color(0xFFE5E7EB)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: 14 * scale,
                          color: AppColors.TEXT_SECONDARY,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 2,
                      ),
                    ),
                    Container(
                      padding: EdgeInsets.all(iconBox),
                      decoration: BoxDecoration(
                        color: iconColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8 * scale),
                      ),
                      child: Icon(icon, color: iconColor, size: iconSize),
                    ),
                  ],
                ),
                SizedBox(height: 12 * scale),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    value,
                    style: TextStyle(
                      fontSize: AppTypography.HEADING_1 * scale,
                      fontWeight: FontWeight.bold,
                      color: AppColors.TEXT_PRIMARY,
                    ),
                    maxLines: 1,
                  ),
                ),
                if (subtitle != null) ...[
                  SizedBox(height: 4 * scale),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 12 * scale,
                      color: AppColors.TEXT_SECONDARY,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
