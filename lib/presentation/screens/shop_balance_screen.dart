import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../data/models/shop_balance.dart';
import '../../providers/app_providers.dart';
import '../widgets/max_width_container.dart';

/// شاشة الرصيد المالي الإجمالي للمحل.
///
/// تعرض السيولة النقدية الحقيقية (الصندوق) وصافي مركز المحل
/// (النقد + المخزون + ديون العملاء − مستحقات الموردين).
class ShopBalanceScreen extends ConsumerWidget {
  const ShopBalanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balanceAsync = ref.watch(shopBalanceProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('رصيد المحل'),
        backgroundColor: AppColors.PRIMARY_BLUE,
        centerTitle: true,
      ),
      body: MaxWidthContainer(
        child: balanceAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('خطأ في تحميل الرصيد: $err')),
        data: (balance) => SingleChildScrollView(
          padding: const EdgeInsets.all(AppLayout.SPACING_UNIT * 3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'الرصيد المالي الإجمالي',
                style: TextStyle(
                  fontSize: AppTypography.HEADING_2,
                  fontWeight: FontWeight.bold,
                  color: AppColors.PRIMARY_BLUE_DARK,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'أرقام محاسبية حقيقية من الحركات المسجلة (مبيعات، تحصيلات، مدفوعات، مصروفات)',
                style: TextStyle(fontSize: 13, color: AppColors.TEXT_SECONDARY),
              ),
              const SizedBox(height: 24),

              // الرصيد النقدي الرئيسي
              _BalanceHeroCard(balance: balance),
              const SizedBox(height: 24),

              // تفاصيل التدفقات النقدية
              _SectionTitle(title: 'تفاصيل الصندوق'),
              const SizedBox(height: 12),
              _FlowCard(
                rows: [
                  _FlowRow(
                    label: 'نقد المبيعات المحصّل',
                    value: balance.cashFromSales,
                    direction: _FlowDirection.in_,
                    hint: 'ما دفعه العملاء فعلياً (بعد الباقي المُعاد)',
                  ),
                  _FlowRow(
                    label: 'تحصيلات الديون',
                    value: balance.collectionsIn,
                    direction: _FlowDirection.in_,
                    hint: 'دفعات سددها العملاء على الحساب',
                  ),
                  _FlowRow(
                    label: 'مدفوعات الموردين',
                    value: balance.supplierPaymentsOut,
                    direction: _FlowDirection.out,
                    hint: 'ما دُفع للموردين (نقداً عند الشراء أو لاحقاً)',
                  ),
                  _FlowRow(
                    label: 'المصروفات التشغيلية',
                    value: balance.expensesOut,
                    direction: _FlowDirection.out,
                    hint: 'إيجار، فواتير، رواتب، صيانة، شحن...',
                  ),
                ],
                total: balance.cashBalance,
                totalLabel: 'رصيد الصندوق',
              ),
              const SizedBox(height: 24),

              // صافي مركز المحل
              _SectionTitle(title: 'صافي مركز المحل'),
              const SizedBox(height: 12),
              _FlowCard(
                rows: [
                  _FlowRow(
                    label: 'رصيد الصندوق',
                    value: balance.cashBalance,
                    direction: _FlowDirection.in_,
                  ),
                  _FlowRow(
                    label: 'قيمة المخزون',
                    value: balance.inventoryValue,
                    direction: _FlowDirection.in_,
                    hint: 'الكميات الحالية × سعر الشراء',
                  ),
                  _FlowRow(
                    label: 'ديون العملاء (لك)',
                    value: balance.customerDebt,
                    direction: _FlowDirection.in_,
                  ),
                  _FlowRow(
                    label: 'مستحقات الموردين (عليك)',
                    value: balance.supplierOwed,
                    direction: _FlowDirection.out,
                  ),
                ],
                total: balance.netWorth,
                totalLabel: 'صافي مركز المحل',
              ),
              const SizedBox(height: 24),

              // ملاحظة
              Container(
                padding: const EdgeInsets.all(AppLayout.SPACING_UNIT * 2),
                decoration: BoxDecoration(
                  color: AppColors.NEUTRAL_SURFACE,
                  borderRadius: BorderRadius.circular(AppLayout.BORDER_RADIUS),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: AppColors.PRIMARY_BLUE,
                      size: 20,
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'ملاحظة: المرتجعات تُخصم من حساب العميل أو صافي المبيعات '
                        'ولا تُحتسب هنا كنقد خارجي إلا عند ردّ قيمتها نقداً للعميل. '
                        'البيع الآجل لا يُحتسب في الصندوق إلا عند تحصيله.',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.TEXT_SECONDARY,
                          height: 1.6,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}

class _BalanceHeroCard extends StatelessWidget {
  final ShopBalance balance;

  const _BalanceHeroCard({required this.balance});

  @override
  Widget build(BuildContext context) {
    final isPositive = balance.cashBalance >= 0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppLayout.SPACING_UNIT * 4),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isPositive
              ? [AppColors.PRIMARY_BLUE, AppColors.PRIMARY_BLUE_DARK]
              : [AppColors.DANGER_RED, const Color(0xFFB91C1C)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(AppLayout.BORDER_RADIUS * 1.5),
        boxShadow: [
          BoxShadow(
            color: (isPositive
                    ? AppColors.PRIMARY_BLUE
                    : AppColors.DANGER_RED)
                .withValues(alpha: 0.25),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.account_balance_wallet,
                color: Colors.white,
                size: 22,
              ),
              const SizedBox(width: 10),
              const Text(
                'رصيد الصندوق الحالي',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '${balance.cashBalance.toStringAsFixed(0)} ${AppStrings.CURRENCY}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 34,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'صافي مركز المحل: ${balance.netWorth.toStringAsFixed(0)} ${AppStrings.CURRENCY}',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;

  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: AppTypography.HEADING_3,
        fontWeight: FontWeight.bold,
        color: AppColors.PRIMARY_BLUE_DARK,
      ),
    );
  }
}

enum _FlowDirection { in_, out }

class _FlowRow extends StatelessWidget {
  final String label;
  final double value;
  final _FlowDirection direction;
  final String? hint;

  const _FlowRow({
    required this.label,
    required this.value,
    required this.direction,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    final isIn = direction == _FlowDirection.in_;
    final color = isIn ? AppColors.SUCCESS_GREEN : AppColors.DANGER_RED;
    final sign = isIn ? '+' : '−';

    return Tooltip(
      message: hint ?? '',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Icon(
              isIn ? Icons.south_west : Icons.north_east,
              color: color,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (hint != null)
                    Text(
                      hint!,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.TEXT_SECONDARY,
                      ),
                    ),
                ],
              ),
            ),
            Text(
              '$sign ${value.toStringAsFixed(0)}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FlowCard extends StatelessWidget {
  final List<_FlowRow> rows;
  final double total;
  final String totalLabel;

  const _FlowCard({
    required this.rows,
    required this.total,
    required this.totalLabel,
  });

  @override
  Widget build(BuildContext context) {
    final isPositive = total >= 0;
    return Container(
      padding: const EdgeInsets.all(AppLayout.SPACING_UNIT * 3),
      decoration: BoxDecoration(
        color: AppColors.NEUTRAL_SURFACE,
        borderRadius: BorderRadius.circular(AppLayout.BORDER_RADIUS),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        children: [
          ...rows,
          const Divider(height: 8, thickness: 1),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                totalLabel,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.PRIMARY_BLUE_DARK,
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: (isPositive
                          ? AppColors.SUCCESS_GREEN
                          : AppColors.DANGER_RED)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${total.toStringAsFixed(0)} ${AppStrings.CURRENCY}',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isPositive
                        ? AppColors.SUCCESS_GREEN
                        : AppColors.DANGER_RED,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
