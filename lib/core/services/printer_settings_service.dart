import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/repositories/shop_profile_repository.dart';
import '../constants/app_constants.dart';

/// إدارة إعدادات الطابعات وتكاملها مع أجهزة التابلت والكمبيوتر (Modern Tablet-ready POS Printing).
class PrinterSettingsService {
  static const String keyPrinterUrl = 'pref_printer_url';
  static const String keyPrinterName = 'pref_printer_name';
  static const String keyPrinterModel = 'pref_printer_model';
  static const String keyPrinterLocation = 'pref_printer_location';
  static const String keyPaperSize = 'pref_printer_paper_size'; // '80mm', '58mm', 'a4'
  static const String keyDirectPrint = 'pref_printer_direct_print'; // bool

  /// استرجاع الطابعة المحفوظة حالياً (إن وُجدت).
  static Future<Printer?> getSavedPrinter() async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString(keyPrinterUrl);
    final name = prefs.getString(keyPrinterName);
    if (url == null || url.isEmpty || name == null || name.isEmpty) {
      return null;
    }
    return Printer(
      url: url,
      name: name,
      model: prefs.getString(keyPrinterModel),
      location: prefs.getString(keyPrinterLocation),
    );
  }

  /// حفظ الطابعة المختارة كطابعة افتراضية للتطبيق.
  static Future<void> savePrinter(Printer printer) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyPrinterUrl, printer.url);
    await prefs.setString(keyPrinterName, printer.name);
    if (printer.model != null && printer.model!.isNotEmpty) {
      await prefs.setString(keyPrinterModel, printer.model!);
    } else {
      await prefs.remove(keyPrinterModel);
    }
    if (printer.location != null && printer.location!.isNotEmpty) {
      await prefs.setString(keyPrinterLocation, printer.location!);
    } else {
      await prefs.remove(keyPrinterLocation);
    }
  }

  /// حفظ طابعة مخصصة يدوياً (مثل طابعات الشبكة IP أو اسم الطابعة).
  static Future<void> saveCustomPrinter({
    required String name,
    required String url,
    String? model,
    String? location,
  }) async {
    final printer = Printer(
      url: url.trim(),
      name: name.trim(),
      model: model?.trim(),
      location: location?.trim(),
    );
    await savePrinter(printer);
  }

  /// مسح الطابعة المحفوظة والرجوع للاختيار التلقائي من النظام.
  static Future<void> clearSavedPrinter() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(keyPrinterUrl);
    await prefs.remove(keyPrinterName);
    await prefs.remove(keyPrinterModel);
    await prefs.remove(keyPrinterLocation);
  }

  /// مقاس الورق الافتراضي (80mm, 58mm, a4).
  static Future<String> getPaperSize() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(keyPaperSize) ?? '80mm';
  }

  /// حفظ مقاس الورق الافتراضي.
  static Future<void> setPaperSize(String size) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyPaperSize, size);
  }

  /// هل الطباعة المباشرة السريعة (بدون إظهار نافذة الحوار) مفعلة؟
  static Future<bool> isDirectPrint() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(keyDirectPrint) ?? false;
  }

  /// تفعيل أو تعطيل الطباعة المباشرة السريعة.
  static Future<void> setDirectPrint(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(keyDirectPrint, value);
  }

  /// البحث عن الطابعات المتوفرة على التابلت أو الجهاز (بلوتوث، شبكة، USB، طابعات النظام).
  static Future<List<Printer>> discoverPrinters() async {
    try {
      final list = await Printing.listPrinters();
      return list;
    } catch (e) {
      debugPrint('Error discovering printers: $e');
      return [];
    }
  }

  /// طباعة مستند (PDF) مع احترام إعدادات الطابعة والطباعة المباشرة.
  static Future<bool> printDocument({
    required Future<Uint8List> Function(PdfPageFormat format) onLayout,
    required String name,
    PdfPageFormat? format,
  }) async {
    final savedPrinter = await getSavedPrinter();
    final direct = await isDirectPrint();

    if (direct && savedPrinter != null) {
      try {
        final success = await Printing.directPrintPdf(
          printer: savedPrinter,
          onLayout: onLayout,
          name: name,
          format: format ?? PdfPageFormat.roll80,
          usePrinterSettings: true,
        );
        if (success) return true;
      } catch (e) {
        debugPrint('Direct print failed, falling back to layoutPdf: $e');
      }
    }

    return await Printing.layoutPdf(
      onLayout: onLayout,
      name: name,
      format: format ?? PdfPageFormat.roll80,
      usePrinterSettings: true,
    );
  }

  /// طباعة صفحة تجريبية لاختبار الطابعة وضبطها فورياً.
  static Future<bool> printTestReceipt(BuildContext context) async {
    final savedPrinter = await getSavedPrinter();
    final paperSize = await getPaperSize();
    final is80mm = paperSize != '58mm';

    // تحميل الخطوط والشعار
    pw.Font baseFont;
    pw.Font boldFont;
    try {
      final baseData = await rootBundle.load('fonts/Cairo-Regular.ttf');
      final boldData = await rootBundle.load('fonts/Cairo-Bold.ttf');
      baseFont = pw.Font.ttf(baseData);
      boldFont = pw.Font.ttf(boldData);
    } catch (_) {
      baseFont = pw.Font.helvetica();
      boldFont = pw.Font.helveticaBold();
    }

    String storeName = AppStrings.DEFAULT_STORE_NAME;
    String? storePhone;
    pw.ImageProvider? logoProvider;
    try {
      final prefs = await SharedPreferences.getInstance();
      storeName = prefs.getString('store_name') ?? storeName;
      storePhone = prefs.getString('store_phone');

      final profile = await ShopProfileRepository().getProfile();
      if (profile.logoPath != null) {
        final file = File(profile.logoPath!);
        if (file.existsSync()) {
          logoProvider = pw.MemoryImage(await file.readAsBytes());
        }
      }
    } catch (_) {}

    final now = DateTime.now();
    final dateStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    final widthPt = is80mm ? 80 * PdfPageFormat.mm : 57 * PdfPageFormat.mm;
    final paperFormat = PdfPageFormat(widthPt, double.infinity, marginAll: 0);

    return await printDocument(
      name: 'تجربة_طباعة',
      format: paperFormat,
      onLayout: (requestedFormat) async {
        final doc = pw.Document();

        doc.addPage(
          pw.Page(
            pageFormat: PdfPageFormat(widthPt, double.infinity, marginAll: 8),
            theme: pw.ThemeData.withFont(base: baseFont, bold: boldFont),
            textDirection: pw.TextDirection.rtl,
            build: (pw.Context ctx) {
              return pw.Column(
                mainAxisSize: pw.MainAxisSize.min,
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  if (logoProvider != null) ...[
                    pw.Container(
                      height: 48,
                      width: 48,
                      alignment: pw.Alignment.center,
                      child: pw.Image(logoProvider),
                    ),
                    pw.SizedBox(height: 6),
                  ],
                  pw.Text(
                    storeName,
                    style: pw.TextStyle(
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                    ),
                    textAlign: pw.TextAlign.center,
                  ),
                  if (storePhone != null && storePhone.isNotEmpty) ...[
                    pw.SizedBox(height: 2),
                    pw.Text(
                      'هاتف: $storePhone',
                      style: const pw.TextStyle(fontSize: 9),
                      textDirection: pw.TextDirection.ltr,
                    ),
                  ],
                  pw.SizedBox(height: 6),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                        vertical: 3, horizontal: 8),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(width: 0.8),
                      borderRadius:
                          const pw.BorderRadius.all(pw.Radius.circular(4)),
                    ),
                    child: pw.Text(
                      'اختبار نجاح إعدادات الطباعة',
                      style: pw.TextStyle(
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                  pw.SizedBox(height: 8),
                  pw.Divider(thickness: 0.5),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('الطابعة المستخدمة:',
                          style: const pw.TextStyle(fontSize: 8)),
                      pw.Expanded(
                        child: pw.Text(
                          savedPrinter?.name ?? 'طابعة النظام الافتراضية',
                          style: pw.TextStyle(
                            fontSize: 8,
                            fontWeight: pw.FontWeight.bold,
                          ),
                          textAlign: pw.TextAlign.left,
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 3),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('مقاس الورق:',
                          style: const pw.TextStyle(fontSize: 8)),
                      pw.Text(
                        is80mm ? '80 مم (حراري)' : '58 مم (حراري)',
                        style: pw.TextStyle(
                          fontSize: 8,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 3),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('التاريخ والوقت:',
                          style: const pw.TextStyle(fontSize: 8)),
                      pw.Text(dateStr,
                          style: const pw.TextStyle(fontSize: 8),
                          textDirection: pw.TextDirection.ltr),
                    ],
                  ),
                  pw.Divider(thickness: 0.5),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'تم الاتصال بالطابعة وإعدادها بنجاح!',
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                    ),
                    textAlign: pw.TextAlign.center,
                  ),
                  pw.SizedBox(height: 8),
                  pw.BarcodeWidget(
                    barcode: pw.Barcode.code128(),
                    data: 'DOKKAN-TEST',
                    width: widthPt * 0.75,
                    height: 28,
                    drawText: true,
                    textStyle: const pw.TextStyle(fontSize: 8),
                  ),
                  pw.SizedBox(height: 6),
                  pw.Text(
                    '--- نهاية الصفحة التجريبية ---',
                    style: const pw.TextStyle(fontSize: 8),
                  ),
                  pw.SizedBox(height: 10),
                ],
              );
            },
          ),
        );

        return doc.save();
      },
    );
  }
}
