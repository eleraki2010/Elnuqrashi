import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:alnokrashy_pos/core/services/document_share_service.dart';
import 'package:alnokrashy_pos/data/models/customer.dart';
import 'package:alnokrashy_pos/data/models/payment.dart';
import 'package:alnokrashy_pos/data/models/sale_invoice.dart';
import 'package:alnokrashy_pos/data/models/supplier.dart';
import 'package:alnokrashy_pos/data/models/purchase_invoice.dart';
import 'package:alnokrashy_pos/data/repositories/customer_repository.dart';
import 'package:alnokrashy_pos/data/repositories/supplier_repository.dart';
import 'package:alnokrashy_pos/presentation/widgets/customer_statement_pdf.dart';
import 'package:alnokrashy_pos/presentation/widgets/supplier_statement_pdf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Statement PDF Generation Tests', () {
    test('CustomerStatementPdf builds multi-page PDF cleanly without infinite layout loop', () async {
      final now = DateTime(2025, 1, 1);
      final customer = Customer(
        id: 'cust_1',
        name: 'عميل تجريبي للطباعة',
        phone: '01012345678',
        balanceDue: 25000.0,
        createdAt: now,
        updatedAt: now,
      );

      final invoices = List<SaleInvoice>.generate(40, (i) {
        return SaleInvoice(
          id: 'inv_$i',
          invoiceNumber: '${1000 + i}',
          customerId: 'cust_1',
          total: 1000.0,
          subtotal: 1000.0,
          paidAmount: 500.0,
          changeDue: 0.0,
          discount: 0.0,
          paymentMethod: 'credit',
          status: 'completed',
          createdAt: now.add(Duration(days: i)),
        );
      });

      final payments = List<Payment>.generate(20, (i) {
        return Payment(
          id: 'pay_$i',
          partyType: 'customer',
          partyId: 'cust_1',
          amount: 250.0,
          direction: 'in',
          note: 'دفعة حساب #$i',
          createdAt: now.add(Duration(days: i * 2)),
        );
      });

      final statement = CustomerStatement(
        customer: customer,
        invoices: invoices,
        returns: [],
        payments: payments,
      );

      final pdfBytes = await CustomerStatementPdf.buildStatementPdf(
        statement: statement,
        storeName: 'متجر النقراشي التجريبي',
      );

      expect(pdfBytes, isNotNull);
      expect(pdfBytes.length, greaterThan(1000));
    });

    test('SupplierStatementPdf builds multi-page PDF cleanly without overflowing single page', () async {
      final now = DateTime(2025, 1, 1);
      final supplier = Supplier(
        id: 'sup_1',
        name: 'مورد تجريبي للطباعة',
        phone: '01234567890',
        balanceOwed: 50000.0,
        createdAt: now,
        updatedAt: now,
      );

      final purchases = List<PurchaseInvoice>.generate(35, (i) {
        return PurchaseInvoice(
          id: 'pur_$i',
          supplierId: 'sup_1',
          total: 2000.0,
          tax: 0.0,
          paidAmount: 1000.0,
          createdAt: now.add(Duration(days: i)),
        );
      });

      final payments = List<Payment>.generate(15, (i) {
        return Payment(
          id: 'pay_s_$i',
          partyType: 'supplier',
          partyId: 'sup_1',
          amount: 500.0,
          direction: 'out',
          note: 'سداد دفعة توريد #$i',
          createdAt: now.add(Duration(days: i * 2)),
        );
      });

      final statement = SupplierStatement(
        supplier: supplier,
        purchases: purchases,
        payments: payments,
        returns: [],
      );

      final pdfBytes = await SupplierStatementPdf.buildStatementPdf(
        statement: statement,
        storeName: 'متجر النقراشي التجريبي',
      );

      expect(pdfBytes, isNotNull);
      expect(pdfBytes.length, greaterThan(1000));
    });

    test('DocumentShareService combines multiple PNG images into a single image correctly', () async {
      // Create two small sample PNG images using PictureRecorder
      Future<Uint8List> createSamplePng(int colorVal) async {
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder, const ui.Rect.fromLTWH(0, 0, 100, 100));
        canvas.drawColor(ui.Color(colorVal), ui.BlendMode.src);
        final pic = recorder.endRecording();
        final img = await pic.toImage(100, 100);
        final bd = await img.toByteData(format: ui.ImageByteFormat.png);
        return bd!.buffer.asUint8List();
      }

      final png1 = await createSamplePng(0xFFFF0000); // Red
      final png2 = await createSamplePng(0xFF00FF00); // Green

      final combined = await DocumentShareService.combinePngImages([png1, png2]);
      expect(combined, isNotNull);
      expect(combined.length, greaterThan(100));

      final codec = await ui.instantiateImageCodec(combined);
      final frame = await codec.getNextFrame();
      expect(frame.image.width, equals(100));
      expect(frame.image.height, equals(200)); // 100 + 100 stitched
    });
  });
}
