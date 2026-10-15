import 'dart:io';

import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/constants/app_constants.dart';
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

  /// ارتفاع صفحة الإيصال القياسية (مم) عند التوسيط العمودي.
  static const double _fixedReceiptHeightMm = 190.0;

  /// عرض حراري تقريبي (نقطة): 85مم = 240.6 نقطة. أي عرض مطلوب ≤ 240
  /// يُعامل كلفة حرارية (57/80مم)، وكل ما هو أعرض يُعامل كورقة كبيرة.
  static const double _thermalMaxWidthPt = 240.0;

  static bool _isThermalWidth(double widthPt) =>
      widthPt > 0 && widthPt <= _thermalMaxWidthPt;

  /// بناء الإيصال (مرحلتان) والعودة بالوثيقة وارتفاعها الفعلي.
  ///
  /// المرحلة الأولى بمقاس لفة ذاتي الارتفاع لمعرفة طول المحتوى الفعلي،
  /// ثم إذا احتوى المحتوى على صفحة القياسية (190mm) تُبنى الصفحة
  /// بارتفاع ثابت مع توسيط الإيصال عمودياً في منتصفها (طلب الاستخدام:
  /// "الفاتورة بالكامل في منتصف الصفحة عمودياً"). الفواتير الطويلة تبقى
  /// على الارتفاع الذاتي حتى لا يُقص أي جزء منها.
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

    // المرحلة 1: ارتفاع ذاتي (لفة حرارية) لقياس طول المحتوى الفعلي.
    final autoDoc = _buildReceiptDocument(
      invoice: invoice,
      width80mm: width80mm,
      storeName: storeName,
      storePhone: storePhone,
      logo: logo,
      baseFont: baseFont,
      boldFont: boldFont,
      fixedPageHeightMm: null,
    );
    await autoDoc.save();
    final contentHeight =
        autoDoc.document.pdfPageList.pages.first.pageFormat.height;

    // المرحلة 2: صفحة قياسية ثابتة مع توسيط عمودي إن احتوى المحتوى عليها؛
    // وإلا الارتفاع الذاتي (لا يُقصّ أي جزء من الفاتورة الطويلة).
    final fixedUsableHeight =
        _fixedReceiptHeightMm * PdfPageFormat.mm - 16.0;
    final useFixed = contentHeight <= fixedUsableHeight;
    final doc = _buildReceiptDocument(
      invoice: invoice,
      width80mm: width80mm,
      storeName: storeName,
      storePhone: storePhone,
      logo: logo,
      baseFont: baseFont,
      boldFont: boldFont,
      fixedPageHeightMm: useFixed ? _fixedReceiptHeightMm : null,
    );
    final bytes = await doc.save();
    final heightPt = useFixed
        ? _fixedReceiptHeightMm * PdfPageFormat.mm
        : contentHeight;

    return _BuiltReceipt(bytes, heightPt, widthPt);
  }

  /// بناء بايتات PDF الإيصال (تُستخدم للمشاركة).
  static Future<Uint8List> buildReceiptPdf({
    required SaleInvoice invoice,
    required bool width80mm,
    String? storeName,
    String? storePhone,
    String? storeLogoPath,
  }) async {
    final built = await _buildReceipt(
      invoice: invoice,
      width80mm: width80mm,
      storeName: storeName,
      storePhone: storePhone,
      storeLogoPath: storeLogoPath,
    );
    return built.bytes;
  }

  /// بناء الوثيقة وفق المقاس الورقي المطلوب من خدمة الطباعة:
  ///  - عرض حراري (57/80مم): الإيصال الأصلي على اللفة بنفس أبعاده ومطابق للتطبيق.
  ///  - عرض أكبر (A4/تابلت/...): عرض نفس الفاتورة المتطابقة تماماً مع المعروضة
  ///    على التطبيق في منتصف الصفحة بأبعاد الإيصال الحراري 80مم القياسية.
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

    // ورقة كبيرة (A4 أو شاشة المعاينة قبل الطباعة على الهاتف/التابلت):
    // عرض الفاتورة مطابقة تماماً للمظهر داخل التطبيق في منتصف الورقة بعرض 80مم
    final body = _receiptBody(
      invoice: invoice,
      width80mm: width80mm,
      storeName: storeName,
      storePhone: storePhone,
      logo: logo,
      baseFont: baseFont,
      boldFont: boldFont,
    );

    final receiptWidthPt = width80mm ? 80 * PdfPageFormat.mm : 57 * PdfPageFormat.mm;

    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: requested,
        margin: const pw.EdgeInsets.all(16),
        build: (context) {
          return pw.Theme(
            data: pw.ThemeData.withFont(base: baseFont, bold: boldFont),
            child: pw.Directionality(
              textDirection: pw.TextDirection.rtl,
              child: pw.Center(
                child: pw.Container(
                  width: receiptWidthPt,
                  padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.white,
                    border: pw.Border.all(color: PdfColors.grey300, width: 0.8),
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

  /// بناء وثيقة الإيصال الحرارية. [fixedPageHeightMm] == null → ارتفاع ذاتي
  /// (مثل لفة حرارية)، وإلا ارتفاع ثابت مع توسيط المحتوى عمودياً.
  static pw.Document _buildReceiptDocument({
    required SaleInvoice invoice,
    required bool width80mm,
    required String? storeName,
    required String? storePhone,
    required pw.ImageProvider? logo,
    required pw.Font baseFont,
    required pw.Font boldFont,
    required double? fixedPageHeightMm,
  }) {
    final pageFormat = fixedPageHeightMm == null
        ? (width80mm ? PdfPageFormat.roll80 : PdfPageFormat.roll57)
        : PdfPageFormat(
            width80mm ? 80 * PdfPageFormat.mm : 57 * PdfPageFormat.mm,
            fixedPageHeightMm * PdfPageFormat.mm,
          );

    final body = _receiptBody(
      invoice: invoice,
      width80mm: width80mm,
      storeName: storeName,
      storePhone: storePhone,
      logo: logo,
      baseFont: baseFont,
      boldFont: boldFont,
    );

    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: pageFormat,
        margin: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        build: (context) {
          // توسيط عمودي على الصفحة الثابتة القياسية.
          final pw.Widget content = fixedPageHeightMm != null
              ? pw.Center(child: body)
              : body;
          return pw.Theme(
            data: pw.ThemeData.withFont(base: baseFont, bold: boldFont),
            child: pw.Directionality(
              textDirection: pw.TextDirection.rtl,
              child: content,
            ),
          );
        },
      ),
    );
    return doc;
  }

  /// محتوى الإيصال المتطابق تماماً مع شاشة الفاتورة في التطبيق:
  /// الشعار بجوار الاسم، ولا ذكر لرقم الفاتورة في الترويسة،
  /// جدول بنسب احترافية (تكبير الصنف وتصغير الكمية والسعر والإجمالي)،
  /// وبطاقات بيانات الفاتورة والإجماليات والتذييل.
  static pw.Widget _receiptBody({
    required SaleInvoice invoice,
    required bool width80mm,
    required String? storeName,
    required String? storePhone,
    required pw.ImageProvider? logo,
    required pw.Font baseFont,
    required pw.Font boldFont,
  }) {
    final dateFmt = DateFormat('yyyy/MM/dd - hh:mm a');
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        // ترويسة المحل: الشعار بجوار اسم المحل (ولا يكتب رقم الفاتورة هنا)
        pw.Center(
          child: logo == null
              ? pw.Text(
                  storeName?.trim().isNotEmpty == true
                      ? storeName!.trim()
                      : AppStrings.STORE_NAME,
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(
                    font: boldFont,
                    fontSize: width80mm ? 13 : 11,
                    color: PdfColors.grey900,
                  ),
                )
              : pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.center,
                  mainAxisSize: pw.MainAxisSize.min,
                  children: [
                    pw.Container(
                      width: width80mm ? 32 : 26,
                      height: width80mm ? 32 : 26,
                      child: pw.ClipRRect(
                        horizontalRadius: 4,
                        verticalRadius: 4,
                        child: pw.Image(logo, fit: pw.BoxFit.contain),
                      ),
                    ),
                    pw.SizedBox(width: 8),
                    pw.Text(
                      storeName?.trim().isNotEmpty == true
                          ? storeName!.trim()
                          : AppStrings.STORE_NAME,
                      style: pw.TextStyle(
                        font: boldFont,
                        fontSize: width80mm ? 13 : 11,
                        color: PdfColors.grey900,
                      ),
                    ),
                  ],
                ),
        ),
        if (storePhone != null && storePhone.trim().isNotEmpty) ...[
          pw.SizedBox(height: 2),
          pw.Center(
            child: pw.Text(
              'هاتف: ${storePhone.trim()}',
              style: pw.TextStyle(
                font: baseFont,
                fontSize: width80mm ? 8 : 7,
                color: PdfColors.grey700,
              ),
            ),
          ),
        ],
        pw.SizedBox(height: 2.5),
        pw.Center(
          child: pw.Text(
            invoice.status == 'held' ? 'فاتورة معلقة' : 'فاتورة مبيعات',
            style: pw.TextStyle(
              font: boldFont,
              fontSize: width80mm ? 9 : 8,
              color: PdfColors.grey700,
            ),
          ),
        ),
        pw.SizedBox(height: 5),
        _divider(),
        pw.SizedBox(height: 5),

        // بطاقة بيانات الفاتورة
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 5),
          decoration: pw.BoxDecoration(
            color: PdfColors.grey100,
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
            border: pw.Border.all(color: PdfColors.grey300, width: 0.6),
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
                      fontSize: width80mm ? 8.5 : 7.5,
                      color: PdfColors.grey900,
                    ),
                  ),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1.5,
                    ),
                    decoration: pw.BoxDecoration(
                      color: invoice.status == 'completed'
                          ? PdfColors.green50
                          : (invoice.status == 'held'
                              ? PdfColors.amber50
                              : PdfColors.red50),
                      border: pw.Border.all(
                        color: invoice.status == 'completed'
                            ? PdfColors.green700
                            : (invoice.status == 'held'
                                ? PdfColors.amber800
                                : PdfColors.red700),
                        width: 0.5,
                      ),
                      borderRadius: const pw.BorderRadius.all(
                        pw.Radius.circular(3),
                      ),
                    ),
                    child: pw.Text(
                      invoice.statusArabic,
                      style: pw.TextStyle(
                        font: boldFont,
                        fontSize: width80mm ? 7.5 : 6.5,
                        color: invoice.status == 'completed'
                            ? PdfColors.green800
                            : (invoice.status == 'held'
                                ? PdfColors.amber900
                                : PdfColors.red800),
                      ),
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 3),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'التاريخ: ${dateFmt.format(invoice.createdAt)}',
                    style: pw.TextStyle(
                      font: baseFont,
                      fontSize: width80mm ? 7.5 : 6.5,
                      color: PdfColors.grey700,
                    ),
                  ),
                  pw.Text(
                    'طريقة الدفع: ${invoice.paymentMethodArabic}',
                    style: pw.TextStyle(
                      font: baseFont,
                      fontSize: width80mm ? 7.5 : 6.5,
                      color: PdfColors.grey700,
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 3),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'العميل: ${invoice.customerName ?? 'عميل نقدي'}',
                    style: pw.TextStyle(
                      font: boldFont,
                      fontSize: width80mm ? 8 : 7,
                      color: PdfColors.grey800,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 5),

        // جدول الأصناف بتنسيق متوازن واحترافي: تكبير خانة الصنف وتصغير الكمية والسعر والإجمالي
        pw.Table(
          border: pw.TableBorder.all(
            color: PdfColors.grey400,
            width: 0.5,
          ),
          columnWidths: {
            0: const pw.FlexColumnWidth(56),
            1: const pw.FlexColumnWidth(12),
            2: const pw.FlexColumnWidth(16),
            3: const pw.FlexColumnWidth(16),
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(
                color: PdfColors.grey200,
              ),
              children: [
                _tableCell('الصنف', boldFont, width80mm ? 8 : 7,
                    bold: true, align: pw.Alignment.centerRight),
                _tableCell('الكمية', boldFont, width80mm ? 8 : 7,
                    bold: true, align: pw.Alignment.center),
                _tableCell('السعر', boldFont, width80mm ? 8 : 7,
                    bold: true, align: pw.Alignment.center),
                _tableCell('الإجمالي', boldFont, width80mm ? 8 : 7,
                    bold: true, align: pw.Alignment.centerLeft),
              ],
            ),
            ...invoice.items.map(
              (item) => pw.TableRow(
                children: [
                  _tableCell(
                    item.productName ?? 'منتج',
                    baseFont,
                    width80mm ? 7.5 : 6.5,
                    align: pw.Alignment.centerRight,
                  ),
                  _tableCell(
                    '${item.quantity}',
                    baseFont,
                    width80mm ? 7.5 : 6.5,
                    align: pw.Alignment.center,
                  ),
                  _tableCell(
                    item.unitPrice.toStringAsFixed(0),
                    baseFont,
                    width80mm ? 7.5 : 6.5,
                    align: pw.Alignment.center,
                  ),
                  _tableCell(
                    item.lineTotal.toStringAsFixed(0),
                    boldFont,
                    width80mm ? 7.5 : 6.5,
                    align: pw.Alignment.centerLeft,
                    bold: true,
                  ),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 5),

        // بطاقة الإجماليات
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 5),
          decoration: pw.BoxDecoration(
            color: PdfColors.grey100,
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
            border: pw.Border.all(color: PdfColors.grey300, width: 0.6),
          ),
          child: pw.Column(
            children: [
              _row('الإجمالي الفرعي', AppStrings.money(invoice.subtotal), baseFont, size: width80mm ? 8 : 7),
              if (invoice.discount > 0)
                _row('الخصم', '-${AppStrings.money(invoice.discount)}', baseFont, size: width80mm ? 8 : 7, valueColor: PdfColors.red700),
              if (invoice.tax > 0)
                _row('الضريبة', AppStrings.money(invoice.tax), baseFont, size: width80mm ? 8 : 7),
              pw.SizedBox(height: 2),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(vertical: 3),
                decoration: const pw.BoxDecoration(
                  border: pw.Border(
                    top: pw.BorderSide(width: 0.7, color: PdfColors.grey400),
                    bottom: pw.BorderSide(width: 0.7, color: PdfColors.grey400),
                  ),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    _boldText('الإجمالي', boldFont, size: width80mm ? 9.5 : 8.5),
                    _boldText(
                      AppStrings.money(invoice.total),
                      boldFont,
                      alignRight: true,
                      size: width80mm ? 9.5 : 8.5,
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 2),
              _row('المدفوع', AppStrings.money(invoice.paidAmount), baseFont, size: width80mm ? 8 : 7),
              if (invoice.isChangePositive)
                _row('الباقي', AppStrings.money(invoice.changeDue), baseFont, size: width80mm ? 8 : 7)
              else if (invoice.remainingOnCustomer > 0)
                _row(
                  'المتبقي على العميل',
                  AppStrings.money(invoice.remainingOnCustomer),
                  baseFont,
                  size: width80mm ? 8 : 7,
                  valueColor: PdfColors.red700,
                ),
            ],
          ),
        ),
        pw.SizedBox(height: 6),
        _divider(),
        pw.SizedBox(height: 5),

        // سياسة الاسترجاع
        pw.Center(
          child: pw.Text(
            'البضاعة المباعة ترد وتستبدل خلال 14 يوماً مع أصل الفاتورة',
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              font: baseFont,
              fontSize: width80mm ? 7 : 6,
              color: PdfColors.grey700,
            ),
          ),
        ),
        pw.SizedBox(height: 5),

        // باركود الفاتورة
        pw.Center(
          child: pw.BarcodeWidget(
            barcode: pw.Barcode.code128(),
            data: invoice.invoiceNumber,
            width: width80mm ? 120 : 95,
            height: width80mm ? 24 : 20,
            drawText: false,
          ),
        ),
        pw.SizedBox(height: 2),
        pw.Center(
          child: pw.Text(
            invoice.invoiceNumber,
            style: pw.TextStyle(
              font: baseFont,
              fontSize: width80mm ? 7.5 : 6.5,
              color: PdfColors.grey700,
            ),
          ),
        ),
        pw.SizedBox(height: 5),

        // عبارة الشكر
        pw.Center(
          child: pw.Text(
            'شكراً لتعاملكم معنا ★ نسعد بخدمتكم دائماً',
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              font: boldFont,
              fontSize: width80mm ? 8.5 : 7.5,
              color: PdfColors.grey900,
            ),
          ),
        ),
      ],
    );
  }

  /// خلية جدول: نص محاذي بمسافة داخلية موحدة
  static pw.Widget _tableCell(
    String text,
    pw.Font font,
    double size, {
    bool bold = false,
    pw.Alignment align = pw.Alignment.centerRight,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 2.5),
      child: pw.Align(
        alignment: align,
        child: pw.Text(
          text,
          softWrap: true,
          style: pw.TextStyle(
            font: font,
            fontSize: size,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
      ),
    );
  }

  static pw.Widget _divider() {
    return pw.Container(
      height: 0.5,
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(width: 0.5, color: PdfColors.grey400)),
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
      padding: const pw.EdgeInsets.symmetric(vertical: 1.2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              font: font,
              fontSize: size,
              color: labelColor ?? PdfColors.grey700,
            ),
          ),
          pw.Text(
            value,
            style: pw.TextStyle(
              font: font,
              fontSize: size,
              color: valueColor ?? PdfColors.grey900,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _boldText(
    String text,
    pw.Font font, {
    double size = 8,
    bool alignRight = false,
  }) {
    return alignRight
        ? pw.Align(
            alignment: pw.Alignment.centerLeft,
            child: pw.Text(
              text,
              style: pw.TextStyle(font: font, fontSize: size),
            ),
          )
        : pw.Text(
            text,
            style: pw.TextStyle(font: font, fontSize: size),
          );
  }

  /// فتح نافذة الطباعة لاختيار الطابعة الحرارية.
  ///
  /// مقاس الورقة المطلوب = مقاس اللفة المختار (80/58مم) — النسخة
  /// المحلية من printing تطلبه في حوار الطباعة كمقاس مخصص بعدّاته
  /// الدقيقة (لا يسقط على A4)، ومع forceCustomPrintPaper وهو المعامل
  /// الفعلي على iOS. إن غيّر المستخدم الورقة داخل حوار النظام يعاد بناء
  /// الوثيقة لتناسبها بالضبط: لفة حرارية للمقاسات الحرارية، وفاتورة
  /// احترافية بمقاس الورقة للمقاسات الكبيرة (onLayout متجاوب).
  static Future<void> printReceipt({
    required SaleInvoice invoice,
    required bool width80mm,
    String? storeName,
    String? storePhone,
    String? storeLogoPath,
  }) async {
    // مقاس الورق المعلن = مقاس اللفّة حسب النوع المختار (80/58مم).
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

    await Printing.layoutPdf(
      name: 'فاتورة_${invoice.invoiceNumber}',
      format: paperFormat,
      forceCustomPrintPaper: true,
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

  /// مشاركة الإيصال كصورة كاملة (PNG)، مع بديل PDF عند الحاجة.
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
    );
    try {
      // تحويل الإيصال إلى صورة كاملة عالية الدقة لمشاركتها كصورة مطابقة لما يظهر بالتطبيق
      final rasterStream = Printing.raster(pdfBytes, pages: [0], dpi: 200);
      final page = await rasterStream.first;
      final imageBytes = await page.toPng();
      await Printing.sharePdf(
        bytes: imageBytes,
        filename: 'فاتورة_${invoice.invoiceNumber}.png',
      );
    } catch (_) {
      // بديل آمن: مشاركة ملف PDF إذا تعذر التحويل لصورة على المنصة
      await Printing.sharePdf(
        bytes: pdfBytes,
        filename: 'فاتورة_${invoice.invoiceNumber}.pdf',
      );
    }
  }
}
