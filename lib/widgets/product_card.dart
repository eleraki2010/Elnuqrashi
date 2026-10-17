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
                    iconSize: 26 * scale,
                  ),
                  // شارة انخفاض المخزون إن وجدت
                  if (product.isOutOfStock)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1.5,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.DANGER_RED,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'نفد المخزون',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 8.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    )
                  else if (product.isLowStock)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1.5,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.WARNING_AMBER,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'مخزون منخفض',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 8.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  // زر التعديل ✏️
                  Positioned(
                    top: 4,
                    left: 4,
                    child: Material(
                      color: Colors.black.withValues(alpha: 0.5),
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: onEdit ?? onTap,
                        child: const Padding(
                          padding: EdgeInsets.all(4.0),
                          child: Icon(
                            Icons.edit_outlined,
                            size: 13,
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
              padding: const EdgeInsets.symmetric(
                horizontal: 5.0,
                vertical: 3.0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    product.name,
                    style: TextStyle(
                      fontSize: ResponsiveUtils.scaledFont(10.0, contentWidth),
                      fontWeight: FontWeight.bold,
                      height: 1.15,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          AppStrings.money(product.salePrice),
                          style: TextStyle(
                            fontSize:
                                ResponsiveUtils.scaledFont(10.5, contentWidth),
                            fontWeight: FontWeight.bold,
                            color: AppColors.PRIMARY_BLUE,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${product.quantity} ${product.unit}',
                        style: TextStyle(
                          fontSize:
                              ResponsiveUtils.scaledFont(8.8, contentWidth),
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