import 'package:flutter/material.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/responsive/responsive_scope.dart';
import '../../../data/models/product.dart';

class ProductCard extends StatelessWidget {
  final Product product;
  final VoidCallback onTap;

  const ProductCard({super.key, required this.product, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scale = ResponsiveScope.scaleOf(context);
    final contentWidth = ResponsiveScope.widthOf(context);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppLayout.BORDER_RADIUS),
      ),
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: product.imageUrl != null &&
                      product.imageUrl!.isNotEmpty
                  ? Image.network(
                      product.imageUrl!,
                      fit: BoxFit.cover,
                    )
                  : Container(
                      color: AppColors.NEUTRAL_BG,
                      child: Icon(
                        Icons.image_not_supported,
                        size: 40 * scale,
                        color: AppColors.TEXT_SECONDARY),
                    ),
            ),
            Padding(
              padding: EdgeInsets.all(
                  ResponsiveUtils.scaledSpacing(8.0, contentWidth)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    style: TextStyle(
                      fontSize:
                          ResponsiveUtils.scaledFont(14.0, contentWidth),
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(
                      height: ResponsiveUtils.scaledSpacing(4.0, contentWidth)),
                   Text(
                     AppStrings.money(product.salePrice),
                     style: TextStyle(
                       fontSize:
                           ResponsiveUtils.scaledFont(16.0, contentWidth),
                       fontWeight: FontWeight.bold,
                       color: AppColors.PRIMARY_BLUE),
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