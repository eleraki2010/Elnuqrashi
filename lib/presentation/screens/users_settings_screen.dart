import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../data/models/user.dart';
import '../../providers/auth_provider.dart';

/// شاشة إدارة المستخدمين المستقلة.
class UsersSettingsScreen extends ConsumerWidget {
  const UsersSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contentKey = GlobalKey<UsersManagementContentState>();

    return Scaffold(
      appBar: AppBar(title: const Text('المستخدمين والصلاحيات')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => contentKey.currentState?.showUserDialog(),
        child: const Icon(Icons.person_add),
      ),
      body: UsersManagementContent(key: contentKey),
    );
  }
}

/// محتوى إدارة المستخدمين — قابل للدمج داخل شاشة الإعدادات أو كشاشة مستقلة.
class UsersManagementContent extends ConsumerStatefulWidget {
  const UsersManagementContent({super.key});

  @override
  ConsumerState<UsersManagementContent> createState() =>
      UsersManagementContentState();
}

class UsersManagementContentState
    extends ConsumerState<UsersManagementContent> {
  Future<List<User>>? _usersFuture;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  void _loadUsers() {
    _usersFuture = ref.read(userRepositoryProvider).getAllUsers();
  }

  /// فتح ديالوج إضافة/تعديل مستخدم. يمكن استدعاؤها من خارج الـ widget.
  Future<void> showUserDialog({User? user}) async {
    final isEdit = user != null;
    final nameController = TextEditingController(text: user?.name ?? '');
    final usernameController = TextEditingController(text: user?.username ?? '');
    final passwordController = TextEditingController();
    final roleNotifier = ValueNotifier<String>(user?.role ?? 'cashier');

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(isEdit ? 'تعديل مستخدم' : 'إضافة مستخدم جديد'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'الاسم *',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: usernameController,
                    decoration: const InputDecoration(
                      labelText: 'اسم المستخدم *',
                      prefixIcon: Icon(Icons.alternate_email),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: passwordController,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: isEdit
                          ? 'كلمة المرور (اتركها فارغة للإبقاء عليها)'
                          : 'كلمة المرور *',
                      prefixIcon: const Icon(Icons.lock_outline),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: roleNotifier.value,
                    decoration: const InputDecoration(
                      labelText: 'الصلاحية *',
                      prefixIcon: Icon(Icons.shield_outlined),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'owner',
                        child: Text('مالك (صلاحيات كاملة)'),
                      ),
                      DropdownMenuItem(
                        value: 'cashier',
                        child: Text('كاشير (بيع فقط)'),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() => roleNotifier.value = val);
                      }
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(isEdit ? 'حفظ' : 'إضافة'),
              ),
            ],
          );
        },
      ),
    );

    if (result != true) return;

    final name = nameController.text.trim();
    final username = usernameController.text.trim();
    final password = passwordController.text;
    final role = roleNotifier.value;

    if (name.isEmpty || username.isEmpty || (!isEdit && password.isEmpty)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: AppColors.DANGER_RED,
            content: Text('يرجى تعبئة جميع الحقول المطلوبة'),
          ),
        );
      }
      return;
    }

    final repo = ref.read(userRepositoryProvider);
    try {
      if (isEdit) {
        await repo.updateUser(
          user.copyWith(name: name, username: username, role: role),
          newPassword: password.isEmpty ? null : password,
        );
      } else {
        await repo.insertUser(
          name: name,
          username: username,
          password: password,
          role: role,
        );
      }
      await ref.read(authProvider.notifier).refreshCurrentUser();
      setState(_loadUsers);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: AppColors.SUCCESS_GREEN,
            content: Text('تم حفظ بيانات المستخدم بنجاح'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.DANGER_RED,
            content: Text('خطأ: $e'),
          ),
        );
      }
    }
  }

  Future<void> _confirmDelete(User user) async {
    final currentUser = ref.read(authProvider).user;
    if (currentUser?.id == user.id) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.DANGER_RED,
          content: Text('لا يمكن حذف الحساب الحالي'),
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text(AppStrings.CONFIRM_DELETE),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.DANGER_RED,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await ref.read(userRepositoryProvider).deleteUser(user.id);
    setState(_loadUsers);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حذف المستخدم')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<User>>(
      future: _usersFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 120,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Text('خطأ: ${snapshot.error}');
        }

        final users = snapshot.data ?? [];
        if (users.isEmpty) {
          return Column(
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('لا يوجد مستخدمون'),
              ),
              _buildAddButton(),
            ],
          );
        }

        return Column(
          children: [
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              itemCount: users.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final user = users[index];
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: user.isOwner
                          ? AppColors.PRIMARY_BLUE
                          : AppColors.NEUTRAL_BG,
                      child: Icon(
                        user.isOwner ? Icons.admin_panel_settings : Icons.person,
                        color: user.isOwner ? Colors.white : AppColors.TEXT_SECONDARY,
                      ),
                    ),
                    title: Text(
                      user.name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      '${user.username} • ${user.isOwner ? "مالك" : "كاشير"}',
                      style: const TextStyle(color: AppColors.TEXT_SECONDARY),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          tooltip: 'تعديل',
                          onPressed: () => showUserDialog(user: user),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline,
                              color: AppColors.DANGER_RED),
                          tooltip: 'حذف',
                          onPressed: () => _confirmDelete(user),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            _buildAddButton(),
          ],
        );
      },
    );
  }

  /// زر إضافة مستخدم — يعمل داخل شاشة الإعدادات (Embedded) وبشاشة مستقلة.
  Widget _buildAddButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () => showUserDialog(),
        icon: const Icon(Icons.person_add),
        label: const Text(
          'إضافة مستخدم جديد',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
