import 'dart:io';

import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/constants/app_constants.dart';
import '../../core/services/document_share_service.dart';
import '../../core/services/printer_settings_service.dart';
import '../../data/models/sale_invoice.dart';

/// نتيجة بناء الإيصال: البايتر + أبعاد الصفحة النهائية (نقطة).
class _BuiltReceipt {
  final Uint8List bytes;
  final double heightPt;
  final double widthPt;

  _BuiltReceipt(this.bytes, this.heightPt, this.widthPt);
}

/// طباعة فاتورة حرارية (Phase 3.14).
///
/// يولّد PDF بمقاس لفة حرارية 58mm أو 80mm، ثم يفتح نافذة الطباعة
/// لاختيار الطابعة (تدعم الطابعات الحرارية عبر نظام التشغيل)،
/// مع مشاركة PDF كبديل.
///
/// مقاس الورق المطلوب = مقاس اللفة المختار (80/58مم): النسخة المحلية
/// من printing (plugins/printing) تطلبه في حوار الطباعة كمقاس مخصص
/// بعدّاته الدقيقة، فلا يسقط الحوار على A4 الافتراضي — وإن غير
/// المستخدم الورقة في الحوار يعاد بناء الوثيقة لتناسبها (تصميم متجاوب
/// في onLayout): حراري → الإيصال على اللفة، وأكبر من 85مم → فاتورة
/// احترافية بمقاس الورقة بالضبط مع تقسيم تلقائي للصفحات الطويلة.
class ThermalReceiptPrinter {
  static Future<pw.Font> _loadFont(String asset) async {
    final data = await rootBundle.load(asset);
    return pw.Font.ttf(data);
  }

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


  /// عرض حراري تقريبي (نقطة): 85مم = 240.6 نقطة. أي عرض مطلوب ≤ 240
  /// يُعامل كلفة حرارية (57/80مم)، وكل ما هو أعرض يُعامل كورقة كبيرة.
  static const double _thermalMaxWidthPt = 240.0;

  static bool _isThermalWidth(double widthPt) =>
      widthPt > 0 && widthPt <= _thermalMaxWidthPt;

  /// حساب الارتفاع الدقيق الفعلي لمحتوى الفاتورة الحرارية بالنقاط (Points).
  /// يمنع تماماً الوقوع في الارتفاع الافتراضي (612pt / Letter) أو مط الفاتورة عمودياً.
  static double _calculateReceiptHeight({
    required SaleInvoice invoice,
    required bool width80mm,
    bool hasLogo = false,
    bool hasPhone = false,
  }) {
    double h = 0.0;
    // هوامش الصفحة والحاوية
    h += 24.0;

    // ترويسة المحل
    if (hasLogo) {
      h += (width80mm ? 30.0 : 24.0) + 4.0;
    } else {
      h += (width80mm ? 16.0 : 14.0);
    }
    if (hasPhone) {
      h += 14.0;
    }
    h += 16.0; // نوع الفاتورة
    h += 12.0; // فاصل

    // بطاقة بيانات الفاتورة
    h += 68.0;

    // جدول الأصناف
    h += 22.0; // عنوان الجدول
    for (final item in invoice.items) {
      final nameLen = (item.productName ?? '').length;
      final maxChars = width80mm ? 22 : 14;
      final extraLines = (nameLen / maxChars).ceil().clamp(1, 4) - 1;
      h += 18.0 + (extraLines * 11.0);
    }
    h += 8.0;

    // بطاقة المبالغ المالية
    int extraRows = 0;
    if (invoice.discount > 0 || invoice.tax > 0) {
      extraRows += 1;
      if (invoice.discount > 0) extraRows += 1;
      if (invoice.tax > 0) extraRows += 1;
      extraRows += 1; // فاصل داخلي
    }
    h += 74.0 + (extraRows * 14.0);
    h += 8.0;

    // الفاصل وتذييل الشكر وسياسة الاسترجاع
    h += 12.0; // فاصل
    h += 14.0; // سياسة الاسترجاع
    h += 16.0; // الشكر
    h += 8.0;

    // باركود الفاتورة
    h += (width80mm ? 22.0 : 18.0) + 16.0 + 6.0;

    // هامش أمان إضافي للخطوط وقص الورق
    h += 24.0;

    return h;
  }

  /// بناء الإيصال بالارتفاع الفعلي التلقائي للوثيقة لضمان طباعة كامل الفاتورة
  /// من البداية وحتى النهاية دون أي اقتصاص أو مط للمحتوى.
  static Future<_BuiltReceipt> _buildReceipt({
    required SaleInvoice invoice,
    required bool width80mm,
    String? storeName,
    String? storePhone,
    String? storeLogoPath,
  }) async {
    final baseFont = await _loadFont('fonts/Cairo-Regular.ttf');
    final boldFont = await _loadFont('fonts/Cairo-Bold.ttf');
    final logoBytes = await _loadLogoBytes(storeLogoPath);
    final logo = logoBytes != null ? _logoProvider(logoBytes) : null;

    final widthPt = width80mm ? 80 * PdfPageFormat.mm : 57 * PdfPageFormat.mm;

    final doc = _buildReceiptDocument(
      invoice: invoice,
      width80mm: width80mm,
      storeName: storeName,
      storePhone: storePhone,
      logo: logo,
      baseFont: baseFont,
      boldFont: boldFont,
    );
    final bytes = await doc.save();
    final heightPt = doc.document.pdfPageList.pages.first.pageFormat.height;

    return _BuiltReceipt(bytes, heightPt, widthPt);
  }

  // لوحة ألوان مطابقة 100% لفاتورة التطبيق (ReceiptDialog)
  static final PdfColor _colorNavy = PdfColor.fromInt(0xFF0F172A);
  static final PdfColor _colorSecondary = PdfColor.fromInt(0xFF64748B);
  static final PdfColor _colorCardBg = PdfColor.fromInt(0xFFF8FAFC);
  static final PdfColor _colorBorder = PdfColor.fromInt(0xFFE2E8F0);
  static final PdfColor _colorTableBorder = PdfColor.fromInt(0xFFCBD5E1);
  static final PdfColor _colorHeaderBg = PdfColor.fromInt(0xFFF1F5F9);
  static final PdfColor _colorPrimaryBlue = PdfColor.fromInt(0xFF1E3A8A);
  static final PdfColor _colorGreenBg = PdfColor.fromInt(0xFFE8F5E9);
  static final PdfColor _colorGreenText = PdfColor.fromInt(0xFF2E7D32);
  static final PdfColor _colorGreenBorder = PdfColor.fromInt(0xFF81C784);
  static final PdfColor _colorAmberBg = PdfColor.fromInt(0xFFFFF8E1);
  static final PdfColor _colorAmberText = PdfColor.fromInt(0xFFF57F17);
  static final PdfColor _colorAmberBorder = PdfColor.fromInt(0xFFFFD54F);
  static final PdfColor _colorRedBg = PdfColor.fromInt(0xFFFFEBEE);
  static final PdfColor _colorRedText = PdfColor.fromInt(0xFFC62828);
  static final PdfColor _colorRedBorder = PdfColor.fromInt(0xFFE57373);

  /// بناء بايتات PDF الإيصال (تُستخدم للمشاركة أو الحفظ).
  static Future<Uint8List> buildReceiptPdf({
    required SaleInvoice invoice,
    required bool width80mm,
    String? storeName,
    String? storePhone,
    String? storeLogoPath,
    bool asCard = false,
  }) async {
    if (!asCard) {
      final built = await _buildReceipt(
        invoice: invoice,
        width80mm: width80mm,
        storeName: storeName,
        storePhone: storePhone,
        storeLogoPath: storeLogoPath,
      );
      return built.bytes;
    }

    final baseFont = await _loadFont('fonts/Cairo-Regular.ttf');
    final boldFont = await _loadFont('fonts/Cairo-Bold.ttf');
    final logoBytes = await _loadLogoBytes(storeLogoPath);
    final logo = logoBytes != null ? _logoProvider(logoBytes) : null;

    final widthPt = width80mm ? 80 * PdfPageFormat.mm : 57 * PdfPageFormat.mm;
    final heightPt = _calculateReceiptHeight(
      invoice: invoice,
      width80mm: width80mm,
      hasLogo: logo != null,
      hasPhone: storePhone != null && storePhone.trim().isNotEmpty,
    );

    final body = _receiptBody(
      invoice: invoice,
      width80mm: width80mm,
      storeName: storeName,
      storePhone: storePhone,
      logo: logo,
      baseFont: baseFont,
      boldFont: boldFont,
      isLargePaper: false,
    );

    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(widthPt + 16, heightPt + 16, marginAll: 8),
        build: (context) {
          return pw.Theme(
            data: pw.ThemeData.withFont(base: baseFont, bold: boldFont),
            child: pw.Directionality(
              textDirection: pw.TextDirection.rtl,
              child: pw.Container(
                width: widthPt,
                padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                decoration: pw.BoxDecoration(
                  color: PdfColors.white,
                  border: pw.Border.all(color: _colorBorder, width: 0.8),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                ),
                child: body,
              ),
            ),
          );
        },
      ),
    );
    return doc.save();
  }

  /// بناء الوثيقة وفق المقاس الورقي المطلوب من خدمة الطباعة:
  ///  - عرض حراري (57/80مم): الإيصال على اللفة بأبعاده الطبيعية الدقيقة.
  ///  - عرض أكبر (A4/تابلت/...):
  ///      * إن كان إعداد الورق A4: توليد فاتورة ضريبية رسمية كاملة لورقة A4.
  ///      * إن كان إعداد الورق حراري (80مم أو 58مم): عرض نفس شريط الإيصال
  ///        بأبعاده ونسبه الحقيقية في أعلى الصفحة (دون مط أو تشويه).
  static Future<Uint8List> _buildForPaper({
    required SaleInvoice invoice,
    required bool width80mm,
    required String? storeName,
    required String? storePhone,
    required String? storeLogoPath,
    required PdfPageFormat requested,
  }) async {
    final baseFont = await _loadFont('fonts/Cairo-Regular.ttf');
    final boldFont = await _loadFont('fonts/Cairo-Bold.ttf');
    final logoBytes = await _loadLogoBytes(storeLogoPath);
    final logo = logoBytes != null ? _logoProvider(logoBytes) : null;

    if (_isThermalWidth(requested.width)) {
      final built = await _buildReceipt(
        invoice: invoice,
        width80mm: width80mm,
        storeName: storeName,
        storePhone: storePhone,
        storeLogoPath: storeLogoPath,
      );
      return built.bytes;
    }

    final paperSizeSetting = await PrinterSettingsService.getPaperSize();
    if (paperSizeSetting == 'a4') {
      return _buildA4InvoiceDocument(
        invoice: invoice,
        storeName: storeName,
        storePhone: storePhone,
        logo: logo,
        baseFont: baseFont,
        boldFont: boldFont,
        pageFormat: requested,
      );
    }

    // ورقة كبيرة أو معاينة تابلت مع ضبط مقاس حراري (80mm أو 58mm):
    // كارت الفاتورة يظهر كشريط إيصال كاشير حقيقي بنسبه وأبعاده الطبيعية
    // دون أي مط لملء الصفحة ودون تكبير مفرط للخطوط.
    final body = _receiptBody(
      invoice: invoice,
      width80mm: width80mm,
      storeName: storeName,
      storePhone: storePhone,
      logo: logo,
      baseFont: baseFont,
      boldFont: boldFont,
      isLargePaper: false,
    );

    final receiptWidth = width80mm ? 80 * PdfPageFormat.mm : 57 * PdfPageFormat.mm;

    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: requested,
        margin: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        build: (context) {
          return pw.Theme(
            data: pw.ThemeData.withFont(base: baseFont, bold: boldFont),
            child: pw.Directionality(
              textDirection: pw.TextDirection.rtl,
              child: pw.Align(
                alignment: pw.Alignment.topCenter,
                child: pw.Container(
                  width: receiptWidth,
                  padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.white,
                    border: pw.Border.all(color: _colorBorder, width: 0.8),
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                  ),
                  child: body,
                ),
              ),
            ),
          );
        },
      ),
    );
    return doc.save();
  }

  /// بناء وثيقة فاتورة ضريبية رسمية كاملة لورق A4 بمظهر محاسبي أنيق ومحترف.
  static Future<Uint8List> _buildA4InvoiceDocument({
    required SaleInvoice invoice,
    required String? storeName,
    required String? storePhone,
    required pw.ImageProvider? logo,
    required pw.Font baseFont,
    required pw.Font boldFont,
    required PdfPageFormat pageFormat,
  }) async {
    final dateFmt = DateFormat('yyyy/MM/dd - hh:mm a');
    final doc = pw.Document();

    doc.addPage(
      pw.MultiPage(
        pageFormat: pageFormat,
        margin: const pw.EdgeInsets.all(28),
        theme: pw.ThemeData.withFont(base: baseFont, bold: boldFont),
        textDirection: pw.TextDirection.rtl,
        header: (context) {
          return pw.Column(
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(
                    children: [
                      if (logo != null) ...[
                        pw.Container(
                          width: 48,
                          height: 48,
                          child: pw.ClipRRect(
                            horizontalRadius: 6,
                            verticalRadius: 6,
                            child: pw.Image(logo, fit: pw.BoxFit.contain),
                          ),
                        ),
                        pw.SizedBox(width: 12),
                      ],
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            storeName?.trim().isNotEmpty == true
                                ? storeName!.trim()
                                : AppStrings.STORE_NAME,
                            style: pw.TextStyle(
                              font: boldFont,
                              fontSize: 18,
                              color: _colorNavy,
                            ),
                          ),
                          if (storePhone != null && storePhone.trim().isNotEmpty) ...[
                            pw.SizedBox(height: 3),
                            pw.Text(
                              'هاتف: ${storePhone.trim()}',
                              style: pw.TextStyle(
                                font: baseFont,
                                fontSize: 10,
                                color: _colorSecondary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        'فاتورة مبيعات ضريبية',
                        style: pw.TextStyle(
                          font: boldFont,
                          fontSize: 16,
                          color: _colorPrimaryBlue,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        'رقم الفاتورة: ${invoice.invoiceNumber}',
                        style: pw.TextStyle(
                          font: boldFont,
                          fontSize: 11,
                          color: _colorNavy,
                        ),
                      ),
                      pw.Text(
                        'التاريخ: ${dateFmt.format(invoice.createdAt)}',
                        style: pw.TextStyle(
                          font: baseFont,
                          fontSize: 10,
                          color: _colorSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 12),
              pw.Divider(thickness: 1, color: _colorBorder),
              pw.SizedBox(height: 8),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: pw.BoxDecoration(
                  color: _colorCardBg,
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                  border: pw.Border.all(color: _colorBorder, width: 0.8),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'العميل: ${invoice.customerName ?? 'عميل نقدي'}',
                      style: pw.TextStyle(font: boldFont, fontSize: 11),
                    ),
                    pw.Text(
                      'طريقة الدفع: ${invoice.paymentMethodArabic}',
                      style: pw.TextStyle(font: baseFont, fontSize: 10, color: _colorSecondary),
                    ),
                    pw.Text(
                      'الحالة: ${invoice.statusArabic}',
                      style: pw.TextStyle(
                        font: boldFont,
                        fontSize: 10,
                        color: invoice.status == 'completed' ? _colorGreenText : _colorRedText,
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 14),
            ],
          );
        },
        build: (context) => [
          pw.Table(
            border: pw.TableBorder.all(color: _colorBorder, width: 0.5),
            columnWidths: {
              0: const pw.FlexColumnWidth(1),
              1: const pw.FlexColumnWidth(5),
              2: const pw.FlexColumnWidth(1.5),
              3: const pw.FlexColumnWidth(2),
              4: const pw.FlexColumnWidth(2),
            },
            children: [
              pw.TableRow(
                decoration: pw.BoxDecoration(color: _colorHeaderBg),
                children: [
                  _tableCell('#', boldFont, 10, bold: true, align: pw.Alignment.center),
                  _tableCell('الصنف / البيان', boldFont, 10, bold: true, align: pw.Alignment.centerRight),
                  _tableCell('الكمية', boldFont, 10, bold: true, align: pw.Alignment.center),
                  _tableCell('سعر الوحدة', boldFont, 10, bold: true, align: pw.Alignment.center),
                  _tableCell('الإجمالي', boldFont, 10, bold: true, align: pw.Alignment.center),
                ],
              ),
              for (var i = 0; i < invoice.items.length; i++)
                pw.TableRow(
                  decoration: pw.BoxDecoration(color: i.isEven ? _colorCardBg : PdfColors.white),
                  children: [
                    _tableCell('${i + 1}', baseFont, 9.5, align: pw.Alignment.center),
                    _tableCell(
                      invoice.items[i].productName ?? 'منتج',
                      baseFont,
                      9.5,
                      align: pw.Alignment.centerRight,
                    ),
                    _tableCell('${invoice.items[i].quantity}', baseFont, 9.5, align: pw.Alignment.center),
                    _tableCell(
                      invoice.items[i].unitPrice % 1 == 0
                          ? invoice.items[i].unitPrice.toInt().toString()
                          : invoice.items[i].unitPrice.toStringAsFixed(2),
                      baseFont,
                      9.5,
                      align: pw.Alignment.center,
                    ),
                    _tableCell(
                      invoice.items[i].lineTotal % 1 == 0
                          ? invoice.items[i].lineTotal.toInt().toString()
                          : invoice.items[i].lineTotal.toStringAsFixed(2),
                      boldFont,
                      9.5,
                      align: pw.Alignment.center,
                      bold: true,
                    ),
                  ],
                ),
            ],
          ),
          pw.SizedBox(height: 16),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'ملاحظات وشروط:',
                    style: pw.TextStyle(font: boldFont, fontSize: 10, color: _colorNavy),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    '• البضاعة المباعة ترد وتستبدل خلال 14 يوماً مع أصل الفاتورة.',
                    style: pw.TextStyle(font: baseFont, fontSize: 9, color: _colorSecondary),
                  ),
                  pw.Text(
                    '• شكراً لتعاملكم معنا ونسعد بخدمتكم دائماً.',
                    style: pw.TextStyle(font: baseFont, fontSize: 9, color: _colorSecondary),
                  ),
                ],
              ),
              pw.Container(
                width: 220,
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  color: _colorCardBg,
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                  border: pw.Border.all(color: _colorBorder, width: 0.8),
                ),
                child: pw.Column(
                  children: [
                    if (invoice.discount > 0 || invoice.tax > 0) ...[
                      _row('الإجمالي الفرعي', AppStrings.money(invoice.subtotal), baseFont, size: 9.5),
                      if (invoice.discount > 0)
                        _row(
                          'الخصم',
                          '- ${AppStrings.money(invoice.discount)}',
                          baseFont,
                          size: 9.5,
                          valueColor: _colorRedText,
                        ),
                      if (invoice.tax > 0)
                        _row('الضريبة', AppStrings.money(invoice.tax), baseFont, size: 9.5),
                      _divider(),
                      pw.SizedBox(height: 4),
                    ],
                    _row(
                      '${AppStrings.LABEL_TOTAL}:',
                      AppStrings.money(invoice.total),
                      boldFont,
                      size: 12,
                      labelColor: _colorNavy,
                      valueColor: _colorPrimaryBlue,
                    ),
                    pw.SizedBox(height: 4),
                    _row('${AppStrings.LABEL_PAID}:', AppStrings.money(invoice.paidAmount), baseFont, size: 9.5),
                    pw.SizedBox(height: 2),
                    if (invoice.isChangePositive)
                      _row(
                        '${AppStrings.LABEL_CHANGE}:',
                        AppStrings.money(invoice.changeDue),
                        boldFont,
                        size: 9.5,
                        labelColor: _colorGreenText,
                        valueColor: _colorGreenText,
                      )
                    else if (invoice.remainingOnCustomer > 0)
                      _row(
                        '${AppStrings.LABEL_REMAINING_ON_CUSTOMER}:',
                        AppStrings.money(invoice.remainingOnCustomer),
                        boldFont,
                        size: 9.5,
                        labelColor: _colorRedText,
                        valueColor: _colorRedText,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
        footer: (context) {
          return pw.Column(
            children: [
              pw.Divider(thickness: 0.5, color: _colorBorder),
              pw.SizedBox(height: 4),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'صفحة ${context.pageNumber} من ${context.pagesCount}',
                    style: pw.TextStyle(font: baseFont, fontSize: 8.5, color: _colorSecondary),
                  ),
                  pw.Text(
                    'تم الإصدار عبر نظام النقرشي كاشير',
                    style: pw.TextStyle(font: baseFont, fontSize: 8.5, color: _colorSecondary),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );

    return doc.save();
  }

  /// بناء وثيقة الإيصال الحرارية بالارتفاع الدقيق المحسوب لمنع المط أو التشويه.
  static pw.Document _buildReceiptDocument({
    required SaleInvoice invoice,
    required bool width80mm,
    required String? storeName,
    required String? storePhone,
    required pw.ImageProvider? logo,
    required pw.Font baseFont,
    required pw.Font boldFont,
  }) {
    final widthPt = width80mm ? 80 * PdfPageFormat.mm : 57 * PdfPageFormat.mm;
    final heightPt = _calculateReceiptHeight(
      invoice: invoice,
      width80mm: width80mm,
      hasLogo: logo != null,
      hasPhone: storePhone != null && storePhone.trim().isNotEmpty,
    );
    final pageFormat = PdfPageFormat(widthPt, heightPt, marginAll: 0);

    final body = _receiptBody(
      invoice: invoice,
      width80mm: width80mm,
      storeName: storeName,
      storePhone: storePhone,
      logo: logo,
      baseFont: baseFont,
      boldFont: boldFont,
      isLargePaper: false,
    );

    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: pageFormat,
        margin: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        build: (context) {
          return pw.Theme(
            data: pw.ThemeData.withFont(base: baseFont, bold: boldFont),
            child: pw.Directionality(
              textDirection: pw.TextDirection.rtl,
              child: body,
            ),
          );
        },
      ),
    );
    return doc;
  }

  /// محتوى الإيصال المتطابق تماماً مع شاشة الفاتورة في التطبيق:
  /// الشعار بجوار الاسم، ولا ذكر لرقم الفاتورة في الترويسة،
  /// جدول بأعمدة متساوية تماماً (الكمية - السعر - الإجمالي)،
  /// مع خطوط واضحة ودون اقتصاص للكتابة داخل الخلية.
  static pw.Widget _receiptBody({
    required SaleInvoice invoice,
    required bool width80mm,
    required String? storeName,
    required String? storePhone,
    required pw.ImageProvider? logo,
    required pw.Font baseFont,
    required pw.Font boldFont,
    bool isLargePaper = false,
  }) {
    final dateFmt = DateFormat('yyyy/MM/dd - hh:mm a');

    // أبعاد وخطوط متناسبة مع الشاشة ومع الورق الحراري
    final double titleSize = isLargePaper ? 16.0 : (width80mm ? 13.0 : 11.0);
    final double logoSize = isLargePaper ? 32.0 : (width80mm ? 30.0 : 24.0);
    final double subSize = isLargePaper ? 10.5 : (width80mm ? 8.0 : 7.0);
    final double typeSize = isLargePaper ? 11.0 : (width80mm ? 9.0 : 8.0);
    final double invoiceNumSize = isLargePaper ? 12.0 : (width80mm ? 8.5 : 7.5);
    final double badgeSize = isLargePaper ? 10.0 : (width80mm ? 7.5 : 6.5);
    final double dateSize = isLargePaper ? 10.5 : (width80mm ? 8.0 : 7.0);
    final double customerSize = isLargePaper ? 11.0 : (width80mm ? 8.0 : 7.0);
    final double tableHeaderSize = isLargePaper ? 11.0 : (width80mm ? 8.0 : 7.0);
    final double tableDataSize = isLargePaper ? 10.5 : (width80mm ? 7.5 : 6.5);
    final double totalLabelSize = isLargePaper ? 13.5 : (width80mm ? 9.5 : 8.5);
    final double totalValSize = isLargePaper ? 15.0 : (width80mm ? 10.0 : 9.0);
    final double paidSize = isLargePaper ? 11.0 : (width80mm ? 8.0 : 7.0);
    final double changeSize = isLargePaper ? 11.0 : (width80mm ? 8.0 : 7.0);
    final double footerSize = isLargePaper ? 9.5 : (width80mm ? 7.0 : 6.0);
    final double barcodeWidth = isLargePaper ? 120.0 : (width80mm ? 110.0 : 90.0);
    final double barcodeHeight = isLargePaper ? 24.0 : (width80mm ? 22.0 : 18.0);
    final double thankYouSize = isLargePaper ? 11.0 : (width80mm ? 8.5 : 7.5);

    final statusBg = invoice.status == 'completed'
        ? _colorGreenBg
        : (invoice.status == 'held' ? _colorAmberBg : _colorRedBg);
    final statusBorder = invoice.status == 'completed'
        ? _colorGreenBorder
        : (invoice.status == 'held' ? _colorAmberBorder : _colorRedBorder);
    final statusText = invoice.status == 'completed'
        ? _colorGreenText
        : (invoice.status == 'held' ? _colorAmberText : _colorRedText);

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        // ترويسة المحل: الشعار بجوار اسم المحل
        pw.Center(
          child: logo == null
              ? pw.Text(
                  storeName?.trim().isNotEmpty == true
                      ? storeName!.trim()
                      : AppStrings.STORE_NAME,
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(
                    font: boldFont,
                    fontSize: titleSize,
                    color: _colorNavy,
                  ),
                )
              : pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.center,
                  mainAxisSize: pw.MainAxisSize.min,
                  children: [
                    pw.Container(
                      width: logoSize,
                      height: logoSize,
                      child: pw.ClipRRect(
                        horizontalRadius: 6,
                        verticalRadius: 6,
                        child: pw.Image(logo, fit: pw.BoxFit.contain),
                      ),
                    ),
                    pw.SizedBox(width: isLargePaper ? 10 : 8),
                    pw.Text(
                      storeName?.trim().isNotEmpty == true
                          ? storeName!.trim()
                          : AppStrings.STORE_NAME,
                      style: pw.TextStyle(
                        font: boldFont,
                        fontSize: titleSize,
                        color: _colorNavy,
                      ),
                    ),
                  ],
                ),
        ),
        if (storePhone != null && storePhone.trim().isNotEmpty) ...[
          pw.SizedBox(height: isLargePaper ? 3 : 2),
          pw.Center(
            child: pw.Text(
              'هاتف: ${storePhone.trim()}',
              style: pw.TextStyle(
                font: baseFont,
                fontSize: subSize,
                color: _colorSecondary,
              ),
            ),
          ),
        ],
        pw.SizedBox(height: isLargePaper ? 3 : 2.5),
        pw.Center(
          child: pw.Text(
            invoice.status == 'held' ? 'فاتورة معلقة' : 'فاتورة مبيعات',
            style: pw.TextStyle(
              font: boldFont,
              fontSize: typeSize,
              color: _colorSecondary,
            ),
          ),
        ),
        pw.SizedBox(height: isLargePaper ? 8 : 5),
        _divider(),
        pw.SizedBox(height: isLargePaper ? 8 : 5),

        // بطاقة بيانات الفاتورة
        pw.Container(
          padding: pw.EdgeInsets.symmetric(
            horizontal: isLargePaper ? 12 : 7,
            vertical: isLargePaper ? 9 : 5,
          ),
          decoration: pw.BoxDecoration(
            color: _colorCardBg,
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
            border: pw.Border.all(color: _colorBorder, width: 0.8),
          ),
          child: pw.Column(
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'رقم الفاتورة: ${invoice.invoiceNumber}',
                    style: pw.TextStyle(
                      font: boldFont,
                      fontSize: invoiceNumSize,
                      color: _colorNavy,
                    ),
                  ),
                  if (invoice.status != 'completed')
                    pw.Container(
                      padding: pw.EdgeInsets.symmetric(
                        horizontal: isLargePaper ? 8 : 5,
                        vertical: isLargePaper ? 2.5 : 1.5,
                      ),
                      decoration: pw.BoxDecoration(
                        color: statusBg,
                        border: pw.Border.all(color: statusBorder, width: 0.6),
                        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                      ),
                      child: pw.Text(
                        invoice.statusArabic,
                        style: pw.TextStyle(
                          font: boldFont,
                          fontSize: badgeSize,
                          color: statusText,
                        ),
                      ),
                    ),
                ],
              ),
              pw.SizedBox(height: isLargePaper ? 5 : 3),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'التاريخ: ${dateFmt.format(invoice.createdAt)}',
                    style: pw.TextStyle(
                      font: baseFont,
                      fontSize: dateSize,
                      color: _colorSecondary,
                    ),
                  ),
                  pw.Text(
                    'طريقة الدفع: ${invoice.paymentMethodArabic}',
                    style: pw.TextStyle(
                      font: baseFont,
                      fontSize: dateSize,
                      color: _colorSecondary,
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: isLargePaper ? 5 : 3),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'العميل: ${invoice.customerName ?? 'عميل نقدي'}',
                    style: pw.TextStyle(
                      font: boldFont,
                      fontSize: customerSize,
                      color: const PdfColor(0.2, 0.25, 0.33),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        pw.SizedBox(height: isLargePaper ? 8 : 5),

        // جدول الأصناف: الأعمدة (الكمية - السعر - الإجمالي) نفس العرض 18:18:18
        // والكتابة داخل الخلية دون اقتصاص ومحاذاة متطابقة مع التطبيق
        pw.Container(
          decoration: pw.BoxDecoration(
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
            border: pw.Border.all(color: _colorTableBorder, width: 0.8),
          ),
          child: pw.Table(
            border: pw.TableBorder.all(
              color: _colorBorder,
              width: 0.5,
            ),
            columnWidths: {
              0: const pw.FlexColumnWidth(46),
              1: const pw.FlexColumnWidth(18),
              2: const pw.FlexColumnWidth(18),
              3: const pw.FlexColumnWidth(18),
            },
            children: [
              pw.TableRow(
                decoration: pw.BoxDecoration(color: _colorHeaderBg),
                children: [
                  _tableCell('الصنف', boldFont, tableHeaderSize,
                      bold: true, align: pw.Alignment.centerRight),
                  _tableCell('الكمية', boldFont, tableHeaderSize,
                      bold: true, align: pw.Alignment.center),
                  _tableCell('السعر', boldFont, tableHeaderSize,
                      bold: true, align: pw.Alignment.center),
                  _tableCell('الإجمالي', boldFont, tableHeaderSize,
                      bold: true, align: pw.Alignment.center),
                ],
              ),
              for (var i = 0; i < invoice.items.length; i++)
                pw.TableRow(
                  decoration: pw.BoxDecoration(
                    color: i.isEven ? _colorCardBg : PdfColors.white,
                  ),
                  children: [
                    _tableCell(
                      invoice.items[i].productName ?? 'منتج',
                      baseFont,
                      tableDataSize,
                      align: pw.Alignment.centerRight,
                    ),
                    _tableCell(
                      '${invoice.items[i].quantity}',
                      baseFont,
                      tableDataSize,
                      align: pw.Alignment.center,
                    ),
                    _tableCell(
                      invoice.items[i].unitPrice % 1 == 0
                          ? invoice.items[i].unitPrice.toInt().toString()
                          : invoice.items[i].unitPrice.toStringAsFixed(2),
                      baseFont,
                      tableDataSize,
                      align: pw.Alignment.center,
                    ),
                    _tableCell(
                      invoice.items[i].lineTotal % 1 == 0
                          ? invoice.items[i].lineTotal.toInt().toString()
                          : invoice.items[i].lineTotal.toStringAsFixed(2),
                      boldFont,
                      tableDataSize,
                      align: pw.Alignment.center,
                      bold: true,
                    ),
                  ],
                ),
            ],
          ),
        ),
        pw.SizedBox(height: isLargePaper ? 8 : 5),

        // بطاقة المبالغ المالية
        pw.Container(
          padding: pw.EdgeInsets.symmetric(
            horizontal: isLargePaper ? 12 : 7,
            vertical: isLargePaper ? 9 : 5,
          ),
          decoration: pw.BoxDecoration(
            color: _colorCardBg,
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
            border: pw.Border.all(color: _colorBorder, width: 0.8),
          ),
          child: pw.Column(
            children: [
              if (invoice.discount > 0 || invoice.tax > 0) ...[
                _row('الإجمالي الفرعي', AppStrings.money(invoice.subtotal), baseFont, size: paidSize),
                if (invoice.discount > 0)
                  _row('الخصم', '- ${AppStrings.money(invoice.discount)}', baseFont, size: paidSize, valueColor: _colorRedText),
                if (invoice.tax > 0)
                  _row('الضريبة', AppStrings.money(invoice.tax), baseFont, size: paidSize),
                _divider(),
                pw.SizedBox(height: 3),
              ],
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    '${AppStrings.LABEL_TOTAL}:',
                    style: pw.TextStyle(
                      font: boldFont,
                      fontSize: totalLabelSize,
                      color: _colorNavy,
                    ),
                  ),
                  pw.Text(
                    AppStrings.money(invoice.total),
                    style: pw.TextStyle(
                      font: boldFont,
                      fontSize: totalValSize,
                      color: _colorPrimaryBlue,
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: isLargePaper ? 6 : 3),
              _row('${AppStrings.LABEL_PAID}:', AppStrings.money(invoice.paidAmount), baseFont, size: paidSize),
              pw.SizedBox(height: isLargePaper ? 4 : 2),
              if (invoice.isChangePositive)
                _row(
                  '${AppStrings.LABEL_CHANGE}:',
                  AppStrings.money(invoice.changeDue),
                  boldFont,
                  size: changeSize,
                  labelColor: _colorGreenText,
                  valueColor: _colorGreenText,
                )
              else if (invoice.remainingOnCustomer > 0)
                _row(
                  '${AppStrings.LABEL_REMAINING_ON_CUSTOMER}:',
                  AppStrings.money(invoice.remainingOnCustomer),
                  boldFont,
                  size: changeSize,
                  labelColor: _colorRedText,
                  valueColor: _colorRedText,
                ),
            ],
          ),
        ),
        pw.SizedBox(height: isLargePaper ? 8 : 6),
        _divider(),
        pw.SizedBox(height: isLargePaper ? 6 : 5),

        // سياسة الاسترجاع
        pw.Center(
          child: pw.Text(
            'البضاعة المباعة ترد وتستبدل خلال 14 يوماً مع أصل الفاتورة',
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              font: baseFont,
              fontSize: footerSize,
              color: _colorSecondary,
            ),
          ),
        ),
        pw.SizedBox(height: isLargePaper ? 6 : 5),

        // باركود الفاتورة
        pw.Center(
          child: pw.BarcodeWidget(
            barcode: pw.Barcode.code128(),
            data: invoice.invoiceNumber,
            width: barcodeWidth,
            height: barcodeHeight,
            drawText: false,
          ),
        ),
        pw.SizedBox(height: 2),
        pw.Center(
          child: pw.Text(
            invoice.invoiceNumber,
            style: pw.TextStyle(
              font: baseFont,
              fontSize: isLargePaper ? 9.5 : 7.0,
              color: _colorSecondary,
            ),
          ),
        ),
        pw.SizedBox(height: isLargePaper ? 6 : 5),

        // عبارة الشكر
        pw.Center(
          child: pw.Text(
            'شكراً لتعاملكم معنا • نسعد بخدمتكم دائماً',
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              font: boldFont,
              fontSize: thankYouSize,
              color: _colorNavy,
            ),
          ),
        ),
      ],
    );
  }

  /// خلية جدول: نص محاذي مع FittedBox ليتم تغيير حجم الخط تلقائياً دون اقتصاص
  static pw.Widget _tableCell(
    String text,
    pw.Font font,
    double size, {
    bool bold = false,
    pw.Alignment align = pw.Alignment.center,
    PdfColor? color,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 2.5, vertical: 3.5),
      child: pw.FittedBox(
        fit: pw.BoxFit.scaleDown,
        alignment: align,
        child: pw.Text(
          text,
          style: pw.TextStyle(
            font: font,
            fontSize: size,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            color: color ?? (bold ? _colorNavy : const PdfColor(0.2, 0.25, 0.33)),
          ),
        ),
      ),
    );
  }

  static pw.Widget _divider() {
    return pw.Container(
      height: 0.8,
      decoration: pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(width: 0.8, color: _colorBorder)),
      ),
    );
  }

  static pw.Widget _row(
    String label,
    String value,
    pw.Font font, {
    double size = 8,
    PdfColor? labelColor,
    PdfColor? valueColor,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              font: font,
              fontSize: size,
              color: labelColor ?? _colorSecondary,
            ),
          ),
          pw.Text(
            value,
            style: pw.TextStyle(
              font: font,
              fontSize: size,
              color: valueColor ?? _colorNavy,
            ),
          ),
        ],
      ),
    );
  }

  /// فتح نافذة الطباعة مع دعم المعاينة المتطابقة مع شاشة التطبيق.
  static Future<void> printReceipt({
    required SaleInvoice invoice,
    required bool width80mm,
    String? storeName,
    String? storePhone,
    String? storeLogoPath,
  }) async {
    final preview = await _buildReceipt(
      invoice: invoice,
      width80mm: width80mm,
      storeName: storeName,
      storePhone: storePhone,
      storeLogoPath: storeLogoPath,
    );
    final paperFormat = PdfPageFormat(
      preview.widthPt,
      preview.heightPt,
      marginAll: 0,
    );

    await PrinterSettingsService.printDocument(
      name: 'فاتورة_${invoice.invoiceNumber}',
      format: paperFormat,
      onLayout: (format) => _buildForPaper(
        invoice: invoice,
        width80mm: width80mm,
        storeName: storeName,
        storePhone: storePhone,
        storeLogoPath: storeLogoPath,
        requested: format,
      ),
    );
  }

  /// مشاركة الإيصال كصورة كاملة (PNG) عالية الدقة عبر وسائل المشاركة (واتساب، فيسبوك، إلخ).
  static Future<void> shareReceipt({
    required SaleInvoice invoice,
    required bool width80mm,
    String? storeName,
    String? storePhone,
    String? storeLogoPath,
  }) async {
    final pdfBytes = await buildReceiptPdf(
      invoice: invoice,
      width80mm: width80mm,
      storeName: storeName,
      storePhone: storePhone,
      storeLogoPath: storeLogoPath,
      asCard: true,
    );
    await DocumentShareService.sharePdfAsImage(
      pdfBytes: pdfBytes,
      filename: 'فاتورة_${invoice.invoiceNumber}',
    );
  }
}
