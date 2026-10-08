// ignore_for_file: avoid_print
import 'package:alnokrashy_pos/data/models/sale_invoice.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('exact screen expression on List<SaleInvoice>', () {
    final invoice = SaleInvoice(
      id: 'inv-1',
      invoiceNumber: '20260100',
      subtotal: 200,
      total: 200,
      paidAmount: 200,
      changeDue: 0,
      paymentMethod: 'cash',
      status: 'completed',
      createdAt: DateTime.now(),
    );

    final data = <SaleInvoice>[invoice];

    // نفس التعبير في returns_screen.dart:
    final invoices = (data as List?)?.cast() ?? [];
    print('invoices runtimeType: ${invoices.runtimeType}, len: ${invoices.length}');

    final completedInvoices = invoices
        .where((dynamic i) => (i as dynamic).status == 'completed')
        .toList();
    print('completed: ${completedInvoices.length}');
    expect(completedInvoices, hasLength(1));

    // سلوك value في DropdownMenuItem مع dynamic:
    final dynamic d = invoice;
    print('dynamic id: ${d.id} status: ${d.status}');
  });
}
