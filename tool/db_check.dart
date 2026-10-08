// ignore_for_file: avoid_print
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// فحص سريع لقاعدة بيانات التطبيق الحية: قيم NULL في فواتير البيع.
void main() async {
  sqfliteFfiInit();
  final path =
      r'C:\Users\elera\AppData\Roaming\com.alnokrashy\alnokrashy_pos\alnokrashy_pos.db';
  final db = await databaseFactoryFfi.openDatabase(path);

  final rows = await db.rawQuery(
    'SELECT id, invoice_number, subtotal, total, paid_amount, change_due, payment_method, status, customer_id, created_at FROM sale_invoices ORDER BY created_at',
  );
  print('=== sale_invoices: ${rows.length} rows ===');
  for (final r in rows) {
    final nulls = <String>[];
    for (final col in ['subtotal', 'total', 'paid_amount', 'change_due']) {
      if (r[col] == null) nulls.add('$col=NULL');
    }
    print(
        '#${r['invoice_number']} | ${r['status']} | ${r['payment_method']} | sub=${r['subtotal']} tot=${r['total']} paid=${r['paid_amount']} chg=${r['change_due']} cust=${r['customer_id'] ?? '-'}${nulls.isNotEmpty ? '  <<<< ${nulls.join(',')}' : ''}');
  }

  final cust = await db.rawQuery(
    'SELECT id, name, balance_due, payment_due_date FROM customers',
  );
  print('=== customers: ${cust.length} ===');
  for (final r in cust) {
    print('${r['name']} | balance_due=${r['balance_due']}');
  }

  final rets = await db.rawQuery(
    'SELECT count(*) c FROM return_invoices',
  );
  final retItems = await db.rawQuery(
    'SELECT count(*) c FROM return_invoice_items',
  );
  print('=== returns: ${rets.first['c']} invoices, ${retItems.first['c']} items ===');

  await db.close();
}
