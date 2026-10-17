import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_constants.dart';
import '../../core/services/printer_settings_service.dart';
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
    String? logoPath;
    try {
      logoPath = (await ShopProfileRepository().getProfile()).logoPath;
    } catch (_) {
      logoPath = null;
    }
    final paperSize = await PrinterSettingsService.getPaperSize();
    if (mounted) {
      setState(() {
        _storeName = prefs.getString('store_name');
        _storePhone = prefs.getString('store_phone');
        _storeLogoPath = logoPath;
        _width80mm = paperSize != '58mm';
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
    final screenWidth = MediaQuery.sizeOf(context).width;
    final dialogWidth = math.min(420.0, screenWidth * 0.94);

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
      child: Container(
        width: dialogWidth,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.90,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ترويسة الفاتورة: الشعار بجوار اسم المحل بحجم أنيق ومتناسق
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: (_storeLogoPath != null &&
                          _storeLogoPath!.isNotEmpty &&
                          File(_storeLogoPath!).existsSync())
                      ? Image.file(
                          File(_storeLogoPath!),
                          width: 30,
                          height: 30,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Image.asset(
                            'assets/images/logo.png',
                            width: 30,
                            height: 30,
                            fit: BoxFit.contain,
                          ),
                        )
                      : Image.asset(
                          'assets/images/logo.png',
                          width: 30,
                          height: 30,
                          fit: BoxFit.contain,
                        ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    _storeName?.trim().isNotEmpty == true
                        ? _storeName!.trim()
                        : AppStrings.STORE_NAME,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if (_storePhone != null && _storePhone!.trim().isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                'هاتف: ${_storePhone!.trim()}',
                style: const TextStyle(
                  fontSize: 10.5,
                  color: AppColors.TEXT_SECONDARY,
                ),
              ),
            ],
            const SizedBox(height: 2),
            Text(
              invoice.status == 'held' ? 'فاتورة معلقة' : 'فاتورة مبيعات',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 6),
            const Divider(thickness: 0.8, height: 1, color: Color(0xFFE2E8F0)),

            // محتوى الفاتورة القابل للتمرير بنسبة متناسقة دون مط
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // بطاقة بيانات الفاتورة
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'رقم الفاتورة: ${invoice.invoiceNumber}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11.5,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                              if (invoice.status != 'completed')
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 1.5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: (invoice.status == 'held'
                                            ? AppColors.WARNING_AMBER
                                            : AppColors.DANGER_RED)
                                        .withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    invoice.statusArabic,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: invoice.status == 'held'
                                          ? AppColors.WARNING_AMBER
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
                                  fontSize: 10.5,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                              Text(
                                'الدفع: ${invoice.paymentMethodArabic}',
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  color: Color(0xFF64748B),
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
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF334155),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),

                    // جدول الأصناف المتناسق القياسي
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: const Color(0xFFCBD5E1),
                          width: 0.8,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _gridRow(
                            isHeader: true,
                            cells: const [
                              _GridCell(
                                '#',
                                flex: 7,
                                align: TextAlign.center,
                              ),
                              _GridCell(
                                'الصنف',
                                flex: 45,
                                align: TextAlign.start,
                              ),
                              _GridCell(
                                'الكمية',
                                flex: 14,
                                align: TextAlign.center,
                              ),
                              _GridCell(
                                'السعر',
                                flex: 17,
                                align: TextAlign.center,
                              ),
                              _GridCell(
                                'الإجمالي',
                                flex: 17,
                                align: TextAlign.center,
                              ),
                            ],
                          ),
                          for (var i = 0; i < invoice.items.length; i++)
                            _gridRow(
                              zebra: i.isEven,
                              cells: [
                                _GridCell(
                                  '${i + 1}',
                                  flex: 7,
                                  align: TextAlign.center,
                                ),
                                _GridCell(
                                  invoice.items[i].productName ?? 'منتج',
                                  flex: 45,
                                  align: TextAlign.start,
                                ),
                                _GridCell(
                                  '${invoice.items[i].quantity}',
                                  flex: 14,
                                  align: TextAlign.center,
                                ),
                                _GridCell(
                                  invoice.items[i].unitPrice % 1 == 0
                                      ? invoice.items[i].unitPrice.toInt().toString()
                                      : invoice.items[i].unitPrice.toStringAsFixed(2),
                                  flex: 17,
                                  align: TextAlign.center,
                                ),
                                _GridCell(
                                  invoice.items[i].lineTotal % 1 == 0
                                      ? invoice.items[i].lineTotal.toInt().toString()
                                      : invoice.items[i].lineTotal.toStringAsFixed(2),
                                  flex: 17,
                                  align: TextAlign.center,
                                  bold: true,
                                ),
                              ],
                            ),
                          // شريط عدد الأصناف وإجمالي الكميات (متبع في البرامج العالمية)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: const BoxDecoration(
                              color: Color(0xFFF1F5F9),
                              border: Border(
                                top: BorderSide(
                                  color: Color(0xFFCBD5E1),
                                  width: 0.8,
                                ),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'عدد الأصناف: ${invoice.itemsCount} صنف',
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF1E293B),
                                  ),
                                ),
                                Text(
                                  'إجمالي الكمية: ${invoice.totalQuantity % 1 == 0 ? invoice.totalQuantity.toInt() : invoice.totalQuantity}',
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF1E293B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),

                    // ملخص المبالغ المالية
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        children: [
                          if (invoice.discount > 0 || invoice.tax > 0) ...[
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'الإجمالي الفرعي:',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                                Text(
                                  AppStrings.money(invoice.subtotal),
                                  style: const TextStyle(fontSize: 11),
                                ),
                              ],
                            ),
                            if (invoice.discount > 0) ...[
                              const SizedBox(height: 3),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'الخصم:',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: AppColors.DANGER_RED,
                                    ),
                                  ),
                                  Text(
                                    '- ${AppStrings.money(invoice.discount)}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.DANGER_RED,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            if (invoice.tax > 0) ...[
                              const SizedBox(height: 3),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'الضريبة:',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFF64748B),
                                    ),
                                  ),
                                  Text(
                                    AppStrings.money(invoice.tax),
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 3),
                            const Divider(
                              height: 1,
                              thickness: 0.5,
                              color: Color(0xFFCBD5E1),
                            ),
                            const SizedBox(height: 3),
                          ],
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                '${AppStrings.LABEL_TOTAL}:',
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                              Text(
                                AppStrings.money(invoice.total),
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.PRIMARY_BLUE,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                '${AppStrings.LABEL_PAID}:',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                              Text(
                                AppStrings.money(invoice.paidAmount),
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                invoice.isChangePositive
                                    ? '${AppStrings.LABEL_CHANGE}:'
                                    : '${AppStrings.LABEL_REMAINING_ON_CUSTOMER}:',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: invoice.isChangePositive
                                      ? AppColors.SUCCESS_GREEN
                                      : AppColors.DANGER_RED,
                                ),
                              ),
                              Text(
                                invoice.isChangePositive
                                    ? AppStrings.money(invoice.changeDue)
                                    : AppStrings.money(
                                        invoice.remainingOnCustomer,
                                      ),
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.bold,
                                  color: invoice.isChangePositive
                                      ? AppColors.SUCCESS_GREEN
                                      : AppColors.DANGER_RED,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),

                    // سياسة الاسترجاع
                    const Text(
                      'البضاعة المباعة ترد وتستبدل خلال 14 يوماً مع أصل الفاتورة',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 9.5,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 3),

                    // تذييل الشكر
                    const Text(
                      'شكراً لتعاملكم معنا • نسعد بخدمتكم دائماً',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF334155),
                      ),
                    ),
                    const SizedBox(height: 6),

                    // باركود الفاتورة المطابق للطباعة
                    Column(
                      children: [
                        CustomPaint(
                          size: const Size(110, 20),
                          painter: _BarcodePainter(invoice.invoiceNumber),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          invoice.invoiceNumber,
                          style: const TextStyle(
                            fontSize: 8.5,
                            fontFamily: 'monospace',
                            color: Color(0xFF64748B),
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'تم إصدار الفاتورة عبر نظام ${AppStrings.APP_NAME}',
                      style: const TextStyle(
                        fontSize: 8.5,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 6),
            const Divider(thickness: 0.8, height: 1, color: Color(0xFFE2E8F0)),
            const SizedBox(height: 8),

            // خيار مقاس لفة ورق الطباعة الحرارية (تصميم أنيق مضاد للفيضان)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.print_outlined,
                    size: 16,
                    color: AppColors.PRIMARY_BLUE,
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'عرض الورق:',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                      color: AppColors.TEXT_PRIMARY,
                    ),
                  ),
                  const Spacer(),
                  InkWell(
                    onTap: () => setState(() => _width80mm = true),
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _width80mm ? AppColors.PRIMARY_BLUE : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '80 مم (عريض)',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: _width80mm ? Colors.white : AppColors.TEXT_SECONDARY,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  InkWell(
                    onTap: () => setState(() => _width80mm = false),
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: !_width80mm ? AppColors.PRIMARY_BLUE : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '58 مم (محمول)',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: !_width80mm ? Colors.white : AppColors.TEXT_SECONDARY,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // أزرار العمليات
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      side: const BorderSide(color: Color(0xFFCBD5E1)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('إغلاق', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      side: const BorderSide(color: AppColors.PRIMARY_BLUE),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: _shareReceipt,
                    icon: const Icon(Icons.share_rounded, size: 15, color: AppColors.PRIMARY_BLUE),
                    label: const Text('مشاركة PDF', style: TextStyle(color: AppColors.PRIMARY_BLUE, fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 4,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      backgroundColor: AppColors.SUCCESS_GREEN,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      elevation: 1,
                    ),
                    onPressed: _printReceipt,
                    icon: const Icon(Icons.print_rounded, size: 16),
                    label: const Text(
                      'طباعة الفاتورة',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static const Color _gridLine = Color(0xFFCBD5E1);
  static const Color _headerBg = Color(0xFFF1F5F9);
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
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
              decoration: BoxDecoration(
                color: isHeader ? _headerBg : (zebra ? _zebraBg : Colors.white),
                border: Border.all(color: _gridLine, width: 0.5),
              ),
              child: c.align == TextAlign.start
                  ? Text(
                      c.text,
                      textAlign: c.align,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: isHeader ? 10.5 : 10.0,
                        fontWeight: isHeader || c.bold ? FontWeight.bold : FontWeight.normal,
                        color: isHeader
                            ? const Color(0xFF1E293B)
                            : const Color(0xFF334155),
                      ),
                    )
                  : FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: c.align == TextAlign.end
                          ? Alignment.centerLeft
                          : Alignment.center,
                      child: Text(
                        c.text,
                        textAlign: c.align,
                        style: TextStyle(
                          fontSize: isHeader ? 10.5 : 10.0,
                          fontWeight: isHeader || c.bold
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: isHeader
                              ? const Color(0xFF1E293B)
                              : const Color(0xFF334155),
                        ),
                      ),
                    ),
            ),
          ),
      ],
    );
  }
}

class _GridCell {
  final String text;
  final int flex;
  final TextAlign align;
  final bool bold;

  const _GridCell(
    this.text, {
    required this.flex,
    required this.align,
    this.bold = false,
  });
}

/// راسم باركود رقمي خفيف متناسق يطابق باركود PDF
class _BarcodePainter extends CustomPainter {
  final String data;

  const _BarcodePainter(this.data);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF0F172A)
      ..strokeWidth = 1.6;

    final bytes = data.codeUnits;
    if (bytes.isEmpty) return;

    final step = size.width / (bytes.length * 4 + 8);
    double x = 4.0;

    // خطوط بداية
    canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    x += step * 2;
    canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    x += step * 2;

    for (var i = 0; i < bytes.length; i++) {
      final b = bytes[i];
      if (b % 2 == 0) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      }
      x += step;
      if (b % 3 == 0) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      }
      x += step;
      if (b % 5 == 0) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      }
      x += step * 2;
    }

    // خطوط نهاية
    canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    x += step * 2;
    canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
