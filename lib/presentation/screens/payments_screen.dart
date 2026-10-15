import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/app_constants.dart';
import '../../core/responsive/responsive_scope.dart';
import '../../data/models/customer.dart';
import '../../data/models/supplier.dart';
import '../../providers/app_providers.dart';
import '../../providers/auth_provider.dart';
import '../../providers/data_refresh_service.dart';
import '../../providers/phase2_providers.dart';
import '../widgets/max_width_container.dart';

/// شاشة المدفوعات: تحصيلات العملاء (داخل) ومدفوعات الموردين (خارج)
/// مع ملخص يومي وإمكانية تسجيل دفعة جديدة مباشرة.
class PaymentsScreen extends ConsumerStatefulWidget {
  const PaymentsScreen({super.key});

  @override
  ConsumerState<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends ConsumerState<PaymentsScreen> {
  _PaymentFilter _filter = _PaymentFilter.all;

  @override
  Widget build(BuildContext context) {
    final paymentsAsync = ref.watch(paymentsProvider);
    final dateFormat = DateFormat('yyyy/MM/dd - hh:mm a');
    // عامل تكبير حسب عرض المحتوى: يكبّر السجلات على التابلت بوضوح.
    final scale = ResponsiveScope.scaleOf(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('المدفوعات والتحصيلات'),
        backgroundColor: AppColors.PRIMARY_BLUE,
        centerTitle: true,
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.PRIMARY_BLUE,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('تسجيل دفعة'),
        onPressed: () => _showAddPaymentDialog(),
      ),
      body: Padding(
        padding: const EdgeInsets.all(AppLayout.SPACING_UNIT * 3),
        child: MaxWidthContainer(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'سجل المدفوعات النقدية',
                  style: TextStyle(
                    fontSize: AppTypography.HEADING_2 * scale,
                    fontWeight: FontWeight.bold,
                    color: AppColors.PRIMARY_BLUE_DARK,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'تحصيلات ديون العملاء ومدفوعات الموردين — كل عملية مسجلة ومؤثرة على الأرصدة',
                  style: TextStyle(
                    fontSize: 13 * scale,
                    color: AppColors.TEXT_SECONDARY,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Daily summary cards
            FutureBuilder<_PaymentsSummary>(
              future: _loadSummary(),
              builder: (context, snapshot) {
                final summary = snapshot.data;
                return Row(
                  children: [
                    Expanded(
                      child: _SummaryCard(
                        title: 'تحصيلات العملاء اليوم',
                        amount: summary?.collections ?? 0.0,
                        icon: Icons.south_west,
                        color: AppColors.SUCCESS_GREEN,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _SummaryCard(
                        title: 'مدفوعات الموردين اليوم',
                        amount: summary?.supplierPayments ?? 0.0,
                        icon: Icons.north_east,
                        color: AppColors.WARNING_AMBER,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _SummaryCard(
                        title: 'صافي الحركة النقدية',
                        amount: (summary?.collections ?? 0.0) -
                            (summary?.supplierPayments ?? 0.0),
                        icon: Icons.account_balance,
                        color: AppColors.PRIMARY_BLUE,
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 20),

            // Filter chips
            Wrap(
              spacing: 8,
              children: [
                _buildFilterChip('الكل', _PaymentFilter.all),
                _buildFilterChip('تحصيلات العملاء', _PaymentFilter.incoming),
                _buildFilterChip('مدفوعات الموردين', _PaymentFilter.outgoing),
              ],
            ),
            const SizedBox(height: 16),

            // Payments list
            Expanded(
              child: paymentsAsync.when(
                data: (payments) {
                  final filtered = payments.where((p) {
                    switch (_filter) {
                      case _PaymentFilter.incoming:
                        return p.payment.direction == 'in';
                      case _PaymentFilter.outgoing:
                        return p.payment.direction == 'out';
                      case _PaymentFilter.all:
                        return true;
                    }
                  }).toList();

                  if (filtered.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.receipt_outlined,
                            size: 64,
                            color: AppColors.TEXT_SECONDARY.withValues(
                              alpha: 0.4,
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'لا توجد مدفوعات مسجلة',
                            style: TextStyle(
                              fontSize: AppTypography.HEADING_3,
                              color: AppColors.TEXT_SECONDARY,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'اضغط "تسجيل دفعة" لتسجيل تحصيل من عميل أو سداد لمورد',
                            style: TextStyle(color: AppColors.TEXT_SECONDARY),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    );
                  }

                  return Container(
                    decoration: BoxDecoration(
                      color: AppColors.NEUTRAL_SURFACE,
                      borderRadius: BorderRadius.circular(
                        AppLayout.BORDER_RADIUS,
                      ),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(
                        AppLayout.BORDER_RADIUS,
                      ),
                      child: ListView.separated(
                        itemCount: filtered.length,
                        separatorBuilder: (_, _) =>
                            const Divider(height: 1, thickness: 0.8),
                        itemBuilder: (context, index) {
                          final entry = filtered[index];
                          final isIn = entry.payment.direction == 'in';
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            leading: CircleAvatar(
                              backgroundColor: (isIn
                                      ? AppColors.SUCCESS_GREEN
                                      : AppColors.WARNING_AMBER)
                                  .withValues(alpha: 0.12),
                              child: Icon(
                                isIn ? Icons.south_west : Icons.north_east,
                                color: isIn
                                    ? AppColors.SUCCESS_GREEN
                                    : AppColors.WARNING_AMBER,
                              ),
                            ),
                            title: Text(
                              entry.partyName,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14.5 * scale,
                              ),
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    isIn
                                        ? 'تحصيل من حساب عميل'
                                        : 'سداد لمورد',
                                    style: TextStyle(
                                      fontSize: 12.5 * scale,
                                      color: AppColors.TEXT_SECONDARY,
                                    ),
                                  ),
                                  Text(
                                    dateFormat.format(entry.payment.createdAt),
                                    style: TextStyle(
                                      fontSize: 12.5 * scale,
                                      color: AppColors.TEXT_SECONDARY,
                                    ),
                                  ),
                                  if (entry.payment.note != null &&
                                      entry.payment.note!.isNotEmpty)
                                    Text(
                                      'ملاحظة: ${entry.payment.note}',
                                      style: TextStyle(
                                        fontSize: 12.5 * scale,
                                        color: AppColors.TEXT_SECONDARY,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            trailing: Text(
                              '${isIn ? '+' : '-'}'
                              '${entry.payment.amount.toStringAsFixed(0)} '
                              '${AppStrings.CURRENCY}',
                              style: TextStyle(
                                fontSize: 16 * scale,
                                fontWeight: FontWeight.bold,
                                color: isIn
                                    ? AppColors.SUCCESS_GREEN
                                    : AppColors.WARNING_AMBER,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  );
                },
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (err, _) => Center(child: Text('خطأ: $err')),
              ),
            ),
          ],
        ),
      ), // MaxWidthContainer
      ),
    );
  }

  Future<_PaymentsSummary> _loadSummary() async {
    final repo = ref.read(paymentRepositoryProvider);
    final now = DateTime.now();
    return _PaymentsSummary(
      collections: await repo.getTotalCollections(
        startDate: now,
        endDate: now,
      ),
      supplierPayments: await repo.getTotalSupplierPayments(
        startDate: now,
        endDate: now,
      ),
    );
  }

  Widget _buildFilterChip(String label, _PaymentFilter value) {
    final selected = _filter == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      selectedColor: AppColors.PRIMARY_BLUE.withValues(alpha: 0.12),
      labelStyle: TextStyle(
        color: selected ? AppColors.PRIMARY_BLUE : AppColors.TEXT_SECONDARY,
        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
      ),
      onSelected: (_) => setState(() => _filter = value),
    );
  }

  void _showAddPaymentDialog() {
    _PaymentPartyType partyType = _PaymentPartyType.customer;
    String? selectedPartyId;
    int partiesRevision = 0;
    final amountController = TextEditingController();
    final noteController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: const Text('تسجيل دفعة جديدة'),
            content: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // نوع الطرف
                  SegmentedButton<_PaymentPartyType>(
                    segments: const [
                      ButtonSegment(
                        value: _PaymentPartyType.customer,
                        label: Text('تحصيل من عميل'),
                        icon: Icon(Icons.person),
                      ),
                      ButtonSegment(
                        value: _PaymentPartyType.supplier,
                        label: Text('سداد لمورد'),
                        icon: Icon(Icons.local_shipping),
                      ),
                    ],
                    selected: {partyType},
                    onSelectionChanged: (selection) {
                      setDialogState(() {
                        partyType = selection.first;
                        selectedPartyId = null;
                      });
                    },
                  ),
                  const SizedBox(height: 16),

                  // اختيار الطرف
                  FutureBuilder<List<dynamic>>(
                    key: ValueKey('payment_party_${partyType}_$partiesRevision'),
                    future: partyType == _PaymentPartyType.customer
                        ? ref
                            .read(customerRepositoryProvider)
                            .getAllCustomers()
                            .then((list) => list.cast<dynamic>())
                        : ref
                            .read(supplierRepositoryProvider)
                            .getAllSuppliers()
                            .then((list) => list.cast<dynamic>()),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState ==
                          ConnectionState.waiting) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      final parties = snapshot.data ?? [];
                      if (parties.isEmpty) {
                        // لا يوجد أطراف بعد: أتاحة الإضافة السريعة من داخل النافذة
                        // حتى لا تنغلق شاشة المدفوعات على المستخدم بدون خيارات.
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              partyType == _PaymentPartyType.customer
                                  ? 'لا يوجد عملاء مسجلون بعد.'
                                  : 'لا يوجد موردون مسجلون بعد.',
                              style: const TextStyle(
                                color: AppColors.WARNING_AMBER,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                icon: const Icon(Icons.add, size: 18),
                                label: Text(
                                  partyType == _PaymentPartyType.customer
                                      ? 'إضافة عميل جديد'
                                      : 'إضافة مورد جديد',
                                ),
                                onPressed: () => _quickAddParty(
                                  partyType: partyType,
                                  onAdded: () =>
                                      setDialogState(() => partiesRevision++),
                                ),
                              ),
                            ),
                          ],
                        );
                      }
                       // إيجاد الطرف المحدد لعرض رصيده الحالي وتحذير
                       // تسجيل دفعة أكبر من المستحق (تصبح دفعة مقدماً).
                       Object? selectedParty;
                       for (final p in parties) {
                         if (p.id == selectedPartyId) {
                           selectedParty = p;
                           break;
                         }
                       }

                       return Column(
                         mainAxisSize: MainAxisSize.min,
                         crossAxisAlignment: CrossAxisAlignment.start,
                         children: [
                           DropdownButtonFormField<String>(
                             key: ValueKey('payment_party_$partyType'),
                             initialValue: selectedPartyId,
                             decoration: const InputDecoration(
                               labelText: 'اختر الطرف *',
                               border: OutlineInputBorder(),
                             ),
                             items: parties.map<DropdownMenuItem<String>>((p) {
                               final name = p.name as String;
                               final id = p.id as String;
                               String subtitle = '';
                               if (p is Customer) {
                                 final b = p.balanceDue;
                                 if (b > 0.01) {
                                   subtitle =
                                       ' (عليه ${b.toStringAsFixed(0)} ${AppStrings.CURRENCY})';
                                 } else if (b < -0.01) {
                                   subtitle =
                                       ' (رصيد مسبق ${(-b).toStringAsFixed(0)} ${AppStrings.CURRENCY})';
                                 }
                               } else if (p is Supplier) {
                                 final o = p.balanceOwed;
                                 if (o > 0.01) {
                                   subtitle =
                                       ' (مستحق له ${o.toStringAsFixed(0)} ${AppStrings.CURRENCY})';
                                 } else if (o < -0.01) {
                                   subtitle =
                                       ' (سداد زائد ${(-o).toStringAsFixed(0)} ${AppStrings.CURRENCY})';
                                 }
                               }
                               return DropdownMenuItem<String>(
                                 value: id,
                                 child: Text('$name$subtitle'),
                               );
                             }).toList(),
                             onChanged: (value) => setDialogState(
                                   () => selectedPartyId = value,
                                 ),
                             validator: (value) {
                               if (value == null) return 'يجب اختيار الطرف';
                               return null;
                             },
                           ),
                           if (selectedParty is Customer) ...[
                             const SizedBox(height: 8),
                             _PartyBalanceHint(
                               balance: selectedParty.balanceDue,
                               isCustomer: true,
                               currency: AppStrings.CURRENCY,
                               enteredAmount: double.tryParse(
                                 amountController.text.trim(),
                               ),
                             ),
                           ] else if (selectedParty is Supplier)
                             _PartyBalanceHint(
                               balance: selectedParty.balanceOwed,
                               isCustomer: false,
                               currency: AppStrings.CURRENCY,
                               enteredAmount: double.tryParse(
                                 amountController.text.trim(),
                               ),
                             ),
                           const SizedBox(height: 16),

                           // المبلغ
                           TextFormField(
                             controller: amountController,
                             // إعادة البناء لعرض تحذير الدفعة الزائدة مباشرة.
                             onChanged: (_) => setDialogState(() {}),
                             keyboardType: const TextInputType.numberWithOptions(
                               decimal: true,
                             ),
                             decoration: const InputDecoration(
                               labelText: 'المبلغ *',
                               suffixText: AppStrings.CURRENCY,
                               prefixIcon: Icon(Icons.payments_outlined),
                               border: OutlineInputBorder(),
                             ),
                             validator: (value) {
                               final amount =
                                   double.tryParse(value?.trim() ?? '');
                               if (amount == null || amount <= 0) {
                                 return 'يرجى إدخال مبلغ صحيح أكبر من الصفر';
                               }
                               return null;
                             },
                           ),
                           const SizedBox(height: 16),

                           // ملاحظة
                           TextFormField(
                             controller: noteController,
                             decoration: const InputDecoration(
                               labelText: 'ملاحظة (اختياري)',
                               hintText: 'مثال: تحصيل دفعة من فاتورة...',
                               border: OutlineInputBorder(),
                             ),
                             maxLines: 2,
                           ),
                         ],
                       );
                     },
                   ),
                 ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.PRIMARY_BLUE,
                  foregroundColor: Colors.white,
                ),
                onPressed: () async {
                  if (!formKey.currentState!.validate()) return;

                  final amount =
                      double.tryParse(amountController.text.trim()) ?? 0.0;
                  final note = noteController.text.trim();
                  final partyId = selectedPartyId!;

                  Navigator.of(ctx).pop();
                  await _recordPayment(
                    partyType: partyType,
                    partyId: partyId,
                    amount: amount,
                    note: note.isEmpty ? null : note,
                  );
                },
                child: const Text('تسجيل'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _recordPayment({
    required _PaymentPartyType partyType,
    required String partyId,
    required double amount,
    String? note,
  }) async {
    try {
      final userId = ref.read(authProvider).user?.id;
      if (partyType == _PaymentPartyType.customer) {
        await ref.read(customerRepositoryProvider).addCustomerPayment(
              customerId: partyId,
              amount: amount,
              note: note,
              userId: userId,
            );
      } else {
        await ref.read(supplierRepositoryProvider).addSupplierPayment(
              supplierId: partyId,
              amount: amount,
              note: note,
              userId: userId,
            );
      }

      // تحديث كل المزودات المتأثرة بالدفعة (الأرصدة والإحصائيات والخزينة
      // وقائمة المتأخرين عن السداد والديون).
      refreshAfterPayment(ref);

      if (mounted) {
        // إعادة بناء ملخص اليوم ليعكس الدفعة الجديدة.
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: AppColors.SUCCESS_GREEN,
            content: Text('✓ تم تسجيل الدفعة وتحديث الأرصدة'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.DANGER_RED,
            content: Text('فشل تسجيل الدفعة: $e'),
          ),
        );
      }
    }
  }

  /// إضافة سريعة لعميل/مورد من داخل نافذة تسجيل الدفعة، حتى لا ينحصر
  /// المستخدم بدون خيارات عند عدم وجود أطراف مسجلة بعد.
  Future<void> _quickAddParty({
    required _PaymentPartyType partyType,
    required VoidCallback onAdded,
  }) async {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final isCustomer = partyType == _PaymentPartyType.customer;

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isCustomer ? 'إضافة عميل سريع' : 'إضافة مورد سريع'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameController,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: isCustomer ? 'اسم العميل *' : 'اسم المورد *',
                  prefixIcon: const Icon(Icons.person_outline),
                  border: const OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'يرجى إدخال الاسم';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'رقم الهاتف (اختياري)',
                  prefixIcon: Icon(Icons.phone_outlined),
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.PRIMARY_BLUE,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;

              final name = nameController.text.trim();
              final phone = phoneController.text.trim();
              final now = DateTime.now();

              Navigator.of(ctx).pop();

              try {
                if (isCustomer) {
                  await ref.read(customerRepositoryProvider).insertCustomer(
                        Customer(
                          id: const Uuid().v4(),
                          name: name,
                          phone: phone.isEmpty ? null : phone,
                          balanceDue: 0.0,
                          createdAt: now,
                          updatedAt: now,
                        ),
                      );
                } else {
                  await ref.read(supplierRepositoryProvider).insertSupplier(
                        Supplier(
                          id: const Uuid().v4(),
                          name: name,
                          phone: phone.isEmpty ? null : phone,
                          balanceOwed: 0.0,
                          createdAt: now,
                          updatedAt: now,
                        ),
                      );
                }

                refreshAfterCustomerChange(ref);
                refreshAfterSupplierChange(ref);
                onAdded();

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      backgroundColor: AppColors.SUCCESS_GREEN,
                      content: Text('✓ تمت الإضافة — اختر الطرف وسجّل الدفعة'),
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: AppColors.DANGER_RED,
                      content: Text('فشلت الإضافة: $e'),
                    ),
                  );
                }
              }
            },
            child: const Text('إضافة'),
          ),
        ],
      ),
    );
  }
}

enum _PaymentFilter { all, incoming, outgoing }

enum _PaymentPartyType { customer, supplier }

/// بطاقة الرصيد الحالي للطرف + تحذير تسجيل دفعة أكبر من المستحق
/// (تُحتسب دفعة مقدماً/رصيداً مسبقاً — قرار يُخطَّر المستخدم قبل التسجيل).
class _PartyBalanceHint extends StatelessWidget {
  final double balance;
  final bool isCustomer;
  final String currency;
  final double? enteredAmount;

  const _PartyBalanceHint({
    required this.balance,
    required this.isCustomer,
    required this.currency,
    this.enteredAmount,
  });

  @override
  Widget build(BuildContext context) {
    final hasOutstanding = balance > 0.01;
    final hasPrepaid = balance < -0.01;

    final title = isCustomer
        ? hasOutstanding
            ? 'المستحق عليه حالياً:'
            : hasPrepaid
                ? 'رصيد مسبق له:'
                : 'حالة الحساب:'
        : hasOutstanding
            ? 'المستحق له حالياً:'
            : hasPrepaid
                ? 'سداد زائد له:'
                : 'حالة الحساب:';

    final valueColor = hasOutstanding
        ? AppColors.DANGER_RED
        : hasPrepaid
            ? AppColors.WARNING_AMBER
            : AppColors.SUCCESS_GREEN;

    // الدفعة أكبر من المستحق → تُحوَّل إلى رصيد مسبق.
    final entered = enteredAmount;
    final overAmount =
        entered != null && hasOutstanding && entered > balance + 0.005
            ? entered - balance
            : null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppLayout.SPACING_UNIT * 1.5),
      decoration: BoxDecoration(
        color: AppColors.PRIMARY_BLUE.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppLayout.BORDER_RADIUS),
        border: Border.all(
          color: AppColors.PRIMARY_BLUE.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.TEXT_SECONDARY,
                  ),
                ),
              ),
              Text(
                hasOutstanding
                    ? '${balance.toStringAsFixed(0)} $currency'
                    : hasPrepaid
                        ? '(${(-balance).toStringAsFixed(0)} $currency)'
                        : 'خالص',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: valueColor,
                ),
              ),
            ],
          ),
          if (overAmount != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(
                  Icons.info_outline,
                  size: 14,
                  color: AppColors.WARNING_AMBER,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'المبلغ أكبر من المستحق — سيُسجَّل دفعة '
                    'مقدماً (رصيد مسبق '
                    '${overAmount.toStringAsFixed(0)} $currency).',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.WARNING_AMBER,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _PaymentsSummary {
  final double collections;
  final double supplierPayments;

  _PaymentsSummary({required this.collections, required this.supplierPayments});
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final double amount;
  final IconData icon;
  final Color color;

  const _SummaryCard({
    required this.title,
    required this.amount,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppLayout.SPACING_UNIT * 2),
      decoration: BoxDecoration(
        color: AppColors.NEUTRAL_SURFACE,
        borderRadius: BorderRadius.circular(AppLayout.BORDER_RADIUS),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.TEXT_SECONDARY,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              ),
              Icon(icon, color: color, size: 20),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(
              '${amount.toStringAsFixed(0)} ${AppStrings.CURRENCY}',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
