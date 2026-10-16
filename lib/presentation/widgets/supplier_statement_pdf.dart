import 'dart:io';

import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';

import '../../core/constants/app_constants.dart';
import '../../core/services/document_share_service.dart';
import '../../core/services/printer_settings_service.dart';
import '../../data/repositories/supplier_repository.dart';

/// طباعة كشف حساب المورد (A4) بتصميم احترافي قابل للتجزئة عبر عدة صفحات دون تهنيج.
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

  /// بناء PDF كشف حساب المورد.
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
                    'كشف حساب مورد',
                    style: pw.TextStyle(
                      font: boldFont,
                      fontSize: 15,
                      color: PdfColors.blueGrey800,
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 4),
              pw.Divider(height: 12, thickness: 0.8, color: PdfColors.grey400),
              pw.SizedBox(height: 4),
            ],
          );
        },
        footer: (context) {
          return pw.Column(
            children: [
              pw.Divider(height: 8, thickness: 0.5, color: PdfColors.grey300),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'صفحة ${context.pageNumber} من ${context.pagesCount}',
                    style: pw.TextStyle(font: baseFont, fontSize: 8, color: PdfColors.grey600),
                  ),
                  pw.Text(
                    'تاريخ الطباعة: ${dateFmt.format(DateTime.now())} - ${timeFmt.format(DateTime.now())}',
                    style: pw.TextStyle(font: baseFont, fontSize: 8, color: PdfColors.grey600),
                  ),
                ],
              ),
            ],
          );
        },
        build: (context) => [
          // 1. بطاقة معلومات المورد
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey100,
              borderRadius: pw.BorderRadius.circular(6),
              border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.RichText(
                      text: pw.TextSpan(
                        children: [
                          pw.TextSpan(
                            text: 'اسم المورد: ',
                            style: pw.TextStyle(font: boldFont, fontSize: 11),
                          ),
                          pw.TextSpan(
                            text: s.name,
                            style: pw.TextStyle(font: boldFont, fontSize: 12, color: PdfColors.blueGrey900),
                          ),
                        ],
                      ),
                    ),
                    if (s.phone != null && s.phone!.isNotEmpty) ...[
                      pw.SizedBox(height: 3),
                      pw.Text(
                        'رقم الهاتف: ${s.phone}',
                        style: pw.TextStyle(font: baseFont, fontSize: 9.5, color: PdfColors.grey700),
                      ),
                    ],
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      'كشف الحساب الشامل',
                      style: pw.TextStyle(font: boldFont, fontSize: 10, color: PdfColors.grey800),
                    ),
                    pw.SizedBox(height: 3),
                    pw.Text(
                      'عدد العمليات: ${entries.length}',
                      style: pw.TextStyle(font: baseFont, fontSize: 9.5, color: PdfColors.grey700),
                    ),
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 10),

          // 2. كروت ملخص المؤشرات المالية
          pw.Row(
            children: [
              pw.Expanded(
                child: _summaryBox(
                  title: 'إجمالي المشتريات',
                  value: AppStrings.money(statement.totalPurchases),
                  color: PdfColors.blue800,
                  baseFont: baseFont,
                  boldFont: boldFont,
                ),
              ),
              pw.SizedBox(width: 6),
              if (statement.totalReturns > 0.005) ...[
                pw.Expanded(
                  child: _summaryBox(
                    title: 'إجمالي المرتجعات',
                    value: AppStrings.money(statement.totalReturns),
                    color: PdfColors.orange800,
                    baseFont: baseFont,
                    boldFont: boldFont,
                  ),
                ),
                pw.SizedBox(width: 6),
              ],
              pw.Expanded(
                child: _summaryBox(
                  title: 'إجمالي الدفعات المسددة',
                  value: AppStrings.money(statement.totalPayments),
                  color: PdfColors.green800,
                  baseFont: baseFont,
                  boldFont: boldFont,
                ),
              ),
              pw.SizedBox(width: 6),
              pw.Expanded(
                child: _summaryBox(
                  title: 'الرصيد المستحق للمورد',
                  value: AppStrings.money(s.balanceOwed),
                  color: s.hasOwed ? PdfColors.red800 : PdfColors.green800,
                  highlight: true,
                  baseFont: baseFont,
                  boldFont: boldFont,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 14),

          // 3. جدول العمليات (Splittable Table - يتوزع بسلاسة على الصفحات)
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
            defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
            columnWidths: {
              0: const pw.FixedColumnWidth(28), // م
              1: const pw.FixedColumnWidth(70), // التاريخ
              2: const pw.FlexColumnWidth(4.5), // البيان
              3: const pw.FlexColumnWidth(2),   // مدين (شراء)
              4: const pw.FlexColumnWidth(2),   // دائن (سداد)
              5: const pw.FlexColumnWidth(2.2), // الرصيد
            },
            children: [
              // رأس الجدول
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  _cell('م', bold: true, align: pw.Alignment.center, font: boldFont),
                  _cell('التاريخ', bold: true, align: pw.Alignment.center, font: boldFont),
                  _cell('البيان والعملية', bold: true, font: boldFont),
                  _cell('مدين (شراء)', bold: true, align: pw.Alignment.centerLeft, font: boldFont),
                  _cell('دائن (سداد)', bold: true, align: pw.Alignment.centerLeft, font: boldFont),
                  _cell('الرصيد', bold: true, align: pw.Alignment.centerLeft, font: boldFont),
                ],
              ),

              if (entries.isEmpty)
                pw.TableRow(
                  children: [
                    _cell('-', align: pw.Alignment.center, font: baseFont),
                    _cell('-', align: pw.Alignment.center, font: baseFont),
                    _cell('لا توجد أي حركات أو فواتير مسجلة للمورد حتى الآن', font: baseFont),
                    _cell('—', align: pw.Alignment.centerLeft, font: baseFont),
                    _cell('—', align: pw.Alignment.centerLeft, font: baseFont),
                    _cell(AppStrings.money(s.balanceOwed), align: pw.Alignment.centerLeft, font: boldFont),
                  ],
                )
              else
                ...entries.asMap().entries.map((entry) {
                  final idx = entry.key + 1;
                  final e = entry.value;
                  final isEven = entry.key.isEven;
                  final isPositiveBalance = e.runningBalance > 0.005;

                  return pw.TableRow(
                    decoration: pw.BoxDecoration(
                      color: isEven ? PdfColors.white : PdfColors.grey50,
                    ),
                    children: [
                      _cell('$idx', align: pw.Alignment.center, font: baseFont, fontSize: 8.5),
                      _cell(dateFmt.format(e.date), align: pw.Alignment.center, font: baseFont, fontSize: 8.5),
                      _cell(e.title, font: baseFont, fontSize: 9),
                      _cell(
                        e.isPurchase ? AppStrings.money(e.amount) : '—',
                        align: pw.Alignment.centerLeft,
                        font: baseFont,
                        fontSize: 8.5,
                        color: e.isPurchase ? PdfColors.blue800 : PdfColors.black,
                      ),
                      _cell(
                        e.isPurchase ? '—' : AppStrings.money(e.amount),
                        align: pw.Alignment.centerLeft,
                        font: baseFont,
                        fontSize: 8.5,
                        color: !e.isPurchase ? PdfColors.green800 : PdfColors.black,
                      ),
                      _cell(
                        AppStrings.money(e.runningBalance),
                        align: pw.Alignment.centerLeft,
                        font: boldFont,
                        fontSize: 8.5,
                        color: isPositiveBalance ? PdfColors.red800 : PdfColors.green800,
                      ),
                    ],
                  );
                }),

              // صف الإجماليات
              if (entries.isNotEmpty)
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    _cell('', align: pw.Alignment.center, font: boldFont),
                    _cell('', align: pw.Alignment.center, font: boldFont),
                    _cell('الإجمالي العام المستحق', bold: true, font: boldFont, fontSize: 9.5),
                    _cell(
                      AppStrings.money(statement.totalPurchases),
                      bold: true,
                      align: pw.Alignment.centerLeft,
                      font: boldFont,
                      fontSize: 9,
                      color: PdfColors.blue900,
                    ),
                    _cell(
                      AppStrings.money(statement.totalPayments),
                      bold: true,
                      align: pw.Alignment.centerLeft,
                      font: boldFont,
                      fontSize: 9,
                      color: PdfColors.green900,
                    ),
                    _cell(
                      AppStrings.money(s.balanceOwed),
                      bold: true,
                      align: pw.Alignment.centerLeft,
                      font: boldFont,
                      fontSize: 9.5,
                      color: s.hasOwed ? PdfColors.red800 : PdfColors.green800,
                    ),
                  ],
                ),
            ],
          ),

          pw.SizedBox(height: 20),

          // 4. التوقيعات الرسمية والملاحظات
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Text('المحاسب / إدارة المشتريات', style: pw.TextStyle(font: boldFont, fontSize: 9.5)),
                  pw.SizedBox(height: 32),
                  pw.Container(width: 140, height: 0.5, color: PdfColors.grey600),
                  pw.SizedBox(height: 3),
                  pw.Text('التوقيع والختم', style: pw.TextStyle(font: baseFont, fontSize: 8, color: PdfColors.grey600)),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Text('المورد / المستلم', style: pw.TextStyle(font: boldFont, fontSize: 9.5)),
                  pw.SizedBox(height: 32),
                  pw.Container(width: 140, height: 0.5, color: PdfColors.grey600),
                  pw.SizedBox(height: 3),
                  pw.Text('التوقيع والمصادقة', style: pw.TextStyle(font: baseFont, fontSize: 8, color: PdfColors.grey600)),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 12),
          pw.Center(
            child: pw.Text(
              'نشكركم لحسن تعاونكم معنا — تم إصدار هذا المستند عبر نظام ${AppStrings.STORE_NAME}',
              style: pw.TextStyle(font: baseFont, fontSize: 8, color: PdfColors.grey600),
            ),
          ),
        ],
      ),
    );

    return doc.save();
  }

  /// طباعة كشف الحساب.
  static Future<void> printStatement({
    required SupplierStatement statement,
    String? storeName,
    String? storeLogoPath,
  }) async {
    await PrinterSettingsService.printDocument(
      name: 'كشف_حساب_${statement.supplier.name}',
      format: PdfPageFormat.a4,
      onLayout: (_) => buildStatementPdf(
        statement: statement,
        storeName: storeName,
        storeLogoPath: storeLogoPath,
      ),
    );
  }

  /// مشاركة كشف الحساب كصورة عالية الدقة (PNG) لتطبيقات التواصل (واتساب، فيسبوك، إلخ).
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
    await DocumentShareService.sharePdfAsImage(
      pdfBytes: bytes,
      filename: 'كشف_حساب_${statement.supplier.name}',
    );
  }

  static pw.Widget _summaryBox({
    required String title,
    required String value,
    required PdfColor color,
    required pw.Font baseFont,
    required pw.Font boldFont,
    bool highlight = false,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: pw.BoxDecoration(
        color: highlight ? PdfColors.grey100 : PdfColors.white,
        borderRadius: pw.BorderRadius.circular(6),
        border: pw.Border.all(
          color: highlight ? color : PdfColors.grey300,
          width: highlight ? 1.0 : 0.5,
        ),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            title,
            style: pw.TextStyle(font: baseFont, fontSize: 8.5, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 3),
          pw.Text(
            value,
            style: pw.TextStyle(font: boldFont, fontSize: 11, color: color),
          ),
        ],
      ),
    );
  }

  static pw.Widget _cell(
    String text, {
    bool bold = false,
    pw.Alignment? align,
    PdfColor? color,
    required pw.Font font,
    double fontSize = 9,
  }) {
    final style = pw.TextStyle(
      font: font,
      fontSize: fontSize,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      color: color ?? PdfColors.black,
    );
    final t = pw.Text(text, style: style);
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
      child: align != null ? pw.Align(alignment: align, child: t) : t,
    );
  }
}
