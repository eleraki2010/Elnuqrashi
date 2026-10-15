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
    _purchasePriceController = TextEditingController(
      text: p != null ? p.purchasePrice.toString() : '',
    );
    _salePriceController = TextEditingController(
      text: p != null ? p.salePrice.toString() : '',
    );
    _quantityController = TextEditingController(
      text: p != null ? p.quantity.toString() : '0',
    );
    _minAlertController = TextEditingController(
      text: p != null ? p.minQuantityAlert.toString() : '5',
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
          // نسخ الصورة داخل مجلد المستندات الدائم للتطبيق
          final appDir = await getApplicationDocumentsDirectory();
          final imagesDir =
              Directory(p_path.join(appDir.path, 'product_images'));
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('يرجى اختيار تصنيف المنتج')));
      return;
    }

    final buyPrice =
        double.tryParse(_purchasePriceController.text.trim()) ?? 0.0;
    final sellPrice = double.tryParse(_salePriceController.text.trim()) ?? 0.0;

    // حماية محاسبية وقانونية: سعر البيع لا يمكن أن يكون أقل من سعر الشراء
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
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppLayout.SPACING_UNIT * 3),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 720),
            padding: const EdgeInsets.all(AppLayout.SPACING_UNIT * 3),
            decoration: BoxDecoration(
              color: AppColors.NEUTRAL_SURFACE,
              borderRadius: BorderRadius.circular(AppLayout.BORDER_RADIUS),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'البيانات الأساسية للمنتج',
                    style: TextStyle(
                      fontSize: AppTypography.HEADING_3,
                      fontWeight: FontWeight.bold,
                      color: AppColors.PRIMARY_BLUE_DARK,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // صورة المنتج مع زر الاختيار والمعاينة والحذف
                  Center(
                    child: Column(
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            InkWell(
                              onTap: _pickProductImage,
                              borderRadius: BorderRadius.circular(16),
                              child: Container(
                                width: 120,
                                height: 120,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: const Color(0xFFCBD5E1),
                                    width: 1.5,
                                  ),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(15),
                                  child: _imageUrl != null &&
                                          _imageUrl!.isNotEmpty
                                      ? ProductImageView(
                                          imageUrl: _imageUrl,
                                          width: 120,
                                          height: 120,
                                          fit: BoxFit.cover,
                                        )
                                      : const Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.add_a_photo_outlined,
                                              size: 38,
                                              color: AppColors.PRIMARY_BLUE,
                                            ),
                                            SizedBox(height: 6),
                                            Text(
                                              'إضافة صورة',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: AppColors.TEXT_SECONDARY,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                ),
                              ),
                            ),
                            if (_imageUrl != null && _imageUrl!.isNotEmpty)
                              Positioned(
                                top: -6,
                                right: -6,
                                child: InkWell(
                                  onTap: () {
                                    setState(() {
                                      _imageUrl = null;
                                    });
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: const BoxDecoration(
                                      color: AppColors.DANGER_RED,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.close,
                                      size: 16,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: _pickProductImage,
                          icon: const Icon(Icons.photo_library_outlined,
                              size: 18),
                          label: Text(
                            _imageUrl == null
                                ? 'اختيار صورة من الجهاز'
                                : 'تغيير صورة المنتج',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Product Name
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'اسم المنتج *',
                      hintText:
                          'مثال: خلاط حنفية تركي كروم، كوع بلاستيك 1 بوصة...',
                      prefixIcon: Icon(Icons.inventory_2_outlined),
                    ),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) {
                        return 'يرجى إدخال اسم المنتج';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Category & Add Category Button
                  Row(
                    children: [
                      Expanded(
                        child: categoriesAsync.when(
                          data: (categories) {
                            if (_selectedCategoryId == null &&
                                categories.isNotEmpty) {
                              _selectedCategoryId = categories.first.id;
                            }
                            return DropdownButtonFormField<String>(
                              initialValue: _selectedCategoryId,
                              decoration: const InputDecoration(
                                labelText: 'الفئة / التصنيف *',
                                prefixIcon: Icon(Icons.category_outlined),
                              ),
                              items: categories.map((cat) {
                                return DropdownMenuItem(
                                  value: cat.id,
                                  child: Text(cat.name),
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
                        icon: const Icon(Icons.add),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Barcode & Unit
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          controller: _barcodeController,
                          decoration: const InputDecoration(
                            labelText: 'الباركود / الكود',
                            hintText: 'امسح أو اكتب الكود',
                            prefixIcon: Icon(Icons.qr_code_scanner),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      IconButton(
                        icon: const Icon(Icons.qr_code_scanner),
                        tooltip: 'مسح الباركود',
                        onPressed: () async {
                          final barcode = await Navigator.push<String>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const BarcodeScannerScreen(),
                            ),
                          );
                          if (barcode != null && mounted) {
                            setState(() {
                              _barcodeController.text = barcode;
                            });
                          }
                        },
                        style: IconButton.styleFrom(
                          backgroundColor: AppColors.PRIMARY_BLUE,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(48, 48),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 1,
                        child: DropdownButtonFormField<String>(
                          initialValue: _selectedUnit,
                          decoration: const InputDecoration(
                            labelText: 'الوحدة *',
                            prefixIcon: Icon(Icons.straighten),
                          ),
                          items: _units.map((unit) {
                            return DropdownMenuItem(
                              value: unit,
                              child: Text(unit),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setState(() => _selectedUnit = val);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Divider(),
                  const SizedBox(height: 16),

                  // Pricing & Stock Header
                  const Text(
                    'الأسعار والمخزون',
                    style: TextStyle(
                      fontSize: AppTypography.HEADING_3,
                      fontWeight: FontWeight.bold,
                      color: AppColors.PRIMARY_BLUE_DARK,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Purchase & Sale Price
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _purchasePriceController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'سعر الشراء (التكلفة) *',
                            suffixText: AppStrings.CURRENCY,
                            prefixIcon: Icon(
                              Icons.arrow_downward,
                              color: AppColors.TEXT_SECONDARY,
                            ),
                          ),
                          onChanged: (_) {
                            if (_salePriceController.text.isNotEmpty) {
                              _formKey.currentState?.validate();
                            }
                          },
                          validator: (val) {
                            if (val == null || val.trim().isEmpty) {
                              return 'يرجى إدخال سعر الشراء';
                            }
                            final p = double.tryParse(val.trim());
                            if (p == null) {
                              return 'أدخل رقم صحيح';
                            }
                            if (p < 0) {
                              return 'لا يمكن أن يكون سالباً';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextFormField(
                          controller: _salePriceController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'سعر البيع للجمهور *',
                            suffixText: AppStrings.CURRENCY,
                            prefixIcon: Icon(
                              Icons.sell_outlined,
                              color: AppColors.SUCCESS_GREEN,
                            ),
                          ),
                          validator: (val) {
                            if (val == null || val.trim().isEmpty) {
                              return 'يرجى إدخال سعر البيع';
                            }
                            final s = double.tryParse(val.trim());
                            if (s == null) {
                              return 'أدخل رقم صحيح';
                            }
                            if (s < 0) {
                              return 'لا يمكن أن يكون سالباً';
                            }
                            final p = double.tryParse(
                                    _purchasePriceController.text.trim()) ??
                                0.0;
                            if (s < p) {
                              return 'سعر البيع ($s) لا يمكن أن يقل عن الشراء ($p)';
                            }
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Quantity & Min Quantity Alert
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _quantityController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'الكمية الحالية في المخزن *',
                            prefixIcon: Icon(Icons.storage_outlined),
                          ),
                          validator: (val) {
                            if (val == null || val.trim().isEmpty) {
                              return 'أدخل الكمية';
                            }
                            if (int.tryParse(val) == null) {
                              return 'أدخل رقم صحيح';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextFormField(
                          controller: _minAlertController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'حد التنبيه الأدنى *',
                            hintText: 'مثال: 5',
                            prefixIcon: Icon(
                              Icons.notifications_active_outlined,
                              color: AppColors.WARNING_AMBER,
                            ),
                          ),
                          validator: (val) {
                            if (val == null || val.trim().isEmpty) {
                              return 'أدخل حد التنبيه';
                            }
                            if (int.tryParse(val) == null) {
                              return 'أدخل رقم صحيح';
                            }
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Notes
                  TextFormField(
                    controller: _notesController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'ملاحظات إضافية (اختياري)',
                      prefixIcon: Icon(Icons.notes_outlined),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Submit Buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('إلغاء'),
                      ),
                      const SizedBox(width: 16),
                      ElevatedButton.icon(
                        onPressed: _saveProduct,
                        icon: const Icon(Icons.save_outlined),
                        label: Text(isEdit ? 'حفظ التعديلات' : 'حفظ المنتج'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
