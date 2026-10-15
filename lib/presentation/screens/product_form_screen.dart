import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p_path;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/app_constants.dart';
import '../../data/models/category.dart';
import '../../data/models/product.dart';
import '../../providers/app_providers.dart';
import '../../providers/data_refresh_service.dart';
import '../widgets/product_image_view.dart';
import 'barcode_scanner_screen.dart';

class ProductFormScreen extends ConsumerStatefulWidget {
  final Product? productToEdit;

  const ProductFormScreen({super.key, this.productToEdit});

  @override
  ConsumerState<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends ConsumerState<ProductFormScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nameController;
  late TextEditingController _barcodeController;
  late TextEditingController _purchasePriceController;
  late TextEditingController _salePriceController;
  late TextEditingController _quantityController;
  late TextEditingController _minAlertController;
  late TextEditingController _notesController;

  String? _selectedCategoryId;
  String _selectedUnit = 'قطعة';
  String? _imageUrl;

  final List<String> _units = ['قطعة', 'متر', 'كرتونة', 'لفة', 'طقم', 'شيكارة'];

  @override
  void initState() {
    super.initState();
    final p = widget.productToEdit;
    _nameController = TextEditingController(text: p?.name ?? '');
    _barcodeController = TextEditingController(text: p?.barcode ?? '');

    // يجب أن تكون الحقول فارغة تماماً عند إضافة منتج جديد ليكتب المستخدم مباشرة دون مسح
    _purchasePriceController = TextEditingController(
      text: p != null ? (p.purchasePrice > 0 ? p.purchasePrice.toString() : '') : '',
    );
    _salePriceController = TextEditingController(
      text: p != null ? (p.salePrice > 0 ? p.salePrice.toString() : '') : '',
    );
    _quantityController = TextEditingController(
      text: p != null ? (p.quantity > 0 ? p.quantity.toString() : '') : '',
    );
    _minAlertController = TextEditingController(
      text: p != null ? (p.minQuantityAlert > 0 ? p.minQuantityAlert.toString() : '') : '',
    );
    _notesController = TextEditingController(text: p?.notes ?? '');

    _imageUrl = p?.imageUrl;
    _selectedCategoryId = p?.categoryId;
    if (p != null && _units.contains(p.unit)) {
      _selectedUnit = p.unit;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _barcodeController.dispose();
    _purchasePriceController.dispose();
    _salePriceController.dispose();
    _quantityController.dispose();
    _minAlertController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickProductImage() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );

      if (result != null && result.files.isNotEmpty) {
        final pickedPath = result.files.single.path;
        if (pickedPath != null && pickedPath.isNotEmpty) {
          final appDir = await getApplicationDocumentsDirectory();
          final imagesDir = Directory(p_path.join(appDir.path, 'product_images'));
          if (!await imagesDir.exists()) {
            await imagesDir.create(recursive: true);
          }
          final ext = p_path.extension(pickedPath);
          final fileName = 'prod_${DateTime.now().millisecondsSinceEpoch}$ext';
          final targetPath = p_path.join(imagesDir.path, fileName);
          final savedFile = await File(pickedPath).copy(targetPath);

          setState(() {
            _imageUrl = savedFile.path;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.DANGER_RED,
            content: Text('تعذر اختيار الصورة: $e'),
          ),
        );
      }
    }
  }

  Future<void> _saveProduct() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCategoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى اختيار تصنيف المنتج')),
      );
      return;
    }

    final buyPrice = double.tryParse(_purchasePriceController.text.trim()) ?? 0.0;
    final sellPrice = double.tryParse(_salePriceController.text.trim()) ?? 0.0;

    // حماية محاسبية: سعر البيع لا يمكن أن يكون أقل من سعر الشراء
    if (sellPrice < buyPrice) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.DANGER_RED,
          content: Text(
            'خطأ: سعر البيع (${AppStrings.money(sellPrice)}) لا يمكن أن يكون أقل من سعر الشراء (${AppStrings.money(buyPrice)})',
          ),
        ),
      );
      return;
    }

    final repo = ref.read(productRepositoryProvider);
    final now = DateTime.now();
    final isEdit = widget.productToEdit != null;
    final productId = isEdit ? widget.productToEdit!.id : const Uuid().v4();

    final product = Product(
      id: productId,
      name: _nameController.text.trim(),
      barcode: _barcodeController.text.trim().isEmpty
          ? null
          : _barcodeController.text.trim(),
      categoryId: _selectedCategoryId!,
      unit: _selectedUnit,
      purchasePrice: buyPrice,
      salePrice: sellPrice,
      quantity: int.tryParse(_quantityController.text.trim()) ?? 0,
      minQuantityAlert: int.tryParse(_minAlertController.text.trim()) ?? 5,
      imageUrl: _imageUrl,
      notes: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
      createdAt: isEdit ? widget.productToEdit!.createdAt : now,
      updatedAt: now,
    );

    if (isEdit) {
      await repo.updateProduct(product);
    } else {
      await repo.insertProduct(product);
    }

    refreshAfterProductChange(ref);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.SUCCESS_GREEN,
          content: Text(
            isEdit ? 'تم تحديث بيانات المنتج بنجاح' : 'تمت إضافة المنتج بنجاح',
          ),
        ),
      );
      Navigator.of(context).pop(product);
    }
  }

  void _showAddCategoryDialog() {
    final catNameController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إضافة تصنيف جديد'),
        content: TextField(
          controller: catNameController,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'اسم التصنيف'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = catNameController.text.trim();
              if (name.isNotEmpty) {
                final catRepo = ref.read(categoryRepositoryProvider);
                final newCat = Category(
                  id: 'cat_${DateTime.now().millisecondsSinceEpoch}',
                  name: name,
                );
                await catRepo.insertCategory(newCat);
                ref.invalidate(categoriesListProvider);
                if (mounted) {
                  setState(() {
                    _selectedCategoryId = newCat.id;
                  });
                }
                if (ctx.mounted) {
                  Navigator.of(ctx).pop();
                }
              }
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(categoriesListProvider);
    final isEdit = widget.productToEdit != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? 'تعديل منتج' : AppStrings.BTN_ADD_PRODUCT),
        elevation: 0.5,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 720;

          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 820),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.NEUTRAL_SURFACE,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Form(
                  key: _formKey,
                  child: isWide
                      ? _buildWideLayout(categoriesAsync)
                      : _buildCompactLayout(categoriesAsync),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // تخطيط الشاشات الواسعة (عمودين متوازيين مدمجين يلائمان الشاشة تماماً بدون تمرير)
  Widget _buildWideLayout(AsyncValue<List<Category>> categoriesAsync) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // العمود الأيمن: البيانات الأساسية + الصورة
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeaderRow('1. البيانات الأساسية للصنف'),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // الصورة بشكل مدمج
                      _buildCompactImagePicker(),
                      const SizedBox(width: 12),
                      // اسم المنتج
                      Expanded(
                        child: _buildNameField(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _buildCategoryRow(categoriesAsync),
                  const SizedBox(height: 10),
                  _buildBarcodeAndUnitRow(),
                ],
              ),
            ),
            const SizedBox(width: 20),
            // العمود الأيسر: الأسعار والمخزون والملاحظات
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeaderRow('2. الأسعار والمخزون'),
                  const SizedBox(height: 10),
                  _buildPriceRow(),
                  const SizedBox(height: 10),
                  _buildStockRow(),
                  const SizedBox(height: 10),
                  _buildNotesField(),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const Divider(height: 1),
        const SizedBox(height: 12),
        _buildActionButtons(),
      ],
    );
  }

  // تخطيط الشاشات الصغيرة / الهواتف (مدمج جداً ليتسع في شاشة واحدة)
  Widget _buildCompactLayout(AsyncValue<List<Category>> categoriesAsync) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // صف الاسم مع أيقونة/صورة المنتج المصغرة
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCompactImagePicker(),
            const SizedBox(width: 10),
            Expanded(
              child: _buildNameField(),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _buildCategoryRow(categoriesAsync),
        const SizedBox(height: 10),
        _buildBarcodeAndUnitRow(),
        const SizedBox(height: 10),
        _buildPriceRow(),
        const SizedBox(height: 10),
        _buildStockRow(),
        const SizedBox(height: 10),
        _buildNotesField(),
        const SizedBox(height: 14),
        _buildActionButtons(),
      ],
    );
  }

  Widget _buildHeaderRow(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 13.5,
        fontWeight: FontWeight.bold,
        color: AppColors.PRIMARY_BLUE_DARK,
      ),
    );
  }

  Widget _buildCompactImagePicker() {
    return InkWell(
      onTap: _pickProductImage,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 58,
        height: 58,
        decoration: BoxDecoration(
          color: AppColors.NEUTRAL_BG,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFCBD5E1)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(9),
          child: _imageUrl != null && _imageUrl!.isNotEmpty
              ? Stack(
                  fit: StackFit.expand,
                  children: [
                    ProductImageView(
                      imageUrl: _imageUrl,
                      width: 58,
                      height: 58,
                      fit: BoxFit.cover,
                    ),
                    Positioned(
                      top: 2,
                      right: 2,
                      child: InkWell(
                        onTap: () => setState(() => _imageUrl = null),
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: const BoxDecoration(
                            color: AppColors.DANGER_RED,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close, size: 10, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                )
              : const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_a_photo_outlined, size: 22, color: AppColors.PRIMARY_BLUE),
                    SizedBox(height: 2),
                    Text('صورة', style: TextStyle(fontSize: 10, color: AppColors.TEXT_SECONDARY)),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildNameField() {
    return TextFormField(
      controller: _nameController,
      decoration: const InputDecoration(
        labelText: 'اسم المنتج *',
        hintText: 'اكتب اسم المنتج بدقة...',
        prefixIcon: Icon(Icons.inventory_2_outlined, size: 20),
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      ),
      validator: (val) {
        if (val == null || val.trim().isEmpty) {
          return 'يرجى إدخال اسم المنتج';
        }
        return null;
      },
    );
  }

  Widget _buildCategoryRow(AsyncValue<List<Category>> categoriesAsync) {
    return Row(
      children: [
        Expanded(
          child: categoriesAsync.when(
            data: (categories) {
              if (_selectedCategoryId == null && categories.isNotEmpty) {
                _selectedCategoryId = categories.first.id;
              }
              return DropdownButtonFormField<String>(
                initialValue: _selectedCategoryId,
                decoration: const InputDecoration(
                  labelText: 'التصنيف *',
                  prefixIcon: Icon(Icons.category_outlined, size: 20),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                ),
                items: categories.map((cat) {
                  return DropdownMenuItem(
                    value: cat.id,
                    child: Text(cat.name, style: const TextStyle(fontSize: 13)),
                  );
                }).toList(),
                onChanged: (val) {
                  setState(() => _selectedCategoryId = val);
                },
              );
            },
            loading: () => const LinearProgressIndicator(),
            error: (_, _) => const Text('تعذر تحميل الفئات'),
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          onPressed: _showAddCategoryDialog,
          tooltip: 'إضافة تصنيف جديد',
          iconSize: 20,
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.add),
        ),
      ],
    );
  }

  Widget _buildBarcodeAndUnitRow() {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: TextFormField(
            controller: _barcodeController,
            decoration: const InputDecoration(
              labelText: 'الباركود / الكود',
              hintText: 'امسح أو اكتب الكود',
              prefixIcon: Icon(Icons.qr_code_scanner, size: 20),
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            ),
          ),
        ),
        const SizedBox(width: 6),
        IconButton(
          icon: const Icon(Icons.qr_code_scanner, size: 20),
          tooltip: 'مسح الباركود بالكاميرا',
          visualDensity: VisualDensity.compact,
          onPressed: () async {
            final barcode = await Navigator.push<String>(
              context,
              MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
            );
            if (barcode != null && mounted) {
              setState(() => _barcodeController.text = barcode);
            }
          },
          style: IconButton.styleFrom(
            backgroundColor: AppColors.PRIMARY_BLUE,
            foregroundColor: Colors.white,
            minimumSize: const Size(40, 40),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: DropdownButtonFormField<String>(
            initialValue: _selectedUnit,
            decoration: const InputDecoration(
              labelText: 'الوحدة *',
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            ),
            items: _units.map((unit) {
              return DropdownMenuItem(
                value: unit,
                child: Text(unit, style: const TextStyle(fontSize: 13)),
              );
            }).toList(),
            onChanged: (val) {
              if (val != null) setState(() => _selectedUnit = val);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPriceRow() {
    return Row(
      children: [
        Expanded(
          child: TextFormField(
            controller: _purchasePriceController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'سعر الشراء (التكلفة) *',
              hintText: '0.00',
              suffixText: 'ج.م',
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            ),
            validator: (val) {
              if (val == null || val.trim().isEmpty) {
                return 'أدخل سعر الشراء';
              }
              final p = double.tryParse(val.trim());
              if (p == null || p < 0) return 'أدخل رقم صحيح';
              return null;
            },
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: TextFormField(
            controller: _salePriceController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'سعر البيع للجمهور *',
              hintText: '0.00',
              suffixText: 'ج.م',
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            ),
            validator: (val) {
              if (val == null || val.trim().isEmpty) {
                return 'أدخل سعر البيع';
              }
              final s = double.tryParse(val.trim());
              if (s == null || s < 0) return 'أدخل رقم صحيح';
              final p = double.tryParse(_purchasePriceController.text.trim()) ?? 0.0;
              if (s < p) return 'سعر البيع أقل من الشراء';
              return null;
            },
          ),
        ),
      ],
    );
  }

  Widget _buildStockRow() {
    return Row(
      children: [
        Expanded(
          child: TextFormField(
            controller: _quantityController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'الكمية في المخزن',
              hintText: '0',
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            ),
            validator: (val) {
              if (val != null && val.trim().isNotEmpty && int.tryParse(val.trim()) == null) {
                return 'أدخل رقم صحيح';
              }
              return null;
            },
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: TextFormField(
            controller: _minAlertController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'حد التنبيه الأدنى',
              hintText: '5',
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            ),
            validator: (val) {
              if (val != null && val.trim().isNotEmpty && int.tryParse(val.trim()) == null) {
                return 'أدخل رقم صحيح';
              }
              return null;
            },
          ),
        ),
      ],
    );
  }

  Widget _buildNotesField() {
    return TextFormField(
      controller: _notesController,
      maxLines: 1,
      decoration: const InputDecoration(
        labelText: 'ملاحظات إضافية (اختياري)',
        hintText: 'أي تفاصيل أخرى...',
        prefixIcon: Icon(Icons.notes_outlined, size: 20),
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      ),
    );
  }

  Widget _buildActionButtons() {
    final isEdit = widget.productToEdit != null;
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(80, 42),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          child: const Text('إلغاء'),
        ),
        const SizedBox(width: 12),
        ElevatedButton.icon(
          onPressed: _saveProduct,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.PRIMARY_BLUE,
            foregroundColor: Colors.white,
            minimumSize: const Size(120, 42),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          icon: const Icon(Icons.save, size: 18),
          label: Text(
            isEdit ? 'تحديث الصنف' : 'حفظ الصنف',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}
