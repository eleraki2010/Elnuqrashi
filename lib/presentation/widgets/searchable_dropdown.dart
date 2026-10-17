import 'package:flutter/material.dart';
import '../../core/constants/app_constants.dart';

/// عنصر يمثل خياراً واحداً داخل القائمة المنسدلة القابلة للبحث.
class SearchableDropdownItem<T> {
  final T value;
  final String label;
  final String? subtitle;
  final IconData? icon;
  final Color? iconColor;
  final Widget? trailing;

  const SearchableDropdownItem({
    required this.value,
    required this.label,
    this.subtitle,
    this.icon,
    this.iconColor,
    this.trailing,
  });
}

/// حقل إدخال وقائمة منسدلة احترافية تدعم البحث الفوري والسلس.
/// ملائمة لكافة أحجام الشاشات وتدعم التخصيص وإضافة عناصر جديدة.
class SearchableDropdownFormField<T> extends FormField<T> {
  final List<SearchableDropdownItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final String? hintText;
  final String? labelText;
  final Widget? prefixIcon;
  final String searchHint;
  final String dialogTitle;
  final VoidCallback? onAddNew;
  final String? addNewLabel;

  SearchableDropdownFormField({
    super.key,
    required this.items,
    T? value,
    T? initialValue,
    this.onChanged,
    this.hintText,
    this.labelText,
    this.prefixIcon,
    this.searchHint = 'ابحث هنا...',
    this.dialogTitle = 'اختر من القائمة',
    this.onAddNew,
    this.addNewLabel,
    super.enabled = true,
    super.validator,
    super.autovalidateMode,
  }) : super(
          initialValue: value ?? initialValue,
          builder: (FormFieldState<T> state) {
            final context = state.context;
            SearchableDropdownItem<T>? selectedItem;
            try {
              selectedItem = items.firstWhere(
                (item) => item.value == state.value,
              );
            } catch (_) {
              selectedItem = null;
            }

            final hasError = state.hasError;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  onTap: enabled
                      ? () async {
                          final selected =
                              await _showSearchModal<T>(
                            context: context,
                            items: items,
                            currentValue: state.value,
                            title: dialogTitle.isNotEmpty
                                ? dialogTitle
                                : (labelText ?? 'اختر من القائمة'),
                            searchHint: searchHint,
                            onAddNew: onAddNew,
                            addNewLabel: addNewLabel,
                          );

                          if (selected != null) {
                            state.didChange(selected.value);
                            onChanged?.call(selected.value);
                          }
                        }
                      : null,
                  borderRadius: BorderRadius.circular(AppLayout.BORDER_RADIUS),
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: labelText,
                      hintText: hintText,
                      prefixIcon: prefixIcon,
                      suffixIcon: const Icon(Icons.arrow_drop_down, size: 28),
                      errorText: hasError ? state.errorText : null,
                      enabled: state.widget.enabled,
                      filled: !state.widget.enabled,
                      fillColor: state.widget.enabled ? null : Colors.grey.shade100,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 14,
                      ),
                      border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(AppLayout.BORDER_RADIUS),
                      ),
                    ),
                    isEmpty: state.value == null,
                    child: selectedItem != null
                        ? Row(
                            children: [
                              if (selectedItem.icon != null) ...[
                                Icon(
                                  selectedItem.icon,
                                  size: 18,
                                  color: selectedItem.iconColor ??
                                      AppColors.PRIMARY_BLUE,
                                ),
                                const SizedBox(width: 8),
                              ],
                              Expanded(
                                child: Text(
                                  selectedItem.label,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.TEXT_PRIMARY,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          )
                        : Text(
                            hintText ?? 'اختر...',
                            style: const TextStyle(
                              color: AppColors.TEXT_SECONDARY,
                              fontSize: 14,
                            ),
                          ),
                  ),
                ),
              ],
            );
          },
        );

  static Future<SearchableDropdownItem<T>?> _showSearchModal<T>({
    required BuildContext context,
    required List<SearchableDropdownItem<T>> items,
    required T? currentValue,
    required String title,
    required String searchHint,
    VoidCallback? onAddNew,
    String? addNewLabel,
  }) async {
    return showModalBottomSheet<SearchableDropdownItem<T>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return _SearchableDropdownSheet<T>(
          items: items,
          currentValue: currentValue,
          title: title,
          searchHint: searchHint,
          onAddNew: onAddNew,
          addNewLabel: addNewLabel,
        );
      },
    );
  }
}

class _SearchableDropdownSheet<T> extends StatefulWidget {
  final List<SearchableDropdownItem<T>> items;
  final T? currentValue;
  final String title;
  final String searchHint;
  final VoidCallback? onAddNew;
  final String? addNewLabel;

  const _SearchableDropdownSheet({
    required this.items,
    required this.currentValue,
    required this.title,
    required this.searchHint,
    this.onAddNew,
    this.addNewLabel,
  });

  @override
  State<_SearchableDropdownSheet<T>> createState() =>
      _SearchableDropdownSheetState<T>();
}

class _SearchableDropdownSheetState<T>
    extends State<_SearchableDropdownSheet<T>> {
  final TextEditingController _searchController = TextEditingController();
  late List<SearchableDropdownItem<T>> _filteredItems;

  @override
  void initState() {
    super.initState();
    _filteredItems = List.of(widget.items);
  }

  void _filter(String query) {
    final clean = query.trim().toLowerCase();
    setState(() {
      if (clean.isEmpty) {
        _filteredItems = List.of(widget.items);
      } else {
        _filteredItems = widget.items.where((item) {
          final matchLabel = item.label.toLowerCase().contains(clean);
          final matchSubtitle =
              item.subtitle?.toLowerCase().contains(clean) ?? false;
          return matchLabel || matchSubtitle;
        }).toList();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final bottomInset = media.viewInsets.bottom;
    final maxHeight = media.size.height * 0.75;

    return Material(
      color: Colors.white,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: Container(
        constraints: BoxConstraints(maxHeight: maxHeight),
        margin: EdgeInsets.only(bottom: bottomInset),
        child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // المقبض العلوي
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: 6),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // الترويسة
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.PRIMARY_BLUE_DARK,
                      ),
                    ),
                  ),
                  if (widget.onAddNew != null)
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        foregroundColor: AppColors.PRIMARY_BLUE,
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        widget.onAddNew!();
                      },
                      icon: const Icon(Icons.add_circle_outline, size: 18),
                      label: Text(widget.addNewLabel ?? 'إضافة جديد'),
                    ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            // شريط البحث
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                onChanged: _filter,
                decoration: InputDecoration(
                  hintText: widget.searchHint,
                  hintStyle: const TextStyle(fontSize: 13),
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            _filter('');
                          },
                        )
                      : null,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  filled: true,
                  fillColor: AppColors.NEUTRAL_BG,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const Divider(height: 1),
            // قائمة النتائج
            Flexible(
              child: _filteredItems.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.search_off_rounded,
                            size: 40,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'لا توجد نتائج مطابقة لبحثك',
                            style: TextStyle(
                              color: AppColors.TEXT_SECONDARY,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      itemCount: _filteredItems.length,
                      separatorBuilder: (_, _) =>
                          const Divider(height: 1, indent: 56),
                      itemBuilder: (ctx, index) {
                        final item = _filteredItems[index];
                        final isSelected = item.value == widget.currentValue;

                        return ListTile(
                          dense: true,
                          visualDensity: VisualDensity.compact,
                          leading: item.icon != null
                              ? CircleAvatar(
                                  radius: 16,
                                  backgroundColor: (item.iconColor ??
                                          AppColors.PRIMARY_BLUE)
                                      .withValues(alpha: 0.12),
                                  child: Icon(
                                    item.icon,
                                    size: 17,
                                    color: item.iconColor ??
                                        AppColors.PRIMARY_BLUE,
                                  ),
                                )
                              : CircleAvatar(
                                  radius: 16,
                                  backgroundColor: isSelected
                                      ? AppColors.PRIMARY_BLUE
                                          .withValues(alpha: 0.12)
                                      : Colors.grey.shade100,
                                  child: Text(
                                    item.label.isNotEmpty
                                        ? item.label.characters.first
                                        : '?',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: isSelected
                                          ? AppColors.PRIMARY_BLUE
                                          : AppColors.TEXT_PRIMARY,
                                    ),
                                  ),
                                ),
                          title: Text(
                            item.label,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.w500,
                              color: isSelected
                                  ? AppColors.PRIMARY_BLUE
                                  : AppColors.TEXT_PRIMARY,
                            ),
                          ),
                          subtitle: item.subtitle != null
                              ? Text(
                                  item.subtitle!,
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    color: AppColors.TEXT_SECONDARY,
                                  ),
                                )
                              : null,
                          trailing: isSelected
                              ? const Icon(
                                  Icons.check_circle,
                                  color: AppColors.SUCCESS_GREEN,
                                  size: 20,
                                )
                              : item.trailing,
                          onTap: () => Navigator.pop(context, item),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    ),
    );
  }
}
