import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../data/models/shop_balance.dart';
import '../../providers/app_providers.dart';
import '../widgets/max_width_container.dart';

/// شاشة الرصيد المالي الإجمالي للمحل المنضبطة بالقواعد والمعايير المحاسبية.
///
/// تعرض:
/// 1. السيولة النقدية الحقيقية (حركة الصندوق الفعلي).
/// 2. قائمة صافي مركز المحل (الأصول − الخصوم = حقوق الملكية).
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
          data: (balance) => RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(shopBalanceProvider);
            },
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
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
                    'بيانات محاسبية حقيقية مدققة ومستخرجة من الحركات الفعلية المسجلة',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.TEXT_SECONDARY,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // بطاقة رصيد الصندوق الرئيسية
                  _BalanceHeroCard(balance: balance),
                  const SizedBox(height: 24),

                  // تفاصيل التدفقات النقدية للصندوق
                  const _SectionTitle(title: 'تفاصيل حركة الصندوق (الخزينة)'),
                  const SizedBox(height: 6),
                  const Text(
                    'حركات النقد الفعلية (الداخل − الخارج) بالصندوق',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.TEXT_SECONDARY,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _FlowCard(
                    rows: [
                      _FlowRow(
                        label: 'نقد المبيعات المحصّل',
                        value: balance.cashFromSales,
                        direction: _FlowDirection.in_,
                        hint: 'ما دفعه العملاء فعلياً واستقر في الصندوق (بعد رد الباقي)',
                      ),
                      _FlowRow(
                        label: 'تحصيلات ديون العملاء',
                        value: balance.collectionsIn,
                        direction: _FlowDirection.in_,
                        hint: 'سندات قبض نقدية سددها العملاء على الحساب',
                      ),
                      if (balance.supplierRefundsIn > 0)
                        _FlowRow(
                          label: 'استرداد نقدي من الموردين',
                          value: balance.supplierRefundsIn,
                          direction: _FlowDirection.in_,
                          hint: 'مبالغ نقدية استردها المحل عند إرجاع بضاعة للموردين',
                        ),
                      _FlowRow(
                        label: 'مدفوعات الموردين',
                        value: balance.supplierPaymentsOut,
                        direction: _FlowDirection.out,
                        hint: 'ما دُفع للموردين نقداً (عند الشراء أو كسندات صرف لاحقة)',
                      ),
                      _FlowRow(
                        label: 'المصروفات التشغيلية',
                        value: balance.expensesOut,
                        direction: _FlowDirection.out,
                        hint: 'إيجار، فواتير كهرباء ومياه، رواتب، صيانة، شحن...',
                      ),
                      if (balance.returnsRefundOut > 0)
                        _FlowRow(
                          label: 'مرتجعات نقدية للعملاء',
                          value: balance.returnsRefundOut,
                          direction: _FlowDirection.out,
                          hint: 'مبالغ رُدّت نقداً من الخزينة للعملاء عند إرجاع منتجات',
                        ),
                    ],
                    total: balance.cashBalance,
                    totalLabel: 'رصيد الصندوق الفعلي',
                  ),
                  const SizedBox(height: 28),

                  // قائمة صافي مركز المحل
                  const _SectionTitle(title: 'صافي مركز المحل (الميزانية وقائمة المركز المالي)'),
                  const SizedBox(height: 6),
                  const Text(
                    'معادلة الميزانية القياسية: الأصول − الالتزامات = رأس المال وصافي المركز',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.TEXT_SECONDARY,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _FlowCard(
                    rows: [
                      _FlowRow(
                        label: 'رصيد الصندوق النقدي (أصل متداول)',
                        value: balance.cashBalance,
                        direction: _FlowDirection.in_,
                        hint: 'السيولة النقدية الجاهزة في الخزينة',
                      ),
                      _FlowRow(
                        label: 'قيمة المخزون الحالي (أصل متداول)',
                        value: balance.inventoryValue,
                        direction: _FlowDirection.in_,
                        hint: 'البضاعة المتوفرة حالياً مقيّمة بسعر التكلفة (سعر الشراء)',
                      ),
                      _FlowRow(
                        label: 'ديون العملاء (لك / ذمم مدينة)',
                        value: balance.customerDebt,
                        direction: _FlowDirection.in_,
                        hint: 'أموال للمحل لدى العملاء مستحقة التحصيل',
                      ),
                      if (balance.supplierAdvance > 0)
                        _FlowRow(
                          label: 'دفعات مقدمة للموردين (لك / أصل)',
                          value: balance.supplierAdvance,
                          direction: _FlowDirection.in_,
                          hint: 'مبالغ دفعها المحل للموردين تزيد عن قيمة البضاعة المستلمة',
                        ),
                      _FlowRow(
                        label: 'مستحقات الموردين (عليك / ذمم دائنة)',
                        value: balance.supplierOwed,
                        direction: _FlowDirection.out,
                        hint: 'التزامات وديون على المحل واجبة السداد للموردين',
                      ),
                      if (balance.customerCredit > 0)
                        _FlowRow(
                          label: 'أرصدة دائنة للعملاء (عليك / أمانات)',
                          value: balance.customerCredit,
                          direction: _FlowDirection.out,
                          hint: 'دفعات زائدة دفعها العملاء تمثل رصيداً دائناً لهم',
                        ),
                    ],
                    total: balance.netWorth,
                    totalLabel: 'صافي مركز المحل (حقوق الملكية)',
                  ),
                  const SizedBox(height: 24),

                  // بطاقة الضوابط والقواعد المحاسبية
                  Container(
                    padding: const EdgeInsets.all(AppLayout.SPACING_UNIT * 2.5),
                    decoration: BoxDecoration(
                      color: AppColors.NEUTRAL_SURFACE,
                      borderRadius:
                          BorderRadius.circular(AppLayout.BORDER_RADIUS),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(
                              Icons.verified_outlined,
                              color: AppColors.SUCCESS_GREEN,
                              size: 20,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'الانضباط بالقواعد والمعايير المحاسبية',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: AppColors.PRIMARY_BLUE_DARK,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _buildAccountingBullet(
                          'مبدأ التدفق النقدي الفعلي (Cash Flow):',
                          'الصندوق يعكس السيولة الفعلية المستلمة أو المصروفة فقط؛ المبيعات الآجلة لا تُسجل في الصندوق إلا عند تحصيلها فعلياً، وفائض الدفع يُعاد كباقي ولا يُضخّم الصندوق.',
                        ),
                        _buildAccountingBullet(
                          'تقييم المخزون بالتكلفة التاريخية:',
                          'يُحسب المخزون بـ (الكمية × سعر الشراء) لمنع تضخيم الأرباح قبل إتمام البيع، وهو المبدأ المعتمد في المعايير المحاسبية (GAAP & IFRS).',
                        ),
                        _buildAccountingBullet(
                          'معالجة المرتجعات:',
                          'مرتجع العميل يُخصم أولاً من حسابه الآجل (لتسوية الدين)، وما زاد يُردّ نقداً من الصندوق ويوثق كمرتجع نقدي.',
                        ),
                        _buildAccountingBullet(
                          'المعادلة المحاسبية لصافي المركز:',
                          'صافي مركز المحل = إجمالي الأصول (نقد + مخزون + ديون العملاء) − إجمالي الالتزامات (مستحقات الموردين).',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAccountingBullet(String title, String description) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '• ',
            style: TextStyle(
              color: AppColors.PRIMARY_BLUE,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.TEXT_PRIMARY,
                  height: 1.5,
                ),
                children: [
                  TextSpan(
                    text: '$title ',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  TextSpan(
                    text: description,
                    style: const TextStyle(color: AppColors.TEXT_SECONDARY),
                  ),
                ],
              ),
            ),
          ),
        ],
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
            color: (isPositive ? AppColors.PRIMARY_BLUE : AppColors.DANGER_RED)
                .withValues(alpha: 0.25),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.account_balance_wallet,
                color: Colors.white,
                size: 22,
              ),
              SizedBox(width: 10),
              Text(
                'رصيد الصندوق الحالي (الخزينة النقدية)',
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
            AppStrings.money(balance.cashBalance),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'صافي مركز المحل الشامل: ${AppStrings.money(balance.netWorth)}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
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
              '$sign ${AppStrings.money(value)}',
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
          const Divider(height: 16, thickness: 1),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                totalLabel,
                style: const TextStyle(
                  fontSize: 15,
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
                  AppStrings.money(total),
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
