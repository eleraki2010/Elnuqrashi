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

    final body = _receiptBody(
      invoice: invoice,
      width80mm: width80mm,
      storeName: storeName,
      storePhone: storePhone,
      logo: logo,
      baseFont: baseFont,
      boldFont: boldFont,
      isLargePaper: true,
    );

    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: const PdfPageFormat(480, double.infinity, marginAll: 16),
        build: (context) {
          return pw.Theme(
            data: pw.ThemeData.withFont(base: baseFont, bold: boldFont),
            child: pw.Directionality(
              textDirection: pw.TextDirection.rtl,
              child: pw.Container(
                width: 440,
                padding: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: pw.BoxDecoration(
                  color: PdfColors.white,
                  border: pw.Border.all(color: _colorBorder, width: 1),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(16)),
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
  ///  - عرض حراري (57/80مم): الإيصال على اللفة بنفس أبعاده ومطابق للتطبيق.
  ///  - عرض أكبر (A4/تابلت/...): عرض نفس الفاتورة المتطابقة تماماً 1:1 مع المعروضة
  ///    على التطبيق في منتصف الصفحة بنفس الحجم والألوان والخطوط الأنيقة.
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
    // بناء الفاتورة لتطابق شاشة التطبيق تماماً (كارت أنيق بعرض 440 وخطوط واضحة)
    final body = _receiptBody(
      invoice: invoice,
      width80mm: width80mm,
      storeName: storeName,
      storePhone: storePhone,
      logo: logo,
      baseFont: baseFont,
      boldFont: boldFont,
      isLargePaper: true,
    );

    const cardWidth = 440.0;

    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: requested,
        margin: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        build: (context) {
          return pw.Theme(
            data: pw.ThemeData.withFont(base: baseFont, bold: boldFont),
            child: pw.Directionality(
              textDirection: pw.TextDirection.rtl,
              child: pw.Center(
                child: pw.Container(
                  width: cardWidth,
                  padding: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.white,
                    border: pw.Border.all(color: _colorBorder, width: 1),
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(16)),
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
      isLargePaper: false,
    );

    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: pageFormat,
        margin: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        build: (context) {
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
    final double titleSize = isLargePaper ? 18.0 : (width80mm ? 13.0 : 11.0);
    final double logoSize = isLargePaper ? 38.0 : (width80mm ? 30.0 : 24.0);
    final double subSize = isLargePaper ? 11.5 : (width80mm ? 8.0 : 7.0);
    final double typeSize = isLargePaper ? 12.0 : (width80mm ? 9.0 : 8.0);
    final double invoiceNumSize = isLargePaper ? 13.0 : (width80mm ? 8.5 : 7.5);
    final double badgeSize = isLargePaper ? 11.0 : (width80mm ? 7.5 : 6.5);
    final double dateSize = isLargePaper ? 11.5 : (width80mm ? 8.0 : 7.0);
    final double customerSize = isLargePaper ? 12.0 : (width80mm ? 8.0 : 7.0);
    final double tableHeaderSize = isLargePaper ? 12.0 : (width80mm ? 8.0 : 7.0);
    final double tableDataSize = isLargePaper ? 12.0 : (width80mm ? 7.5 : 6.5);
    final double totalLabelSize = isLargePaper ? 15.0 : (width80mm ? 9.5 : 8.5);
    final double totalValSize = isLargePaper ? 17.0 : (width80mm ? 10.0 : 9.0);
    final double paidSize = isLargePaper ? 12.5 : (width80mm ? 8.0 : 7.0);
    final double changeSize = isLargePaper ? 12.5 : (width80mm ? 8.0 : 7.0);
    final double footerSize = isLargePaper ? 11.0 : (width80mm ? 7.0 : 6.0);
    final double barcodeWidth = isLargePaper ? 130.0 : (width80mm ? 110.0 : 90.0);
    final double barcodeHeight = isLargePaper ? 26.0 : (width80mm ? 22.0 : 18.0);
    final double thankYouSize = isLargePaper ? 12.5 : (width80mm ? 8.5 : 7.5);

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
            'شكراً لتعاملكم معنا ★ نسعد بخدمتكم دائماً',
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
      asCard: true,
    );
    try {
      final rasterStream = Printing.raster(pdfBytes, pages: [0], dpi: 200);
      final page = await rasterStream.first;
      final imageBytes = await page.toPng();
      await Printing.sharePdf(
        bytes: imageBytes,
        filename: 'فاتورة_${invoice.invoiceNumber}.png',
      );
    } catch (_) {
      await Printing.sharePdf(
        bytes: pdfBytes,
        filename: 'فاتورة_${invoice.invoiceNumber}.pdf',
      );
    }
  }
}
