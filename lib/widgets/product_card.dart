import 'package:flutter/material.dart';
import '../core/constants/app_constants.dart';
import '../core/responsive/responsive_scope.dart';
import '../data/models/product.dart';
import '../presentation/widgets/product_image_view.dart';

class ProductCard extends StatelessWidget {
  final Product product;
  final VoidCallback onTap;
  final VoidCallback? onEdit;

  const ProductCard({
    super.key,
    required this.product,
    required this.onTap,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final scale = ResponsiveScope.scaleOf(context);
    final contentWidth = ResponsiveScope.widthOf(context);

    return Card(
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppLayout.BORDER_RADIUS),
      ),
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // صورة المنتج مع زر التعديل المباشر
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ProductImageView(
                    imageUrl: product.imageUrl,
                    iconSize: 36 * scale,
                  ),
                  // شارة انخفاض المخزون إن وجدت
                  if (product.isOutOfStock)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.DANGER_RED,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'نفد المخزون',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    )
                  else if (product.isLowStock)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.WARNING_AMBER,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'مخزون منخفض',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  // زر التعديل ✏️
                  Positioned(
                    top: 6,
                    left: 6,
                    child: Material(
                      color: Colors.black.withValues(alpha: 0.5),
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: onEdit ?? onTap,
                        child: const Padding(
                          padding: EdgeInsets.all(6.0),
                          child: Icon(
                            Icons.edit_outlined,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // بيانات المنتج
            Padding(
              padding: EdgeInsets.all(
                ResponsiveUtils.scaledSpacing(8.0, contentWidth),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    style: TextStyle(
                      fontSize: ResponsiveUtils.scaledFont(13.0, contentWidth),
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(
                    height: ResponsiveUtils.scaledSpacing(4.0, contentWidth),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        AppStrings.money(product.salePrice),
                        style: TextStyle(
                          fontSize:
                              ResponsiveUtils.scaledFont(14.0, contentWidth),
                          fontWeight: FontWeight.bold,
                          color: AppColors.PRIMARY_BLUE,
                        ),
                      ),
                      Text(
                        '${product.quantity} ${product.unit}',
                        style: TextStyle(
                          fontSize:
                              ResponsiveUtils.scaledFont(11.0, contentWidth),
                          color: product.isOutOfStock
                              ? AppColors.DANGER_RED
                              : AppColors.TEXT_SECONDARY,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}