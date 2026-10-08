// ignore_for_file: avoid_print
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() async {
  sqfliteFfiInit();
  final path =
      r'C:\Users\elera\AppData\Roaming\com.alnokrashy\alnokrashy_pos\alnokrashy_pos.db';
  final db = await databaseFactoryFfi.openDatabase(path);

  final v = await db.rawQuery('PRAGMA user_version;');
  print('user_version = ${v.first.values.first}');

  final cols = await db.rawQuery(
      "SELECT name FROM pragma_table_info('sale_invoices')");
  print('sale_invoices cols: ${cols.map((r) => r['name']).join(', ')}');

  final pcols = await db.rawQuery("SELECT name FROM pragma_table_info('products')");
  print('products cols: ${pcols.map((r) => r['name']).join(', ')}');

  final products = await db.rawQuery(
      'SELECT id, name, quantity, purchase_price, sale_price FROM products');
  print('products: ${products.length}');
  for (final r in products) {
    print('  ${r['name']} qty=${r['quantity']}');
  }

  final items = await db.rawQuery(
      'SELECT sii.invoice_id, sii.product_id, p.name FROM sale_invoice_items sii LEFT JOIN products p ON p.id = sii.product_id');
  print('sale items: ${items.length}');
  for (final r in items) {
    print('  ${r['name'] ?? 'MISSING PRODUCT (${r['product_id']})'}');
  }

  final cust = await db.rawQuery(
      'SELECT id, name, balance_due FROM customers');
  print('customers: ${cust.length}');
  final sup = await db.rawQuery('SELECT id, name, balance_owed FROM suppliers');
  print('suppliers: ${sup.length}');
  final pays = await db.rawQuery('SELECT count(*) c FROM payments');
  print('payments: ${pays.first['c']}');

  await db.close();
}
