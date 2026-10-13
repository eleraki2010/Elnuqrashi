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
  ///  - عرض حراري (57/80مم): الإيصال الأصلي على اللفة بنفس قواعده
  ///    (190مم قياسية مع توسيط عمودي إن احتوى، أو ارتفاع ذاتي).
  ///  - عرض أكبر (A4/...): فاتورة احترافية بمقاس الورقة بالضبط مع
  ///    ترويسة وتذييل مكررين وتقسيم تلقائي للصفحات الطويلة — حتى لا
  ///    يظهر الإيصال مقصوصًا أو مشوهًا على ورق ليس لفته.
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

    // ورقة كبيرة (A4/... حسب اختيار المستخدم): فاتورة احترافية بمقاس
    // الورقة المطلوب بالضبط — ترويسة وتذييل مكرران في كل صفحة، وجدول
    // الأصناف يتوزع تلقائياً على الصفحات الطويلة (لا اقتطاع محتوى).
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat(
          requested.width,
          requested.height,
          marginAll: 30.0,
        ),
        textDirection: pw.TextDirection.rtl,
        mainAxisAlignment: pw.MainAxisAlignment.center,
        theme: pw.ThemeData.withFont(base: baseFont, bold: boldFont),
        header: (ctx) =>
            _a4Header(invoice, storeName, baseFont, boldFont),
        footer: (ctx) => pw.Center(
          child: pw.Text(
            'صفحة ${ctx.pageNumber}',
            style: pw.TextStyle(
              font: baseFont,
              fontSize: 8,
              color: PdfColors.grey600,
            ),
          ),
        ),
        build: (ctx) => [
          _a4Meta(invoice, baseFont, boldFont),
          pw.SizedBox(height: 10),
          _a4ItemsTable(invoice, baseFont, boldFont),
          pw.SizedBox(height: 10),
          _a4Totals(invoice, baseFont, boldFont),
          pw.SizedBox(height: 14),
          pw.Center(
            child: pw.Text(
              'شكراً لتعاملكم معنا',
              style: pw.TextStyle(font: baseFont, fontSize: 10),
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Center(
            child: pw.Text(
              'نتمنى لكم يوماً سعيداً',
              style: pw.TextStyle(
                font: baseFont,
                fontSize: 8.5,
                color: PdfColors.grey600,
              ),
            ),
          ),
        ],
      ),
    );
    return doc.save();
  }

  /// ترويسة A4 مكررة في كل صفحة.
  static pw.Widget _a4Header(
    SaleInvoice invoice,
    String? storeName,
    pw.Font base,
    pw.Font bold,
  ) {
    return pw.Column(
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              storeName?.trim().isEmpty == false
                  ? storeName!
                  : AppStrings.STORE_NAME,
              style: pw.TextStyle(
                font: bold,
                fontSize: 13,
                color: PdfColors.black,
              ),
            ),
            pw.Text(
              'فاتورة مبيعات رقم ${invoice.invoiceNumber}',
              style: pw.TextStyle(
                font: base,
                fontSize: 10,
                color: PdfColors.grey700,
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 5),
        pw.Container(
          height: 0.8,
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              top: pw.BorderSide(width: 0.8, color: PdfColors.black),
            ),
          ),
        ),
      ],
    );
  }

  /// بيانات الفاتورة على A4 داخل صندوق محدد.
  static pw.Widget _a4Meta(SaleInvoice invoice, pw.Font base, pw.Font bold) {
    final dateFmt = DateFormat('yyyy/MM/dd - hh:mm a');
    return pw.Container(
      width: 430,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.black, width: 0.8),
      ),
      child: pw.Column(
        children: [
          _a4Row('رقم الفاتورة', invoice.invoiceNumber, base),
          _a4Row('التاريخ', dateFmt.format(invoice.createdAt), base),
          _a4Row('العميل', invoice.customerName ?? 'عميل نقدي', base),
          _a4Row('طريقة الدفع', invoice.paymentMethodArabic, base),
        ],
      ),
    );
  }

  /// جدول الأصناف على A4 بحدود واضحة (يتوزع على الصفحات تلقائياً).
  static pw.Table _a4ItemsTable(
    SaleInvoice invoice,
    pw.Font base,
    pw.Font bold,
  ) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.black, width: 0.5),
      columnWidths: {
        0: const pw.FixedColumnWidth(210),
        1: const pw.FixedColumnWidth(60),
        2: const pw.FixedColumnWidth(80),
        3: const pw.FixedColumnWidth(80),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey300),
          children: [
            _tableCell('الصنف', bold, 10, bold: true),
            _tableCell('الكمية', bold, 10,
                bold: true, align: pw.Alignment.center),
            _tableCell('السعر', bold, 10,
                bold: true, align: pw.Alignment.centerLeft),
            _tableCell('الإجمالي', bold, 10,
                bold: true, align: pw.Alignment.centerLeft),
          ],
        ),
        ...invoice.items.map(
          (item) => pw.TableRow(
            children: [
              _tableCell(item.productName ?? 'منتج', base, 10),
              _tableCell('${item.quantity}', base, 10,
                  align: pw.Alignment.center),
              _tableCell(item.unitPrice.toStringAsFixed(0), base, 10,
                  align: pw.Alignment.centerLeft),
              _tableCell(item.lineTotal.toStringAsFixed(0), base, 10,
                  align: pw.Alignment.centerLeft),
            ],
          ),
        ),
      ],
    );
  }

  /// الإجماليات على A4.
  static pw.Widget _a4Totals(SaleInvoice invoice, pw.Font base, pw.Font bold) {
    return pw.Container(
      width: 430,
      child: pw.Column(
        children: [
          _a4Row('الإجمالي الفرعي', AppStrings.money(invoice.subtotal), base),
          if (invoice.discount > 0)
            _a4Row('الخصم', '-${AppStrings.money(invoice.discount)}', base),
          if (invoice.tax > 0)
            _a4Row('الضريبة', AppStrings.money(invoice.tax), base),
          pw.SizedBox(height: 6),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(vertical: 5),
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                top: pw.BorderSide(width: 0.8),
                bottom: pw.BorderSide(width: 0.8),
              ),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'الإجمالي',
                  style: pw.TextStyle(font: bold, fontSize: 12),
                ),
                pw.Text(
                  AppStrings.money(invoice.total),
                  style: pw.TextStyle(font: bold, fontSize: 12),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 6),
          _a4Row('المدفوع', AppStrings.money(invoice.paidAmount), base),
          if (invoice.isChangePositive)
            _a4Row('الباقي', AppStrings.money(invoice.changeDue), base)
          else if (invoice.remainingOnCustomer > 0)
            _a4Row(
              'المتبقي على العميل',
              AppStrings.money(invoice.remainingOnCustomer),
              base,
            ),
        ],
      ),
    );
  }

  /// صف «تسمية/قيمة» على A4.
  static pw.Widget _a4Row(String label, String value, pw.Font font) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label,
              style: pw.TextStyle(font: font, fontSize: 10, color: PdfColors.grey700)),
          pw.Text(value, style: pw.TextStyle(font: font, fontSize: 10)),
        ],
      ),
    );
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

  /// محتوى الإيصال (بلا إطار الصفحة): ترويسة المحل + بيانات الفاتورة +
  /// جدول الأصناف المبيّن بالحدود + الإجماليات + التذييل. يُستخدم لللفة
  /// الحرارية وللإيصال المتمركز على A4 معًا.
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
        // ترويسة المحل (الشعار بجوار الاسم — لا فوقه)
        pw.Center(
          child: logo == null
              ? pw.Text(
                  storeName ?? AppStrings.STORE_NAME,
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(
                    font: boldFont,
                    fontSize: width80mm ? 13 : 11,
                  ),
                )
              : pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.center,
                  mainAxisSize: pw.MainAxisSize.min,
                  children: [
                    pw.Image(logo, width: 34, height: 34),
                    pw.SizedBox(width: 6),
                    pw.Text(
                      storeName ?? AppStrings.STORE_NAME,
                      style: pw.TextStyle(
                        font: boldFont,
                        fontSize: width80mm ? 13 : 11,
                      ),
                    ),
                  ],
                ),
        ),
        if (storePhone != null && storePhone.isNotEmpty) ...[
          pw.SizedBox(height: 2),
          pw.Center(
            child: pw.Text(
              'هاتف: $storePhone',
              style: pw.TextStyle(
                font: baseFont,
                fontSize: width80mm ? 8 : 7,
              ),
            ),
          ),
        ],
        pw.SizedBox(height: 4),
        pw.Center(
          child: pw.Text(
            'فاتورة مبيعات',
            style: pw.TextStyle(
              font: baseFont,
              fontSize: width80mm ? 9 : 8,
              color: PdfColors.grey700,
            ),
          ),
        ),
        pw.SizedBox(height: 6),
        _divider(),
        pw.SizedBox(height: 4),
        // بيانات الفاتورة
        _row('رقم الفاتورة', invoice.invoiceNumber, baseFont),
        _row('التاريخ', dateFmt.format(invoice.createdAt), baseFont),
        _row('العميل', invoice.customerName ?? 'عميل نقدي', baseFont),
        _divider(),
        pw.SizedBox(height: 4),
        // جدول الأصناف بإطار وحدود واضحة (تنسيق احترافي مطابق
        // للفواتير في برامج نقاط البيع): صف عناوين مُظلَل،
        // كل صنف في خلية، والكمية وسط عمودها والأسعار يسارها.
        pw.Table(
          border: pw.TableBorder.all(
            color: PdfColors.black,
            width: 0.45,
          ),
          columnWidths: {
            0: const pw.FlexColumnWidth(5),
            1: const pw.FlexColumnWidth(2),
            2: const pw.FlexColumnWidth(3),
            3: const pw.FlexColumnWidth(3),
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(
                color: PdfColors.grey300,
              ),
              children: [
                _tableCell('الصنف', boldFont, width80mm ? 8 : 7,
                    bold: true),
                _tableCell('الكمية', boldFont, width80mm ? 8 : 7,
                    bold: true, align: pw.Alignment.center),
                _tableCell(
                    'السعر', boldFont, width80mm ? 8 : 7,
                    bold: true,
                    align: pw.Alignment.centerLeft),
                _tableCell(
                    'الإجمالي', boldFont, width80mm ? 8 : 7,
                    bold: true,
                    align: pw.Alignment.centerLeft),
              ],
            ),
            // الأصناف (أرقام صحيحة بلا كسور)
            ...invoice.items.map(
              (item) => pw.TableRow(
                children: [
                  _tableCell(
                      item.productName ?? 'منتج',
                      baseFont,
                      width80mm ? 8 : 7),
                  _tableCell(
                      '${item.quantity}',
                      baseFont,
                      width80mm ? 8 : 7,
                      align: pw.Alignment.center),
                  _tableCell(
                      item.unitPrice.toStringAsFixed(0),
                      baseFont,
                      width80mm ? 8 : 7,
                      align: pw.Alignment.centerLeft),
                  _tableCell(
                      item.lineTotal.toStringAsFixed(0),
                      baseFont,
                      width80mm ? 8 : 7,
                      align: pw.Alignment.centerLeft),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 5),
        // الإجماليات (أرقام صحيحة بلا كسور)
        _row(
          'الإجمالي الفرعي',
          AppStrings.money(invoice.subtotal),
          baseFont,
        ),
        if (invoice.discount > 0)
          _row(
            'الخصم',
            '-${AppStrings.money(invoice.discount)}',
            baseFont,
          ),
        if (invoice.tax > 0)
          _row('الضريبة', AppStrings.money(invoice.tax), baseFont),
        pw.SizedBox(height: 3),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 3),
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              top: pw.BorderSide(width: 0.7),
              bottom: pw.BorderSide(width: 0.7),
            ),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              _boldText('الإجمالي', boldFont, size: width80mm ? 10 : 9),
              _boldText(
                AppStrings.money(invoice.total),
                boldFont,
                alignRight: true,
                size: width80mm ? 10 : 9,
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 3),
        _row('المدفوع', AppStrings.money(invoice.paidAmount), baseFont),
        if (invoice.isChangePositive)
          _row('الباقي', AppStrings.money(invoice.changeDue), baseFont)
        else if (invoice.remainingOnCustomer > 0)
          _row(
            'المتبقي على العميل',
            AppStrings.money(invoice.remainingOnCustomer),
            baseFont,
          ),
        _row('طريقة الدفع', invoice.paymentMethodArabic, baseFont),
        pw.SizedBox(height: 8),
        _divider(),
        pw.SizedBox(height: 6),

        // سياسة الاسترجاع والضمان (معايير نقاط البيع المحاسبية)
        pw.Center(
          child: pw.Text(
            'البضاعة المباعة ترد وتستبدل خلال 14 يوماً مع أصل الفاتورة',
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              font: baseFont,
              fontSize: width80mm ? 7.5 : 6.5,
              color: PdfColors.grey700,
            ),
          ),
        ),
        pw.SizedBox(height: 6),

        // باركود الفاتورة للبحث والاسترجاع السريع
        pw.Center(
          child: pw.BarcodeWidget(
            barcode: pw.Barcode.code128(),
            data: invoice.invoiceNumber,
            width: width80mm ? 120 : 95,
            height: width80mm ? 26 : 22,
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
        pw.SizedBox(height: 6),

        // عبارة الشكر والترحيب
        pw.Center(
          child: pw.Text(
            'شكراً لتعاملكم معنا ★ نسعد بخدمتكم دائماً',
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              font: boldFont,
              fontSize: width80mm ? 8.5 : 7.5,
            ),
          ),
        ),
      ],
    );
  }

  /// خلية جدول: نص محاذي (يمين للعناوين العربية، وسط للكميات،
  /// يسار للمبالغ) بمسافة داخلية موحدة.
  static pw.Widget _tableCell(
    String text,
    pw.Font font,
    double size, {
    bool bold = false,
    pw.Alignment align = pw.Alignment.centerRight,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 2),
      child: pw.Align(
        alignment: align,
        child: pw.Text(
          text,
          style: pw.TextStyle(
            font: font,
            fontSize: size,
            fontWeight:
                bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
      ),
    );
  }

  static pw.Widget _divider() {
    return pw.Container(
      height: 0.5,
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(width: 0.5)),
      ),
    );
  }

  static pw.Widget _row(String label, String value, pw.Font font) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: pw.TextStyle(font: font, fontSize: 8)),
          pw.Text(value, style: pw.TextStyle(font: font, fontSize: 8)),
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

  /// مشاركة الإيصال كـ PDF.
  static Future<void> shareReceipt({
    required SaleInvoice invoice,
    required bool width80mm,
    String? storeName,
    String? storePhone,
    String? storeLogoPath,
  }) async {
    final bytes = await buildReceiptPdf(
      invoice: invoice,
      width80mm: width80mm,
      storeName: storeName,
      storePhone: storePhone,
      storeLogoPath: storeLogoPath,
    );
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'فاتورة_${invoice.invoiceNumber}.pdf',
    );
  }
}
