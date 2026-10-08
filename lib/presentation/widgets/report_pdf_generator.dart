import 'dart:io';
import 'dart:typed_data';

import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../../core/constants/app_constants.dart';
import '../../data/repositories/report_repository.dart';

class ReportPdfGenerator {
  /// تحميل بيانات شعار المحل (إن وُجد) لتحويلها لـ PdfImage داخل الوثيقة.
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

  /// تحويل بايتات الصورة إلى مزود صورة آمن للوثيقة.
  static pw.ImageProvider? _logoProvider(Uint8List bytes) {
    try {
      return pw.MemoryImage(bytes);
    } catch (_) {
      return null;
    }
  }

  static Future<void> generateAndShareReport({
    required PeriodReportSummary report,
    required DateTime startDate,
    required DateTime endDate,
    String? storeName,
    String? storeLogoPath,
  }) async {
    final logoBytes = await _loadLogoBytes(storeLogoPath);
    final doc = pw.Document();
    final logo = logoBytes != null ? _logoProvider(logoBytes) : null;
    final dateFmt = DateFormat('yyyy/MM/dd');
    final periodText = '${dateFmt.format(startDate)} - ${dateFmt.format(endDate)}';

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Row(
                      children: [
                        if (logo != null) ...[
                          pw.Image(logo, width: 36, height: 36),
                          pw.SizedBox(width: 8),
                        ],
                        pw.Text(
                          (storeName?.trim().isNotEmpty == true)
                              ? storeName!.trim()
                              : AppStrings.STORE_NAME,
                          style: pw.TextStyle(
                            fontSize: 18,
                            fontWeight: pw.FontWeight.bold,
                          ),
                          textDirection: pw.TextDirection.rtl,
                        ),
                      ],
                    ),
                    pw.Text(
                      'تقرير مالي',
                      style: pw.TextStyle(
                        fontSize: 16,
                        fontWeight: pw.FontWeight.bold,
                      ),
                      textDirection: pw.TextDirection.rtl,
                    ),
                  ],
                ),
                pw.SizedBox(height: 8),
                pw.Text(
                  'الفترة: $periodText',
                  style: pw.TextStyle(fontSize: 12),
                  textDirection: pw.TextDirection.rtl,
                ),
                pw.Divider(height: 20, thickness: 1),

                pw.GridView(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 2.5,
                  children: [
                    _buildMetricCard(
                      'صافي المبيعات',
                      AppStrings.money(report.netSales),
                      PdfColors.green500,
                    ),
                    _buildMetricCard(
                      'عدد الفواتير',
                      '${report.totalInvoices}',
                      PdfColors.blue,
                    ),
                    _buildMetricCard(
                      'صافي الأرباح',
                      AppStrings.money(report.totalProfit),
                      PdfColors.green500,
                    ),
                    _buildMetricCard(
                      'إجمالي المشتريات',
                      AppStrings.money(report.totalPurchases),
                      PdfColors.blue,
                    ),
                    _buildMetricCard(
                      'إجمالي المرتجعات',
                      AppStrings.money(report.totalReturns),
                      PdfColors.orange500,
                    ),
                    _buildMetricCard(
                      'المصروفات',
                      AppStrings.money(report.totalExpenses),
                      PdfColors.orange500,
                    ),
                    _buildMetricCard(
                      'الربح بعد المصروفات',
                      AppStrings.money(report.netProfitAfterExpenses),
                      report.netProfitAfterExpenses >= 0
                          ? PdfColors.green500
                          : PdfColors.red,
                    ),
                  ],
                ),
                pw.SizedBox(height: 24),

                pw.Text(
                  'صافي المبيعات = إجمالي المبيعات (${report.totalSales.toStringAsFixed(0)}) − إجمالي المرتجعات (${report.totalReturns.toStringAsFixed(0)})',
                  style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
                  textDirection: pw.TextDirection.rtl,
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  'الربح بعد المصروفات = صافي أرباح المبيعات (${report.totalProfit.toStringAsFixed(0)}) − المصروفات (${report.totalExpenses.toStringAsFixed(0)})',
                  style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
                  textDirection: pw.TextDirection.rtl,
                ),
                pw.SizedBox(height: 24),

                pw.Text(
                  'أفضل المنتجات مبيعاً',
                  style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                  ),
                  textDirection: pw.TextDirection.rtl,
                ),
                pw.SizedBox(height: 8),
                if (report.topSellingProducts.isEmpty)
                  pw.Text(
                    'لا توجد مبيعات مسجلة في هذه الفترة',
                    style: const pw.TextStyle(fontSize: 11),
                    textDirection: pw.TextDirection.rtl,
                  )
                else
                  pw.Table(
                    border: pw.TableBorder.all(color: PdfColors.grey),
                    columnWidths: {
                      0: const pw.FlexColumnWidth(4),
                      1: const pw.FlexColumnWidth(2),
                      2: const pw.FlexColumnWidth(2),
                      3: const pw.FlexColumnWidth(2),
                    },
                    children: [
                      pw.TableRow(
                        decoration:
                            const pw.BoxDecoration(color: PdfColors.grey),
                        children: [
                          _arabicTableText('اسم المنتج', bold: true),
                          _arabicTableText('الكمية', bold: true),
                          _arabicTableText('إجمالي المبيعات', bold: true),
                          _arabicTableText('الربح', bold: true),
                        ],
                      ),
                      ...report.topSellingProducts.map((p) {
                        return pw.TableRow(
                          children: [
                            _arabicTableText(p.productName),
                            _arabicTableText('${p.totalQuantity}'),
                            _arabicTableText(
                                AppStrings.money(p.totalSales)),
                            _arabicTableText(
                                AppStrings.money(p.totalProfit)),
                          ],
                        );
                      }),
                    ],
                  ),
              ],
            ),
          );
        },
      ),
    );

    final bytes = await doc.save();
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'تقرير_${dateFmt.format(startDate)}.pdf',
    );
  }

  static pw.Widget _buildMetricCard(String title, String value, dynamic color) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        mainAxisAlignment: pw.MainAxisAlignment.center,
        children: [
          pw.Text(
            title,
            style: const pw.TextStyle(fontSize: 11),
            textDirection: pw.TextDirection.rtl,
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
              color: color,
            ),
            textDirection: pw.TextDirection.rtl,
          ),
        ],
      ),
    );
  }

  static pw.Widget _arabicTableText(String text, {bool bold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(8),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 11,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
        textDirection: pw.TextDirection.rtl,
      ),
    );
  }
}
