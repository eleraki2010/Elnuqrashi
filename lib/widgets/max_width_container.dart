import 'package:flutter/material.dart';
import '../../../core/constants/app_constants.dart';

class MaxWidthContainer extends StatelessWidget {
  final Widget child;

  const MaxWidthContainer({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: AppLayout.MAX_CONTENT_WIDTH,
        ),
        child: child,
      ),
    );
  }
}