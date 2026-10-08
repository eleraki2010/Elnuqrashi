import 'dart:io';

import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../../core/constants/app_constants.dart';
import '../../data/repositories/supplier_repository.dart';

/// طباعة كشف حساب المورد (A4) — شامل كل عملياته (شراء + دفعات)
/// مع رصيد دائري بعد كل بيان.
class SupplierStatementPdf {
  static Future<pw.Font> _loadFont(String asset) async {
    final data = await rootBundle.load(asset);
    return pw.Font.ttf(data);
  }

  static Future<Uint8List?> _loadLogoBytes(String? storeLogoPath) async {
    if (storeLogoPath == null || storeLogoPath.isEmpty) return null;
    try {
      final file = File(storeLogoPath);
      if (!file.existsSync()) return null;
      final bytes = await file.readAsBytes();
      return bytes;
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

  /// بناء PDF كشف الحساب.
  static Future<Uint8List> buildStatementPdf({
    required SupplierStatement statement,
    String? storeName,
    String? storeLogoPath,
  }) async {
    final baseFont = await _loadFont('fonts/Cairo-Regular.ttf');
    final boldFont = await _loadFont('fonts/Cairo-Bold.ttf');
    final logoBytes = await _loadLogoBytes(storeLogoPath);
    final logo = logoBytes != null ? _logoProvider(logoBytes) : null;

    final dateFmt = DateFormat('yyyy/MM/dd');
    final timeFmt = DateFormat('hh:mm a');
    final entries = statement.buildEntries();
    final s = statement.supplier;

    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (context) {
          return pw.Theme(
            data: pw.ThemeData.withFont(base: baseFont, bold: boldFont),
            child: pw.Directionality(
              textDirection: pw.TextDirection.rtl,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  // الترويسة: الشعار + اسم المحل (بجواره) | عنوان المستند
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Row(
                        mainAxisSize: pw.MainAxisSize.min,
                        children: [
                          if (logo != null) ...[
                            pw.Image(logo, width: 38, height: 38),
                            pw.SizedBox(width: 8),
                          ],
                          pw.Text(
                            (storeName?.trim().isNotEmpty == true)
                                ? storeName!.trim()
                                : AppStrings.STORE_NAME,
                            style: pw.TextStyle(font: boldFont, fontSize: 16),
                          ),
                        ],
                      ),
                      pw.Text(
                        'كشف حساب مورد',
                        style: pw.TextStyle(
                          font: boldFont,
                          fontSize: 15,
                          color: PdfColors.grey700,
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 4),
                  pw.Divider(height: 18, thickness: 1),

                  // بيانات المورد والتاريخ
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'المورد: ${s.name}',
                            style: pw.TextStyle(font: boldFont, fontSize: 12),
                          ),
                          if (s.phone != null && s.phone!.isNotEmpty)
                            pw.Text(
                              'هاتف: ${s.phone}',
                              style: pw.TextStyle(
                                font: baseFont,
                                fontSize: 10,
                                color: PdfColors.grey700,
                              ),
                            ),
                        ],
                      ),
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          pw.Text(
                            'تاريخ الإصدار: ${dateFmt.format(DateTime.now())} - ${timeFmt.format(DateTime.now())}',
                            style: pw.TextStyle(
                              font: baseFont,
                              fontSize: 10,
                              color: PdfColors.grey700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 12),

                  // ملخص الأرصدة
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      _summaryCard(
                        'إجمالي المشتريات',
                        AppStrings.money(statement.totalPurchases),
                        PdfColors.blue,
                        baseFont,
                        boldFont,
                      ),
                      _summaryCard(
                        'إجمالي الدفعات',
                        AppStrings.money(statement.totalPayments),
                        PdfColors.green500,
                        baseFont,
                        boldFont,
                      ),
                      _summaryCard(
                        'الرصيد المستحق للمورد',
                        AppStrings.money(s.balanceOwed),
                        s.hasOwed ? PdfColors.orange500 : PdfColors.green500,
                        baseFont,
                        boldFont,
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 16),

                  // جدول العمليات: التاريخ | البيان | مدين | دائن | الرصيد
                  pw.Table(
                    border: pw.TableBorder.all(
                      color: PdfColors.grey,
                      width: 0.5,
                    ),
                    defaultVerticalAlignment:
                        pw.TableCellVerticalAlignment.middle,
                    columnWidths: {
                      0: const pw.FlexColumnWidth(2),
                      1: const pw.FlexColumnWidth(4),
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
                            'مدين (شراء)',
                            bold: true,
                            align: pw.Alignment.centerLeft,
                            font: boldFont,
                          ),
                          _cell(
                            'دائن (سداد)',
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
                      if (entries.isEmpty)
                        pw.TableRow(
                          children: List.filled(
                            5,
                            _cell(
                              'لا توجد عمليات مسجلة',
                              align: pw.Alignment.center,
                              font: baseFont,
                            ),
                          ),
                        )
                      else
                        ...entries.map((e) {
                          final dateText = dateFmt.format(e.date);
                          return pw.TableRow(
                            children: [
                              _cell(dateText, font: baseFont),
                              _cell(e.title, font: baseFont),
                              _cell(
                                e.isPurchase ? AppStrings.money(e.amount) : '—',
                                align: pw.Alignment.centerLeft,
                                font: baseFont,
                              ),
                              _cell(
                                e.isPurchase ? '—' : AppStrings.money(e.amount),
                                align: pw.Alignment.centerLeft,
                                font: baseFont,
                              ),
                              _cell(
                                AppStrings.money(e.runningBalance),
                                align: pw.Alignment.centerLeft,
                                font: baseFont,
                                color: e.runningBalance > 0.005
                                    ? PdfColors.orange500
                                    : PdfColors.green500,
                              ),
                            ],
                          );
                        }),
                      if (entries.isNotEmpty)
                        pw.TableRow(
                          decoration: const pw.BoxDecoration(
                            color: PdfColors.grey200,
                          ),
                          children: [
                            _cell('الإجمالي', bold: true, font: boldFont),
                            _cell('', font: baseFont),
                            _cell(
                              AppStrings.money(statement.totalPurchases),
                              bold: true,
                              align: pw.Alignment.centerLeft,
                              font: boldFont,
                            ),
                            _cell(
                              AppStrings.money(statement.totalPayments),
                              bold: true,
                              align: pw.Alignment.centerLeft,
                              font: boldFont,
                            ),
                            _cell(
                              AppStrings.money(s.balanceOwed),
                              bold: true,
                              align: pw.Alignment.centerLeft,
                              font: boldFont,
                              color: s.hasOwed
                                  ? PdfColors.orange500
                                  : PdfColors.green500,
                            ),
                          ],
                        ),
                    ],
                  ),
                  pw.SizedBox(height: 16),
                  pw.Center(
                    child: pw.Text(
                      'شكراً لتعاملكم معنا — ${AppStrings.STORE_NAME}',
                      style: pw.TextStyle(
                        font: baseFont,
                        fontSize: 9,
                        color: PdfColors.grey600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    return doc.save();
  }

  /// طباعة كشف الحساب (يفتح حوار الطباعة/المشاركة حسب النظام).
  static Future<void> printStatement({
    required SupplierStatement statement,
    String? storeName,
    String? storeLogoPath,
  }) async {
    await Printing.layoutPdf(
      name: 'كشف_حساب_${statement.supplier.name}',
      format: PdfPageFormat.a4,
      onLayout: (_) => buildStatementPdf(
        statement: statement,
        storeName: storeName,
        storeLogoPath: storeLogoPath,
      ),
    );
  }

  /// مشاركة كشف الحساب كـ PDF (بديل عن الطباعة المباشرة).
  static Future<void> shareStatement({
    required SupplierStatement statement,
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
      filename: 'كشف_حساب_${statement.supplier.name}.pdf',
    );
  }

  static pw.Widget _summaryCard(
    String title,
    String value,
    dynamic color,
    pw.Font baseFont,
    pw.Font boldFont,
  ) {
    return pw.Container(
      width: 150,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            title,
            style: pw.TextStyle(
              font: baseFont,
              fontSize: 10,
              color: PdfColors.grey700,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            value,
            style: pw.TextStyle(font: boldFont, fontSize: 13, color: color),
          ),
        ],
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
      fontSize: 10,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      color: color ?? PdfColors.black,
    );
    final t = pw.Text(text, style: style);
    if (align == null) {
      return pw.Padding(padding: const pw.EdgeInsets.all(6), child: t);
    }
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Align(alignment: align, child: t),
    );
  }
}
