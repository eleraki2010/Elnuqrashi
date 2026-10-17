import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/constants/app_constants.dart';
import 'core/database/app_database.dart';
import 'core/theme/app_theme.dart';
import 'core/services/google_drive_backup_service.dart';
import 'presentation/screens/login_screen.dart';
import 'presentation/screens/main_layout_screen.dart';
import 'presentation/screens/splash_screen.dart';
import 'providers/auth_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ضبط التطبيق للعمل في الوضع الرأسي (Portrait) للأجهزة اللوحية
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Initialize SQLite local database.
  // أي فشل في فتح/ترقية القاعدة لا يجب أن يُسقط التطبيق بصمت؛ نلتقطه ونعرضه.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
  };
  try {
    await AppDatabase.instance;
  } catch (e, st) {
    FlutterError.reportError(FlutterErrorDetails(exception: e, stack: st));
    // نتيح للتطبيق الإقلاع حتى لو فشلت القاعدة: AuthGate سيعرض شاشة فارغة بدل تعليق.
  }

  runApp(
    const ProviderScope(
      child: AlnokrashyPOSApp(),
    ),
  );

  // استماع وتفعيل النسخ الاحتياطي التلقائي في الخلفية بعد إقلاع التطبيق دون تأخير الفتح
  Future.microtask(() async {
    try {
      GoogleDriveBackupService.initializeAutoBackupListener();
      await Future.delayed(const Duration(seconds: 3));
      GoogleDriveBackupService.checkAndTriggerAutoBackup();
    } catch (e) {
      debugPrint('Google Drive background init: $e');
    }
  });
}

class AlnokrashyPOSApp extends StatelessWidget {
  const AlnokrashyPOSApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppStrings.APP_TITLE,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      locale: const Locale('ar', 'EG'),
      supportedLocales: const [
        Locale('ar', 'EG'),
        Locale('ar'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const SplashScreen(),
    );
  }
}

/// يقرر بين شاشة تسجيل الدخول والواجهة الرئيسية حسب حالة الجلسة.
class AuthGate extends ConsumerStatefulWidget {
  const AuthGate({super.key});

  @override
  ConsumerState<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<AuthGate> {
  @override
  void initState() {
    super.initState();
    // استعادة الجلسة المحفوظة (إن وجدت) عند بدء التطبيق.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(authProvider.notifier).restore();
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);

    if (!auth.initialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!auth.isLoggedIn) {
      return const LoginScreen();
    }

    return const MainLayoutScreen();
  }
}
