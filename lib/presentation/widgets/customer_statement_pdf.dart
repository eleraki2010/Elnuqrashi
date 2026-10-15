import 'dart:io';

import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../../core/constants/app_constants.dart';
import '../../data/repositories/customer_repository.dart';

/// حركة موحدة في كشف حساب العميل للمطبعة.
class _StatementRow {
  final DateTime date;
  final int typeOrder;
  final String label;
  final double debit;
  final double credit;
  _StatementRow(this.date, this.typeOrder, this.label, this.debit, this.credit);
}

/// طباعة كشف حساب العميل (A4) — شامل كل حركاته (فواتير + مرتجعات +
/// تحصيلات) برصيد دائري بعد كل حركة، بنفس قواعد الديون المطبقة في
/// شاشة كشف حساب العميل.
class CustomerStatementPdf {
  static Future<pw.Font> _loadFont(String asset) async {
    final data = await rootBundle.load(asset);
    return pw.Font.ttf(data);
  }

  static Future<Uint8List?> _loadLogoBytes(String? storeLogoPath) async {
    if (storeLogoPath == null || storeLogoPath.isEmpty) return null;
    try {
      final file = File(storeLogoPath);
      if (!file.existsSync()) return null;
      return await file.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  static pw.ImageProvider? _logoProvider(Uint8List bytes) {
    try {
      return pw.MemoryImage(bytes);
    } catch (_) {
      return null;
    }
  }

  /// بناء PDF كشف حساب العميل.
  static Future<Uint8List> buildStatementPdf({
    required CustomerStatement statement,
    String? storeName,
    String? storeLogoPath,
  }) async {
    final baseFont = await _loadFont('fonts/Cairo-Regular.ttf');
    final boldFont = await _loadFont('fonts/Cairo-Bold.ttf');
    final logoBytes = await _loadLogoBytes(storeLogoPath);
    final logo = logoBytes != null ? _logoProvider(logoBytes) : null;

    final dateFmt = DateFormat('yyyy/MM/dd');
    final timeFmt = DateFormat('hh:mm a');

    // الحركات الموحدة بنفس قواعد شاشة كشف حساب العميل:
    // - فاتورة: يزيد الدين بمقدار غير المسدد (total − paid).
    // - مرتجع: يخصم من الدين بمقدار ما خُصم فعلياً (debt_reduction).
    // - تحصيل: يخصم المبلغ.
    final s = statement;
    final c = s.customer;

    // أرقام فواتير العميل لمعرفة رقم الفاتورة الأصلية عند بيان المرتجع.
    final invoiceNumbers = {
      for (final inv in s.invoices) inv.id: inv.invoiceNumber,
    };

    final rows = <_StatementRow>[];
    for (final inv in s.invoices) {
      final remaining = (inv.total - inv.paidAmount).clamp(0.0, double.infinity);
      var label =
          '${inv.status == 'held' ? 'فاتورة معلّقة' : 'فاتورة بيع'} #${inv.invoiceNumber}';
      if (inv.paidAmount > 0.005) {
        label += ' (مدفوع منها ${inv.paidAmount.toStringAsFixed(0)})';
      }
      rows.add(_StatementRow(inv.createdAt, 0, label, remaining, 0.0));
    }
    for (final r in s.returns) {
      final originalNo =
          invoiceNumbers[r.invoice.originalSaleInvoiceId] ?? '—';
      var label = 'مرتجع من فاتورة #$originalNo';
      final isCashRefund = r.invoice.cashRefundOut > 0.001 && r.invoice.debtReduction <= 0.001;
      if (isCashRefund) {
        label += ' (استرداد نقدي من الخزينة)';
      }
      final returnVal = isCashRefund
          ? 0.0
          : (r.invoice.debtReduction > 0.001
              ? r.invoice.debtReduction
              : r.invoice.returnAmount);
      rows.add(
          _StatementRow(r.invoice.createdAt, 1, label, 0.0, returnVal));
    }
    for (final p in s.payments) {
      rows.add(_StatementRow(
        p.createdAt,
        2,
        p.note != null && p.note!.trim().isNotEmpty
            ? 'تحصيل (دفعة) — ${p.note!.trim()}'
            : 'تحصيل (دفعة)',
        0.0,
        p.amount,
      ));
    }
    rows.sort((a, b) {
      final byDate = a.date.compareTo(b.date);
      if (byDate != 0) return byDate;
      return a.typeOrder.compareTo(b.typeOrder);
    });

    final netActivity = rows.fold(0.0, (sum, r) => sum + (r.debit - r.credit));
    final openingBalance = c.balanceDue - netActivity;
    if (openingBalance.abs() > 0.01) {
      rows.insert(
        0,
        _StatementRow(
          c.createdAt,
          -1,
          'رصيد سابق / افتتاحي',
          openingBalance > 0 ? openingBalance : 0.0,
          openingBalance < 0 ? -openingBalance : 0.0,
        ),
      );
    }

    var running = 0.0;
    final runningBalances = <double>[
      for (final r in rows)
        (running += r.debit - r.credit),
    ];

    final totalSales = s.invoices.fold(0.0, (sum, i) => sum + i.total);
    final totalReturns =
        s.returns.fold(0.0, (sum, r) => sum + r.invoice.returnAmount);
    final totalCollections =
        s.payments.fold(0.0, (sum, p) => sum + p.amount);

    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        textDirection: pw.TextDirection.rtl,
        theme: pw.ThemeData.withFont(base: baseFont, bold: boldFont),
        header: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Row(
                    mainAxisSize: pw.MainAxisSize.min,
                    children: [
                      if (logo != null) ...[
                        pw.Image(logo, width: 34, height: 34),
                        pw.SizedBox(width: 8),
                      ],
                      pw.Text(
                        (storeName?.trim().isNotEmpty == true)
                            ? storeName!.trim()
                            : AppStrings.STORE_NAME,
                        style: pw.TextStyle(
                          font: boldFont,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  pw.Text(
                    'كشف حساب عميل',
                    style: pw.TextStyle(
                      font: boldFont,
                      fontSize: 14,
                      color: PdfColors.grey800,
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 3),
              pw.Divider(thickness: 0.8),
              pw.SizedBox(height: 4),
            ],
          );
        },
        footer: (context) {
          return pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'تاريخ الطباعة: ${dateFmt.format(DateTime.now())} - ${timeFmt.format(DateTime.now())}',
                style: pw.TextStyle(
                  font: baseFont,
                  fontSize: 8,
                  color: PdfColors.grey600,
                ),
              ),
              pw.Text(
                'صفحة ${context.pageNumber} من ${context.pagesCount}',
                style: pw.TextStyle(
                  font: baseFont,
                  fontSize: 8,
                  color: PdfColors.grey600,
                ),
              ),
            ],
          );
        },
        build: (context) => [
          // بيانات العميل والتاريخ
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'العميل: ${c.name}',
                    style: pw.TextStyle(font: boldFont, fontSize: 12),
                  ),
                  if (c.phone != null && c.phone!.isNotEmpty)
                    pw.Text(
                      'هاتف: ${c.phone}',
                      style: pw.TextStyle(
                        font: baseFont,
                        fontSize: 9.5,
                        color: PdfColors.grey700,
                      ),
                    ),
                ],
              ),
              pw.Text(
                'تاريخ الإصدار: ${dateFmt.format(DateTime.now())}',
                style: pw.TextStyle(
                  font: baseFont,
                  fontSize: 9.5,
                  color: PdfColors.grey700,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 8),

          // ملخص الأرصدة
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              _summaryCard(
                'إجمالي الفواتير',
                AppStrings.money(totalSales),
                PdfColors.blue,
                baseFont,
                boldFont,
              ),
              _summaryCard(
                'إجمالي المرتجعات',
                AppStrings.money(totalReturns),
                PdfColors.orange500,
                baseFont,
                boldFont,
              ),
              _summaryCard(
                'إجمالي التحصيلات',
                AppStrings.money(totalCollections),
                PdfColors.green500,
                baseFont,
                boldFont,
              ),
              _summaryCard(
                c.hasDebt
                    ? 'الرصيد المستحق على العميل'
                    : c.hasCredit
                        ? 'رصيد مسبق لصالح العميل'
                        : 'حالة الحساب',
                AppStrings.money(
                  c.hasDebt ? c.balanceDue : -c.balanceDue,
                ),
                c.hasDebt
                    ? PdfColors.orange500
                    : c.hasCredit
                        ? PdfColors.blue
                        : PdfColors.green500,
                baseFont,
                boldFont,
              ),
            ],
          ),
          pw.SizedBox(height: 12),

          // عنوان جدول حركة الحساب
          pw.Text(
            'سجل حركة الحساب والرصيد التراكمي:',
            style: pw.TextStyle(font: boldFont, fontSize: 11),
          ),
          pw.SizedBox(height: 4),

          // جدول الحركات: التاريخ | البيان | مدين | دائن | الرصيد
          pw.Table(
            border: pw.TableBorder.all(
              color: PdfColors.grey,
              width: 0.5,
            ),
            defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
            columnWidths: {
              0: const pw.FlexColumnWidth(2),
              1: const pw.FlexColumnWidth(4.5),
              2: const pw.FlexColumnWidth(2),
              3: const pw.FlexColumnWidth(2),
              4: const pw.FlexColumnWidth(2),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(
                  color: PdfColors.grey300,
                ),
                children: [
                  _cell('التاريخ', bold: true, font: boldFont),
                  _cell('البيان', bold: true, font: boldFont),
                  _cell(
                    'مدين (مبيعات)',
                    bold: true,
                    align: pw.Alignment.centerLeft,
                    font: boldFont,
                  ),
                  _cell(
                    'دائن (سداد/مرتجع)',
                    bold: true,
                    align: pw.Alignment.centerLeft,
                    font: boldFont,
                  ),
                  _cell(
                    'الرصيد',
                    bold: true,
                    align: pw.Alignment.centerLeft,
                    font: boldFont,
                  ),
                ],
              ),
              if (rows.isEmpty)
                pw.TableRow(
                  children: List.filled(
                    5,
                    _cell(
                      'لا توجد حركات مسجلة',
                      align: pw.Alignment.center,
                      font: baseFont,
                    ),
                  ),
                )
              else
                ...rows.asMap().entries.map(
                  (e) {
                    final r = e.value;
                    final balance = runningBalances[e.key];
                    return pw.TableRow(
                      children: [
                        _cell(dateFmt.format(r.date), font: baseFont),
                        _cell(r.label, font: baseFont),
                        _cell(
                          r.debit > 0 ? AppStrings.money(r.debit) : '—',
                          align: pw.Alignment.centerLeft,
                          font: baseFont,
                        ),
                        _cell(
                          r.credit > 0 ? AppStrings.money(r.credit) : '—',
                          align: pw.Alignment.centerLeft,
                          font: baseFont,
                        ),
                        _cell(
                          AppStrings.money(balance),
                          align: pw.Alignment.centerLeft,
                          font: baseFont,
                          color: balance > 0.005
                              ? PdfColors.orange500
                              : PdfColors.green500,
                        ),
                      ],
                    );
                  },
                ),
              if (rows.isNotEmpty)
                pw.TableRow(
                  decoration: const pw.BoxDecoration(
                    color: PdfColors.grey200,
                  ),
                  children: [
                    _cell('الإجمالي', bold: true, font: boldFont),
                    _cell('', font: baseFont),
                    _cell(
                      AppStrings.money(
                        rows.fold(0.0, (s, r) => s + r.debit),
                      ),
                      bold: true,
                      align: pw.Alignment.centerLeft,
                      font: boldFont,
                    ),
                    _cell(
                      AppStrings.money(
                        rows.fold(0.0, (s, r) => s + r.credit),
                      ),
                      bold: true,
                      align: pw.Alignment.centerLeft,
                      font: boldFont,
                    ),
                    _cell(
                      AppStrings.money(c.balanceDue),
                      bold: true,
                      align: pw.Alignment.centerLeft,
                      font: boldFont,
                      color: c.hasDebt
                          ? PdfColors.orange500
                          : PdfColors.green500,
                    ),
                  ],
                ),
            ],
          ),
          pw.SizedBox(height: 16),

          // قسم تفاصيل العمليات المسجلة (الأصناف والبنود لكل فاتورة ومرتجع وسداد)
          if (s.invoices.any((inv) => inv.items.isNotEmpty) ||
              s.returns.any((r) => r.invoice.items.isNotEmpty)) ...[
            pw.Text(
              'تفاصيل بنود العمليات المسجلة للعميل:',
              style: pw.TextStyle(font: boldFont, fontSize: 12),
            ),
            pw.SizedBox(height: 6),
            ...s.invoices.where((inv) => inv.items.isNotEmpty).map(
              (inv) => pw.Container(
                margin: const pw.EdgeInsets.only(bottom: 10),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: [
                    // ترويسة الفاتورة المصغرة
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      color: PdfColors.grey100,
                      child: pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(
                            'فاتورة بيع #${inv.invoiceNumber} (${inv.statusArabic}) — ${dateFmt.format(inv.createdAt)}',
                            style: pw.TextStyle(font: boldFont, fontSize: 9.5),
                          ),
                          pw.Text(
                            'الدفع: ${inv.paymentMethodArabic} | الإجمالي: ${AppStrings.money(inv.total)} | المدفوع: ${AppStrings.money(inv.paidAmount)}',
                            style: pw.TextStyle(font: baseFont, fontSize: 9),
                          ),
                        ],
                      ),
                    ),
                    // جدول أصناف الفاتورة
                    pw.Table(
                      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.4),
                      columnWidths: {
                        0: const pw.FlexColumnWidth(5),
                        1: const pw.FlexColumnWidth(1.8),
                        2: const pw.FlexColumnWidth(2),
                        3: const pw.FlexColumnWidth(2.2),
                      },
                      children: [
                        pw.TableRow(
                          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                          children: [
                            _cell('الصنف', bold: true, font: boldFont),
                            _cell('الكمية', bold: true, align: pw.Alignment.center, font: boldFont),
                            _cell('السعر', bold: true, align: pw.Alignment.center, font: boldFont),
                            _cell('الإجمالي', bold: true, align: pw.Alignment.centerLeft, font: boldFont),
                          ],
                        ),
                        ...inv.items.map(
                          (item) => pw.TableRow(
                            children: [
                              _cell(item.productName ?? 'منتج', font: baseFont),
                              _cell('${item.quantity}', align: pw.Alignment.center, font: baseFont),
                              _cell(item.unitPrice.toStringAsFixed(0), align: pw.Alignment.center, font: baseFont),
                              _cell(item.lineTotal.toStringAsFixed(0), align: pw.Alignment.centerLeft, bold: true, font: baseFont),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            // المرتجعات بتفاصيل أصنافها إن وُجدت
            ...s.returns.where((r) => r.invoice.items.isNotEmpty).map(
              (r) => pw.Container(
                margin: const pw.EdgeInsets.only(bottom: 10),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.orange300, width: 0.5),
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: [
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      color: PdfColors.orange50,
                      child: pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(
                            'مرتجع من فاتورة #${invoiceNumbers[r.invoice.originalSaleInvoiceId] ?? "—"} — ${dateFmt.format(r.invoice.createdAt)}',
                            style: pw.TextStyle(font: boldFont, fontSize: 9.5),
                          ),
                          pw.Text(
                            'قيمة المرتجع: ${AppStrings.money(r.invoice.returnAmount)} | الخصم من الحساب: ${AppStrings.money(r.invoice.debtReduction)}',
                            style: pw.TextStyle(font: baseFont, fontSize: 9),
                          ),
                        ],
                      ),
                    ),
                    pw.Table(
                      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.4),
                      columnWidths: {
                        0: const pw.FlexColumnWidth(5),
                        1: const pw.FlexColumnWidth(1.8),
                        2: const pw.FlexColumnWidth(2),
                        3: const pw.FlexColumnWidth(2.2),
                      },
                      children: [
                        pw.TableRow(
                          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                          children: [
                            _cell('الصنف المرتجع', bold: true, font: boldFont),
                            _cell('الكمية', bold: true, align: pw.Alignment.center, font: boldFont),
                            _cell('السعر', bold: true, align: pw.Alignment.center, font: boldFont),
                            _cell('الإجمالي', bold: true, align: pw.Alignment.centerLeft, font: boldFont),
                          ],
                        ),
                        ...r.invoice.items.map(
                          (item) => pw.TableRow(
                            children: [
                              _cell(item.productName, font: baseFont),
                              _cell('${item.quantity}', align: pw.Alignment.center, font: baseFont),
                              _cell(item.unitPrice.toStringAsFixed(0), align: pw.Alignment.center, font: baseFont),
                              _cell(item.lineTotal.toStringAsFixed(0), align: pw.Alignment.centerLeft, bold: true, font: baseFont),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
          pw.SizedBox(height: 12),
          pw.Center(
            child: pw.Text(
              'شكراً لتعاملكم معنا ★ نسعد بخدمتكم دائماً',
              style: pw.TextStyle(
                font: baseFont,
                fontSize: 9,
                color: PdfColors.grey600,
              ),
            ),
          ),
        ],
      ),
    );

    return doc.save();
  }

  /// طباعة كشف حساب العميل (حوار الطباعة، وبديل: مشاركة PDF).
  static Future<void> printStatement({
    required CustomerStatement statement,
    String? storeName,
    String? storeLogoPath,
  }) async {
    await Printing.layoutPdf(
      name: 'كشف_حساب_${statement.customer.name}',
      format: PdfPageFormat.a4,
      onLayout: (_) => buildStatementPdf(
        statement: statement,
        storeName: storeName,
        storeLogoPath: storeLogoPath,
      ),
    );
  }

  /// مشاركة كشف الحساب كـ PDF.
  static Future<void> shareStatement({
    required CustomerStatement statement,
    String? storeName,
    String? storeLogoPath,
  }) async {
    final bytes = await buildStatementPdf(
      statement: statement,
      storeName: storeName,
      storeLogoPath: storeLogoPath,
    );
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'كشف_حساب_${statement.customer.name}.pdf',
    );
  }

  static pw.Widget _summaryCard(
    String title,
    String value,
    dynamic color,
    pw.Font baseFont,
    pw.Font boldFont,
  ) {
    return pw.Expanded(
      child: pw.Container(
        margin: const pw.EdgeInsets.symmetric(horizontal: 2.5),
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 7),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey400, width: 0.6),
          borderRadius: pw.BorderRadius.circular(6),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              title,
              maxLines: 1,
              style: pw.TextStyle(
                font: baseFont,
                fontSize: 8.5,
                color: PdfColors.grey700,
              ),
            ),
            pw.SizedBox(height: 3),
            pw.Text(
              value,
              style: pw.TextStyle(
                font: boldFont,
                fontSize: 11,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static pw.Widget _cell(
    String text, {
    bool bold = false,
    pw.Alignment? align,
    dynamic color,
    pw.Font? font,
  }) {
    final style = pw.TextStyle(
      font: font,
      fontSize: 8.5,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      color: color ?? PdfColors.black,
    );
    final t = pw.Text(text, style: style);
    if (align == null) {
      return pw.Padding(padding: const pw.EdgeInsets.all(5), child: t);
    }
    return pw.Padding(
      padding: const pw.EdgeInsets.all(5),
      child: pw.Align(alignment: align, child: t),
    );
  }
}
