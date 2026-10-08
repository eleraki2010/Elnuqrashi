import 'dart:io';

import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' hide Category;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../data/models/category.dart';
import '../../data/models/product.dart';
import '../../data/repositories/category_repository.dart';
import '../../data/repositories/product_repository.dart';

/// استيراد وتصدير المنتجات عبر ملفات Excel (Phase 4).
///
/// يعتمد على ترتيب أعمدة ثابت لضمان توافق الملفات المُصدّرة مع المستوردة.
class ExcelProductService {
  ExcelProductService._();

  // ترتيب الأعمدة (يجب أن يطابق الترويسة في [_headerRow]).
  static const int _colName = 1;
  static const int _colBarcode = 2;
  static const int _colCategory = 3;
  static const int _colUnit = 4;
  static const int _colPurchase = 5;
  static const int _colSale = 6;
  static const int _colQuantity = 7;
  static const int _colMinAlert = 8;

  static List<CellValue?> get _headerRow => [
        const IntCellValue(0),
        TextCellValue('اسم المنتج'),
        TextCellValue('الباركود'),
        TextCellValue('الفئة'),
        TextCellValue('الوحدة'),
        TextCellValue('سعر الشراء'),
        TextCellValue('سعر البيع'),
        TextCellValue('الكمية'),
        TextCellValue('حد التنبيه'),
      ];

  /// تصدير كل المنتجات إلى ملف Excel. يُرجع المسار أو null عند الإلغاء.
  static Future<String?> exportProducts() async {
    final repo = ProductRepository();
    final catRepo = CategoryRepository();

    final products = await repo.getAllProducts();
    final categories = await catRepo.getAllCategories();
    final categoryNames = {for (final c in categories) c.id: c.name};

    final excel = Excel.createExcel();
    final sheet = excel['المنتجات'];

    // ترويسة الجدول.
    sheet.appendRow(_headerRow);

    for (var i = 0; i < products.length; i++) {
      final pr = products[i];
      sheet.appendRow([
        IntCellValue(i + 1),
        TextCellValue(pr.name),
        TextCellValue(pr.barcode ?? ''),
        TextCellValue(categoryNames[pr.categoryId] ?? ''),
        TextCellValue(pr.unit),
        DoubleCellValue(pr.purchasePrice),
        DoubleCellValue(pr.salePrice),
        IntCellValue(pr.quantity),
        IntCellValue(pr.minQuantityAlert),
      ]);
    }

    // ورقة تعليمات الاستيراد.
    final helpSheet = excel['تعليمات الاستيراد'];
    helpSheet.appendRow([TextCellValue('تعليمات تعبئة ملف الاستيراد')]);
    helpSheet.appendRow([TextCellValue('')]);
    helpSheet.appendRow([
      TextCellValue(
          '1. الأعمدة المطلوبة: اسم المنتج، سعر الشراء، سعر البيع، الكمية.'),
    ]);
    helpSheet.appendRow([
      TextCellValue('2. الباركود والفئة والوحدة وحد التنبيه اختيارية.'),
    ]);
    helpSheet.appendRow([
      TextCellValue(
          '3. تُطابَق الفئة بالاسم؛ تُنشأ تلقائياً إذا لم تكن موجودة.'),
    ]);
    helpSheet.appendRow([
      TextCellValue(
          '4. إذا كان الباركود موجوداً مسبقاً يُحدَّث المنتج بدلاً من تكراره.'),
    ]);
    helpSheet.appendRow([TextCellValue('5. الأسطر الفارغة تُتجاهل.')]);

    final bytes = excel.encode();
    if (bytes == null) return null;

    final now = DateTime.now();
    final fileName =
        'المنتجات_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}.xlsx';

    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'اختر مكان حفظ ملف المنتجات',
        fileName: fileName,
        bytes: Uint8List.fromList(bytes),
      );
      return path;
    }

    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, fileName));
    await file.writeAsBytes(bytes);
    return file.path;
  }

  /// استيراد المنتجات من ملف Excel يختاره المستخدم.
  /// يُرجع ملخصاً نصياً بالنتيجة.
  static Future<String> importProducts() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'اختر ملف Excel للمنتجات',
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) {
      return 'تم إلغاء الاستيراد';
    }

    final file = result.files.single;
    List<int> bytes;
    if (file.bytes != null) {
      bytes = file.bytes!;
    } else if (file.path != null) {
      bytes = await File(file.path!).readAsBytes();
    } else {
      return 'تعذّر قراءة الملف';
    }

    final excel = Excel.decodeBytes(bytes);
    final sheet = excel.tables.values.firstOrNull;
    if (sheet == null) return 'لا توجد أوراق في الملف';

    final catRepo = CategoryRepository();
    final productRepo = ProductRepository();
    final categories = await catRepo.getAllCategories();
    final categoryByName = {for (final c in categories) c.name: c};
    final existingByBarcode = <String, Product>{};
    for (final pr in await productRepo.getAllProducts()) {
      final b = pr.barcode;
      if (b != null && b.isNotEmpty) {
        existingByBarcode[b] = pr;
      }
    }

    final uuid = const Uuid();
    // فئة احتياطية لضمان عدم كسر قيد NOT NULL عند غياب الفئة.
    final fallbackCategoryId =
        categoryByName.values.isNotEmpty ? categoryByName.values.first.id : null;

    int added = 0;
    int updated = 0;
    int skipped = 0;
    int rowNumber = 0;

    for (final row in sheet.rows) {
      rowNumber++;
      if (rowNumber == 1) continue; // تخطّي الترويسة.

      final name = _cellString(row, _colName);
      if (name.isEmpty) {
        skipped++;
        continue;
      }

      final purchase = _cellDouble(row, _colPurchase);
      final sale = _cellDouble(row, _colSale);
      final quantity = _cellInt(row, _colQuantity);

      if (sale == null && purchase == null && quantity == null) {
        skipped++;
        continue;
      }

      // مطابقة أو إنشاء الفئة.
      final categoryName = _cellString(row, _colCategory);
      Category? category;
      if (categoryName.isNotEmpty) {
        category = categoryByName[categoryName];
        if (category == null) {
          category = Category(id: uuid.v4(), name: categoryName);
          await catRepo.insertCategory(category);
          categoryByName[categoryName] = category;
        }
      }

      final barcode = _cellString(row, _colBarcode);
      final existing =
          barcode.isNotEmpty ? existingByBarcode[barcode] : null;

      // عند عدم وجود فئة صريحة: نستخدم فئة المنتج الموجود، أو الفئة الافتراضية.
      final resolvedCategoryId =
          category?.id ?? existing?.categoryId ?? fallbackCategoryId;
      if (resolvedCategoryId == null) {
        skipped++;
        continue;
      }

      final now = DateTime.now();
      final product = Product(
        id: existing?.id ?? uuid.v4(),
        name: name,
        barcode: barcode.isEmpty ? null : barcode,
        categoryId: resolvedCategoryId,
        unit: _cellString(row, _colUnit, fallback: existing?.unit ?? 'قطعة'),
        purchasePrice: purchase ?? existing?.purchasePrice ?? 0,
        salePrice: sale ?? existing?.salePrice ?? 0,
        quantity: quantity ?? existing?.quantity ?? 0,
        minQuantityAlert:
            _cellInt(row, _colMinAlert) ?? existing?.minQuantityAlert ?? 5,
        imageUrl: existing?.imageUrl,
        notes: existing?.notes,
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
      );

      if (existing == null) {
        await productRepo.insertProduct(product);
        added++;
      } else {
        await productRepo.updateProduct(product);
        updated++;
      }
    }

    return 'اكتمل الاستيراد: $added منتج جديد، $updated محدّث، $skipped سطر متجاهل.';
  }

  static String _cellString(List<Data?> row, int index, {String fallback = ''}) {
    if (index >= row.length) return fallback;
    final cell = row[index];
    if (cell == null || cell.value == null) return fallback;
    return cell.value.toString().trim();
  }

  static double? _cellDouble(List<Data?> row, int index) {
    final raw = _cellString(row, index);
    if (raw.isEmpty) return null;
    return double.tryParse(raw);
  }

  static int? _cellInt(List<Data?> row, int index) {
    final raw = _cellString(row, index);
    if (raw.isEmpty) return null;
    final parsed = double.tryParse(raw);
    return parsed?.round();
  }
}
