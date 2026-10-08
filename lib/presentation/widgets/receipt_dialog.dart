import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_constants.dart';
import '../../data/models/sale_invoice.dart';
import '../../data/repositories/shop_profile_repository.dart';
import 'thermal_receipt_printer.dart';

class ReceiptDialog extends StatefulWidget {
  final SaleInvoice invoice;

  const ReceiptDialog({super.key, required this.invoice});

  @override
  State<ReceiptDialog> createState() => _ReceiptDialogState();
}

class _ReceiptDialogState extends State<ReceiptDialog> {
  String? _storeName;
  String? _storePhone;
  String? _storeLogoPath;
  bool _width80mm = true;

  @override
  void initState() {
    super.initState();
    _loadStoreInfo();
  }

  Future<void> _loadStoreInfo() async {
    final prefs = await SharedPreferences.getInstance();
    // الشعار من قاعدة بيانات المحل (المصدر الوحيد للحقيقة).
    String? logoPath;
    try {
      logoPath = (await ShopProfileRepository().getProfile()).logoPath;
    } catch (_) {
      logoPath = null;
    }
    if (mounted) {
      setState(() {
        _storeName = prefs.getString('store_name');
        _storePhone = prefs.getString('store_phone');
        _storeLogoPath = logoPath;
      });
    }
  }

  Future<void> _printReceipt() async {
    await ThermalReceiptPrinter.printReceipt(
      invoice: widget.invoice,
      width80mm: _width80mm,
      storeName: _storeName,
      storePhone: _storePhone,
      storeLogoPath: _storeLogoPath,
    );
  }

  Future<void> _shareReceipt() async {
    await ThermalReceiptPrinter.shareReceipt(
      invoice: widget.invoice,
      width80mm: _width80mm,
      storeName: _storeName,
      storePhone: _storePhone,
      storeLogoPath: _storeLogoPath,
    );
  }

  @override
  Widget build(BuildContext context) {
    final invoice = widget.invoice;
    final dateFormat = DateFormat('yyyy/MM/dd - hh:mm a');

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppLayout.BORDER_RADIUS),
      ),
      child: Container(
        width: 440,
        constraints: const BoxConstraints(maxHeight: 680),
        padding: const EdgeInsets.all(AppLayout.SPACING_UNIT * 3),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Receipt Header (الشعار بجوار اسم المحل — لا فوقه)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_storeLogoPath != null &&
                    _storeLogoPath!.isNotEmpty &&
                    File(_storeLogoPath!).existsSync()) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.file(
                      File(_storeLogoPath!),
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Text(
                  _storeName?.trim().isEmpty == false
                      ? _storeName!
                      : AppStrings.STORE_NAME,
                  style: const TextStyle(
                    fontSize: AppTypography.HEADING_3,
                    fontWeight: FontWeight.bold,
                    color: AppColors.PRIMARY_BLUE_DARK,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'فاتورة مبيعات نقدية',
              style: TextStyle(fontSize: 13, color: AppColors.TEXT_SECONDARY),
            ),
            const SizedBox(height: 12),
            const Divider(thickness: 1, height: 1),
            const SizedBox(height: 8),

            // Metadata
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'رقم الفاتورة: ${invoice.invoiceNumber}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: invoice.status == 'completed'
                        ? AppColors.SUCCESS_GREEN.withValues(alpha: 0.12)
                        : AppColors.DANGER_RED.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    invoice.statusArabic,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: invoice.status == 'completed'
                          ? AppColors.SUCCESS_GREEN
                          : AppColors.DANGER_RED,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'التاريخ: ${dateFormat.format(invoice.createdAt)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.TEXT_SECONDARY,
                  ),
                ),
                Text(
                  'طريقة الدفع: ${invoice.paymentMethodArabic}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.TEXT_SECONDARY,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'العميل: ${invoice.customerName ?? 'عميل نقدي'}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.TEXT_SECONDARY,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(thickness: 1, height: 1),

            // جدول الأصناف: جدول محترف بحدود واضحة على كل الخلايا
            // (تشكيل بنمط جداول الفواتير في البرامج المحاسبية): حد خارجي
            // داكن + شبكة داخلية بين كل الصفوف والأعمدة + رأس مؤطر.
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppColors.NEUTRAL_SURFACE,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF475569), width: 1.2),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _gridRow(
                    isHeader: true,
                    cells: const [
                      _GridCell('الصنف', flex: 4, align: TextAlign.start),
                      _GridCell('الكمية', flex: 2),
                      _GridCell('السعر', flex: 2),
                      _GridCell('الإجمالي', flex: 2, align: TextAlign.end),
                    ],
                  ),
                  for (var i = 0; i < invoice.items.length; i++)
                    _gridRow(
                      zebra: i.isEven,
                      cells: [
                        _GridCell(invoice.items[i].productName ?? 'منتج',
                            flex: 4, align: TextAlign.start),
                        _GridCell('${invoice.items[i].quantity}', flex: 2),
                        _GridCell(
                            invoice.items[i].unitPrice.toStringAsFixed(0),
                            flex: 2),
                        _GridCell(
                            invoice.items[i].lineTotal.toStringAsFixed(0),
                            flex: 2, align: TextAlign.end, bold: true),
                      ],
                    ),
                ],
              ),
            ),

            const Divider(thickness: 1, height: 16),

            // Financial Summary
            if (invoice.discount > 0) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'الإجمالي الفرعي:',
                    style: TextStyle(fontSize: 13),
                  ),
                  Text(
                    AppStrings.money(invoice.subtotal),
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'الخصم:',
                    style: TextStyle(fontSize: 13, color: AppColors.DANGER_RED),
                  ),
                  Text(
                    '- ${AppStrings.money(invoice.discount)}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.DANGER_RED,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
            ],

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '${AppStrings.LABEL_TOTAL}:',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                Text(
                  AppStrings.money(invoice.total),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.PRIMARY_BLUE,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '${AppStrings.LABEL_PAID}:',
                  style: TextStyle(fontSize: 13),
                ),
                Text(
                  AppStrings.money(invoice.paidAmount),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  invoice.isChangePositive
                      ? '${AppStrings.LABEL_CHANGE}:'
                      : '${AppStrings.LABEL_REMAINING_ON_CUSTOMER}:',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: invoice.isChangePositive
                        ? AppColors.SUCCESS_GREEN
                        : AppColors.DANGER_RED,
                  ),
                ),
                Text(
                  invoice.isChangePositive
                      ? AppStrings.money(invoice.changeDue)
                      : AppStrings.money(invoice.remainingOnCustomer),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: invoice.isChangePositive
                        ? AppColors.SUCCESS_GREEN
                        : AppColors.DANGER_RED,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Paper width toggle (Phase 3.14)
            Row(
              children: [
                const Text('عرض الورقة:', style: TextStyle(fontSize: 13)),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('80mm'),
                  selected: _width80mm,
                  onSelected: (_) => setState(() => _width80mm = true),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('58mm'),
                  selected: !_width80mm,
                  onSelected: (_) => setState(() => _width80mm = false),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('إغلاق'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _shareReceipt,
                    icon: const Icon(Icons.share, size: 18),
                    label: const Text('مشاركة'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _printReceipt,
                    icon: const Icon(Icons.print, size: 18),
                    label: const Text('طباعة'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// صف في جدول الأصناف: صف مكوّن من خلايا محددة — الرأس بخلفية رمادية
  /// والنصوص العيادية بخط صفير (zebra) لوضوح الأقواس الطويلة.
  static const Color _gridLine = Color(0xFF94A3B8);
  static const Color _headerBg = Color(0xFFEEF2F7);
  static const Color _zebraBg = Color(0xFFF8FAFC);

  Widget _gridRow({
    required List<_GridCell> cells,
    bool isHeader = false,
    bool zebra = false,
  }) {
    return Row(
      children: [
        for (final c in cells)
          Expanded(
            flex: c.flex,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
              decoration: BoxDecoration(
                color: isHeader ? _headerBg : (zebra ? _zebraBg : null),
                // حد كامل على كل خلية: الشبكة الداخلية تتضح تماماً
                // (حدود مزدوجة بين الخلية المجاورة ≈ سُمك موحّد).
                border: Border.all(color: _gridLine, width: 0.7),
              ),
              child: Text(
                c.text,
                textAlign: c.align,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: isHeader ? 12.5 : 13,
                  fontWeight: isHeader || c.bold
                      ? FontWeight.bold
                      : FontWeight.w400,
                  color: isHeader
                      ? AppColors.PRIMARY_BLUE_DARK
                      : AppColors.TEXT_PRIMARY,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// خلية في جدول الفاتورة: نص + مرونة + محاذاة.
class _GridCell {
  final String text;
  final int flex;
  final TextAlign align;
  final bool bold;

  const _GridCell(
    this.text, {
    this.flex = 1,
    this.align = TextAlign.center,
    this.bold = false,
  });
}
