import 'dart:convert';

import 'package:alnokrashy_pos/data/models/sale_invoice.dart';
import 'package:alnokrashy_pos/data/models/sale_invoice_item.dart';
import 'package:alnokrashy_pos/presentation/widgets/thermal_receipt_printer.dart';
import 'package:pdf/pdf.dart';
import 'package:flutter_test/flutter_test.dart';

/// اختبار توسيط الفاتورة عمودياً في الصفحة القياسية (190mm) عند الطباعة.
void main() {
  SaleInvoice buildInvoice({required int itemCount}) {
    final now = DateTime(2026, 10, 4, 12);
    return SaleInvoice(
      id: 'inv-test',
      invoiceNumber: '20261001',
      subtotal: 100.0,
      total: 100.0,
      paidAmount: 100.0,
      changeDue: 0.0,
      paymentMethod: 'cash',
      status: 'completed',
      createdAt: now,
      items: List.generate(
        itemCount,
        (i) => SaleInvoiceItem(
          id: 'item-$i',
          invoiceId: 'inv-test',
          productId: 'p-$i',
          quantity: 1,
          unitPrice: 10,
          lineTotal: 10,
          productName: 'منتج رقم $i',
        ),
      ),
    );
  }

  /// قراءة أبعاد الصفحة (MediaBox) من بايتات الـ PDF مباشرة.
  (double width, double height) mediaBox(List<int> bytes) {
    final text = utf8.decode(bytes, allowMalformed: true);
    final match = RegExp(
      r'/MediaBox\s*\[\s*[-\d.]+\s+[-\d.]+\s+([-\d.]+)\s+([-\d.]+)\s*\]',
    ).firstMatch(text);
    expect(match, isNotNull);
    return (
      double.parse(match!.group(1)!),
      double.parse(match.group(2)!),
    );
  }

  testWidgets('short receipt has compact dynamic height matching content',
      (tester) async {
    // تحميل خطوط الأصول يحتاج وقتاً حقيقياً (runAsync).
    final bytes = await tester.runAsync<List<int>>(() async {
      return await ThermalReceiptPrinter.buildReceiptPdf(
        invoice: buildInvoice(itemCount: 2),
        width80mm: true,
      );
    });
    final (width, height) = mediaBox(bytes!);
    // عرض لفة 80mm وارتفاع ديناميكي مقتضب يتناسب مع الصنفين (دون مط أو مساحات بيضاء فارغة)
    expect(width, closeTo(80 * PdfPageFormat.mm, 0.5));
    expect(height, lessThan(190 * PdfPageFormat.mm));
    expect(height, greaterThan(80 * PdfPageFormat.mm));
  });

  testWidgets('long receipt keeps auto height instead of clipping',
      (tester) async {
    final bytes = await tester.runAsync<List<int>>(() async {
      return await ThermalReceiptPrinter.buildReceiptPdf(
        invoice: buildInvoice(itemCount: 40),
        width80mm: true,
      );
    });
    final (width, height) = mediaBox(bytes!);
    // المحتوى أطول من 190mm → يتمدد الارتفاع تلقائياً دون أي اقتصاص
    expect(height, greaterThan(190 * PdfPageFormat.mm + 1));
    expect(width, closeTo(80 * PdfPageFormat.mm, 0.5));
  });
}
