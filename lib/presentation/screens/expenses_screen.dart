import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/app_constants.dart';
import '../../data/models/expense.dart';
import '../../data/repositories/expense_repository.dart';
import '../../providers/app_providers.dart';
import '../../providers/auth_provider.dart';
import '../widgets/max_width_container.dart';

class ExpensesScreen extends ConsumerStatefulWidget {
  const ExpensesScreen({super.key});

  @override
  ConsumerState<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends ConsumerState<ExpensesScreen> {
  _ExpenseRange _range = _ExpenseRange.month;

  @override
  Widget build(BuildContext context) {
    final expensesAsync = ref.watch(expensesListProvider);
    final dateFormat = DateFormat('yyyy/MM/dd - hh:mm a');

    return Scaffold(
      appBar: AppBar(
        title: const Text('المصروفات'),
        backgroundColor: AppColors.PRIMARY_BLUE,
        centerTitle: true,
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.WARNING_AMBER,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('تسجيل مصروف'),
        onPressed: () => _showExpenseDialog(),
      ),
      body: Padding(
        padding: const EdgeInsets.all(AppLayout.SPACING_UNIT * 3),
        child: MaxWidthContainer(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'المصروفات التشغيلية',
                    style: TextStyle(
                      fontSize: AppTypography.HEADING_2,
                      fontWeight: FontWeight.bold,
                      color: AppColors.PRIMARY_BLUE_DARK,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'تُخصم المصروفات من صافي الربح في التقارير لتعكس الربح الحقيقي للمحل',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.TEXT_SECONDARY,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Filter chips
              Wrap(
                spacing: 8,
                children: [
                  _buildRangeChip('اليوم', _ExpenseRange.day),
                  _buildRangeChip('هذا الشهر', _ExpenseRange.month),
                  _buildRangeChip('الكل', _ExpenseRange.all),
                ],
              ),
              const SizedBox(height: 16),

              // Total card
              FutureBuilder<double>(
                future: _loadTotal(),
                builder: (context, snapshot) {
                  final total = snapshot.data ?? 0.0;
                  return Container(
                    padding: const EdgeInsets.all(AppLayout.SPACING_UNIT * 3),
                    decoration: BoxDecoration(
                      color: AppColors.WARNING_AMBER.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(
                        AppLayout.BORDER_RADIUS,
                      ),
                      border: Border.all(
                        color: AppColors.WARNING_AMBER.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'إجمالي المصروفات',
                              style: TextStyle(
                                fontSize: 14,
                                color: AppColors.TEXT_SECONDARY,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _rangeLabel[_range]!,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.TEXT_SECONDARY,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          '${total.toStringAsFixed(0)} ${AppStrings.CURRENCY}',
                          style: const TextStyle(
                            fontSize: AppTypography.HEADING_2,
                            fontWeight: FontWeight.bold,
                            color: AppColors.WARNING_AMBER,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 20),

              // Expenses list
              Expanded(
                child: expensesAsync.when(
                  data: (expenses) {
                    if (expenses.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.receipt_long_outlined,
                              size: 64,
                              color: AppColors.TEXT_SECONDARY.withValues(
                                alpha: 0.4,
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'لا توجد مصروفات مسجلة',
                              style: TextStyle(
                                fontSize: AppTypography.HEADING_3,
                                color: AppColors.TEXT_SECONDARY,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'اضغط "تسجيل مصروف" لإضافة إيجار أو فواتير أو رواتب',
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
                          itemCount: expenses.length,
                          separatorBuilder: (_, _) =>
                              const Divider(height: 1, thickness: 0.8),
                          itemBuilder: (context, index) {
                            final expense = expenses[index];
                            return Dismissible(
                              key: ValueKey(expense.id),
                              direction: DismissDirection.startToEnd,
                              background: Container(
                                color: AppColors.DANGER_RED,
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 24),
                                child: const Icon(
                                  Icons.delete,
                                  color: Colors.white,
                                ),
                              ),
                              confirmDismiss: (_) =>
                                  _confirmDelete(context, expense),
                              onDismissed: (_) => _deleteExpense(expense),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                leading: CircleAvatar(
                                  backgroundColor: AppColors.WARNING_AMBER
                                      .withValues(alpha: 0.12),
                                  child: const Icon(
                                    Icons.receipt,
                                    color: AppColors.WARNING_AMBER,
                                  ),
                                ),
                                title: Text(
                                  expense.title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        expense.category,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.TEXT_SECONDARY,
                                        ),
                                      ),
                                      Text(
                                        dateFormat.format(expense.createdAt),
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.TEXT_SECONDARY,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '${expense.amount.toStringAsFixed(0)} ${AppStrings.CURRENCY}',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.WARNING_AMBER,
                                      ),
                                    ),
                                    IconButton(
                                      icon: Icon(
                                        Icons.edit_outlined,
                                        size: 18,
                                        color: AppColors.PRIMARY_BLUE,
                                      ),
                                      tooltip: 'تعديل المصروف',
                                      visualDensity: VisualDensity.compact,
                                      onPressed: () =>
                                          _showExpenseDialog(existing: expense),
                                    ),
                                    IconButton(
                                      icon: Icon(
                                        Icons.delete_outline,
                                        size: 18,
                                        color: AppColors.DANGER_RED,
                                      ),
                                      tooltip: 'حذف المصروف',
                                      visualDensity: VisualDensity.compact,
                                      onPressed: () =>
                                          _confirmDelete(context, expense),
                                    ),
                                  ],
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

  Future<double> _loadTotal() async {
    final repo = ref.read(expenseRepositoryProvider);
    final now = DateTime.now();
    switch (_range) {
      case _ExpenseRange.day:
        return repo.getTotalExpenses(startDate: now, endDate: now);
      case _ExpenseRange.month:
        return repo.getTotalExpenses(
          startDate: DateTime(now.year, now.month, 1),
          endDate: DateTime(now.year, now.month + 1, 0),
        );
      case _ExpenseRange.all:
        return repo.getTotalExpenses();
    }
  }

  Widget _buildRangeChip(String label, _ExpenseRange value) {
    final selected = _range == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      selectedColor: AppColors.PRIMARY_BLUE.withValues(alpha: 0.12),
      labelStyle: TextStyle(
        color: selected ? AppColors.PRIMARY_BLUE : AppColors.TEXT_SECONDARY,
        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
      ),
      onSelected: (_) => setState(() => _range = value),
    );
  }

  /// حوار إضافة/تعديل مصروف في واجهة واحدة.
  /// [existing] != null يعني تعديل مصروف مسجل (تُحدث العمليات الحسابية بعدها).
  Future<void> _showExpenseDialog({Expense? existing}) async {
    final repo = ref.read(expenseRepositoryProvider);
    final isEdit = existing != null;

    // الفئات من قاعدة البيانات (الافتراضية + المخصصة).
    List<String> categories;
    try {
      categories = await repo.getCategories();
    } catch (_) {
      categories = List<String>.of(ExpenseRepository.defaultCategories);
    }
    if (categories.isEmpty) {
      categories = List<String>.of(ExpenseRepository.defaultCategories);
    }
    if (existing != null && !categories.contains(existing.category)) {
      categories.add(existing.category);
    }

    final titleController = TextEditingController(text: existing?.title ?? '');
    final amountController = TextEditingController(
      text: existing != null ? existing.amount.toStringAsFixed(0) : '',
    );
    final formKey = GlobalKey<FormState>();
    String category = existing?.category ?? categories.first;

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: Text(isEdit ? 'تعديل مصروف' : 'تسجيل مصروف جديد'),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      controller: titleController,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'بيان المصروف *',
                        hintText: 'مثال: إيجار المحل - أكتوبر',
                        prefixIcon: Icon(Icons.description_outlined),
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'يرجى إدخال بيان المصروف';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: amountController,
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
                        final amount = double.tryParse(value?.trim() ?? '');
                        if (amount == null || amount <= 0) {
                          return 'يرجى إدخال مبلغ صحيح أكبر من الصفر';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    // الفئة + زر إضافة فئة جديدة بجوارها.
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: categories.contains(category)
                                ? category
                                : null,
                            decoration: const InputDecoration(
                              labelText: 'الفئة',
                              prefixIcon: Icon(Icons.category_outlined),
                              border: OutlineInputBorder(),
                            ),
                            items: categories
                                .map(
                                  (c) => DropdownMenuItem(
                                    value: c,
                                    child: Text(
                                      c,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              if (value != null) {
                                setDialogState(() => category = value);
                              }
                            },
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: IconButton(
                            icon: const Icon(
                              Icons.add_box_outlined,
                              color: AppColors.PRIMARY_BLUE,
                            ),
                            tooltip: 'إضافة فئة جديدة',
                            onPressed: () async {
                              final newName = await _promptNewCategory();
                              if (newName == null) return;
                              setDialogState(() {
                                categories = [...categories, newName];
                                category = newName;
                              });
                            },
                          ),
                        ),
                      ],
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
                    backgroundColor: AppColors.WARNING_AMBER,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    if (!formKey.currentState!.validate()) return;

                    final amount =
                        double.tryParse(amountController.text.trim()) ?? 0.0;
                    final title = titleController.text.trim();

                    Navigator.of(ctx).pop();

                    try {
                      if (isEdit) {
                        // تعديل: تحديث البيان مع توثيقه وسحب إجماليات الشاشة.
                        await repo.updateExpense(
                          existing.copyWith(
                            title: title,
                            amount: amount,
                            category: category,
                          ),
                          userId: ref.read(authProvider).user?.id,
                        );
                      } else {
                        await repo.insertExpense(
                          Expense(
                            id: const Uuid().v4(),
                            title: title,
                            amount: amount,
                            category: category,
                            createdAt: DateTime.now(),
                          ),
                          userId: ref.read(authProvider).user?.id,
                        );
                      }

                      // إعادة كل العمليات الحسابية (الإجماليات واللوحة).
                      ref.invalidate(expensesListProvider);
                      ref.invalidate(dashboardStatsProvider);

                      if (mounted) {
                        setState(() {});
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: AppColors.SUCCESS_GREEN,
                            content: Text(
                              isEdit
                                  ? '✓ تم تعديل المصروف وتحديث الإجماليات'
                                  : '✓ تم تسجيل المصروف',
                            ),
                          ),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: AppColors.DANGER_RED,
                            content: Text(
                              'فشل ${isEdit ? 'تعديل' : 'تسجيل'} المصروف: $e',
                            ),
                          ),
                        );
                      }
                    }
                  },
                  child: Text(isEdit ? 'حفظ التعديل' : 'تسجيل'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// طلب اسم فئة مصروف جديدة من المستخدم وإضافتها لقائمة الفئات.
  Future<String?> _promptNewCategory() async {
    final controller = TextEditingController();
    final repo = ref.read(expenseRepositoryProvider);

    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إضافة فئة مصروف جديدة'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'اسم الفئة',
            hintText: 'مثال: اشتراكات، تسويق...',
            prefixIcon: Icon(Icons.category_outlined),
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () async {
              final value = controller.text.trim();
              if (value.isEmpty) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('يرجى إدخال اسم الفئة')),
                );
                return;
              }
              try {
                await repo.addCategory(value);
                if (!ctx.mounted) return;
                Navigator.of(ctx).pop(value);
              } catch (e) {
                if (!ctx.mounted) return;
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(
                    backgroundColor: AppColors.DANGER_RED,
                    content: Text('فشل إضافة الفئة: $e'),
                  ),
                );
              }
            },
            child: const Text('إضافة'),
          ),
        ],
      ),
    );
    return name;
  }

  Future<bool?> _confirmDelete(BuildContext context, Expense expense) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text(
          'هل تريد حذف المصروف "${expense.title}" بقيمة '
          '${expense.amount.toStringAsFixed(0)} ${AppStrings.CURRENCY}؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('تراجع'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.DANGER_RED,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteExpense(Expense expense) async {
    try {
      await ref
          .read(expenseRepositoryProvider)
          .deleteExpense(expense.id, userId: ref.read(authProvider).user?.id);
      ref.invalidate(expensesListProvider);
      ref.invalidate(dashboardStatsProvider);

      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: AppColors.SUCCESS_GREEN,
            content: Text('✓ تم حذف المصروف'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.DANGER_RED,
            content: Text('فشل الحذف: $e'),
          ),
        );
      }
    }
  }
}

enum _ExpenseRange { day, month, all }

const _rangeLabel = {
  _ExpenseRange.day: 'مصروفات اليوم',
  _ExpenseRange.month: 'مصروفات الشهر الحالي',
  _ExpenseRange.all: 'كل المصروفات المسجلة',
};
