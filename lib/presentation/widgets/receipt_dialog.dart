import 'dart:io';

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

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        width: _width80mm ? 360 : 310,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.88,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ترويسة الفاتورة: الشعار بجوار اسم المحل (ولا داعي لكتابة رقم الفاتورة هنا)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_storeLogoPath != null &&
                    _storeLogoPath!.isNotEmpty &&
                    File(_storeLogoPath!).existsSync()) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      File(_storeLogoPath!),
                      width: 38,
                      height: 38,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Text(
                  _storeName?.trim().isNotEmpty == true
                      ? _storeName!.trim()
                      : AppStrings.STORE_NAME,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ],
            ),
            if (_storePhone != null && _storePhone!.trim().isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                'هاتف: ${_storePhone!.trim()}',
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AppColors.TEXT_SECONDARY,
                ),
              ),
            ],
            const SizedBox(height: 3),
            Text(
              invoice.status == 'held' ? 'فاتورة معلقة' : 'فاتورة مبيعات',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 8),
            const Divider(thickness: 0.8, height: 1, color: Color(0xFFE2E8F0)),

            // محتوى الفاتورة القابل للتمرير بنسبة متناسقة دون مط
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // بطاقة بيانات الفاتورة
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 9,
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
                                  fontSize: 13,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                              if (invoice.status != 'completed')
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
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
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: invoice.status == 'held'
                                          ? AppColors.WARNING_AMBER
                                          : AppColors.DANGER_RED,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 5),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'التاريخ: ${dateFormat.format(invoice.createdAt)}',
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                              Text(
                                'طريقة الدفع: ${invoice.paymentMethodArabic}',
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 5),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'العميل: ${invoice.customerName ?? 'عميل نقدي'}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF334155),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),

                    // جدول الأصناف: تكبير خانة الصنف وتصغير خانات الكمية والسعر والإجمالي
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
                                'الصنف',
                                flex: 44,
                                align: TextAlign.start,
                              ),
                              _GridCell(
                                'الكمية',
                                flex: 18,
                                align: TextAlign.center,
                              ),
                              _GridCell(
                                'السعر',
                                flex: 19,
                                align: TextAlign.center,
                              ),
                              _GridCell(
                                'الإجمالي',
                                flex: 19,
                                align: TextAlign.center,
                              ),
                            ],
                          ),
                          for (var i = 0; i < invoice.items.length; i++)
                            _gridRow(
                              zebra: i.isEven,
                              cells: [
                                _GridCell(
                                  invoice.items[i].productName ?? 'منتج',
                                  flex: 44,
                                  align: TextAlign.start,
                                ),
                                _GridCell(
                                  '${invoice.items[i].quantity}',
                                  flex: 18,
                                  align: TextAlign.center,
                                ),
                                _GridCell(
                                  invoice.items[i].unitPrice % 1 == 0
                                      ? invoice.items[i].unitPrice.toInt().toString()
                                      : invoice.items[i].unitPrice.toStringAsFixed(2),
                                  flex: 19,
                                  align: TextAlign.center,
                                ),
                                _GridCell(
                                  invoice.items[i].lineTotal % 1 == 0
                                      ? invoice.items[i].lineTotal.toInt().toString()
                                      : invoice.items[i].lineTotal.toStringAsFixed(2),
                                  flex: 19,
                                  align: TextAlign.center,
                                  bold: true,
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),

                    // ملخص المبالغ المالية
                    Container(
                      padding: const EdgeInsets.all(12),
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
                                    fontSize: 12,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                                Text(
                                  AppStrings.money(invoice.subtotal),
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ],
                            ),
                            if (invoice.discount > 0) ...[
                              const SizedBox(height: 4),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'الخصم:',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.DANGER_RED,
                                    ),
                                  ),
                                  Text(
                                    '- ${AppStrings.money(invoice.discount)}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.DANGER_RED,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            if (invoice.tax > 0) ...[
                              const SizedBox(height: 4),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'الضريبة:',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF64748B),
                                    ),
                                  ),
                                  Text(
                                    AppStrings.money(invoice.tax),
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ],
                              ),
                            ],
                            const Divider(
                              height: 12,
                              thickness: 0.6,
                              color: Color(0xFFE2E8F0),
                            ),
                          ],
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                '${AppStrings.LABEL_TOTAL}:',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                              Text(
                                AppStrings.money(invoice.total),
                                style: const TextStyle(
                                  fontSize: 17,
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
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                              Text(
                                AppStrings.money(invoice.paidAmount),
                                style: const TextStyle(
                                  fontSize: 12.5,
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
                                  fontSize: 12.5,
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
                                  fontSize: 13.5,
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
                    const SizedBox(height: 10),

                    // سياسة الاسترجاع
                    const Text(
                      'البضاعة المباعة ترد وتستبدل خلال 14 يوماً مع أصل الفاتورة',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 6),

                    // تذييل الشكر
                    const Text(
                      'شكراً لتعاملكم معنا • نسعد بخدمتكم دائماً',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF334155),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // باركود الفاتورة المطابق للطباعة
                    Column(
                      children: [
                        CustomPaint(
                          size: Size(_width80mm ? 120 : 100, 22),
                          painter: _BarcodePainter(),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          invoice.invoiceNumber,
                          style: const TextStyle(
                            fontSize: 10,
                            letterSpacing: 1.2,
                            color: Color(0xFF64748B),
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 6),
            const Divider(thickness: 0.8, height: 1, color: Color(0xFFE2E8F0)),
            const SizedBox(height: 6),

            // خيار مقاس لفة ورق الطباعة الحرارية
            Row(
              children: [
                const Icon(
                  Icons.print_outlined,
                  size: 16,
                  color: AppColors.PRIMARY_BLUE_DARK,
                ),
                const SizedBox(width: 6),
                const Text(
                  'مقاس الورق:',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                    color: AppColors.TEXT_PRIMARY,
                  ),
                ),
                const Spacer(),
                ChoiceChip(
                  label: const Text('80 مم (عريض / كاشير قياسي)'),
                  labelStyle: TextStyle(
                    fontSize: 10.5,
                    fontWeight: _width80mm ? FontWeight.bold : FontWeight.normal,
                  ),
                  selected: _width80mm,
                  onSelected: (_) => setState(() => _width80mm = true),
                ),
                const SizedBox(width: 4),
                ChoiceChip(
                  label: const Text('58 مم (محمول)'),
                  labelStyle: TextStyle(
                    fontSize: 10.5,
                    fontWeight:
                        !_width80mm ? FontWeight.bold : FontWeight.normal,
                  ),
                  selected: !_width80mm,
                  onSelected: (_) => setState(() => _width80mm = false),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // أزرار العمليات
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      side: const BorderSide(color: Color(0xFFCBD5E1)),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('إغلاق'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      side: const BorderSide(color: Color(0xFFCBD5E1)),
                    ),
                    onPressed: _shareReceipt,
                    icon: const Icon(Icons.share, size: 15),
                    label: const Text('مشاركة'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      backgroundColor: AppColors.SUCCESS_GREEN,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _printReceipt,
                    icon: const Icon(Icons.print, size: 15),
                    label: const Text(
                      'طباعة الفاتورة',
                      style: TextStyle(fontWeight: FontWeight.bold),
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
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              decoration: BoxDecoration(
                color: isHeader ? _headerBg : (zebra ? _zebraBg : Colors.white),
                border: Border.all(color: _gridLine, width: 0.5),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: c.align == TextAlign.start
                    ? Alignment.centerRight
                    : (c.align == TextAlign.end
                        ? Alignment.centerLeft
                        : Alignment.center),
                child: Text(
                  c.text,
                  textAlign: c.align,
                  style: TextStyle(
                    fontSize: 12,
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
      this.flex = 1,
      this.align = TextAlign.center,
      this.bold = false,
    });
}

/// رسم باركود شريطي نظيف ودقيق يحاكي Code128 كما يظهر في إيصال الكاشير المطبوع.
class _BarcodePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF1E293B)
      ..strokeCap = StrokeCap.square;

    const pattern = [2, 1, 3, 1, 1, 2, 1, 3, 2, 1, 1, 2, 3, 1, 2, 1, 1, 3, 1, 2, 2, 1, 1, 3, 2];
    double x = 4.0;
    final step = (size.width - 8) / (pattern.length * 1.55);
    for (int i = 0; i < pattern.length; i++) {
      final w = pattern[i] * 0.75;
      paint.strokeWidth = w;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      x += step * (pattern[i] > 1 ? 1.4 : 1.0) + 1.1;
      if (x > size.width - 4) break;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
