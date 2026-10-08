import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/constants/app_constants.dart';

/// شاشة مسح الباركود.
///
/// تدعم الكاميرا على المنصات التي يدعمها mobile_scanner (Android/iOS/macOS/Web)،
/// وتدعم قارئ الباركود الخارجي (USB/Bluetooth كلوحة مفاتيح) + الإدخال اليدوي
/// على كل المنصات بما فيها Windows.
class BarcodeScannerScreen extends StatefulWidget {
  final String? title;

  const BarcodeScannerScreen({super.key, this.title});

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> {
  final TextEditingController _manualController = TextEditingController();
  final MobileScannerController _cameraController = MobileScannerController();
  bool _cameraReady = false;
  String? _errorMessage;

  /// منصات الكاميرا المدعومة من mobile_scanner (لا يشمل Windows/Linux).
  static bool get cameraSupported {
    if (kIsWeb) return true;
    return Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
  }

  @override
  void initState() {
    super.initState();
    if (cameraSupported) {
      _startCamera();
    }
  }

  Future<void> _startCamera() async {
    try {
      await _cameraController.start();
      if (mounted) setState(() => _cameraReady = true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'تعذّر تشغيل الكاميرا: $e\nيمكنك استخدام قارئ الباركود الخارجي أو الإدخال اليدوي.';
        });
      }
    }
  }

  @override
  void dispose() {
    _manualController.dispose();
    if (cameraSupported) {
      _cameraController.dispose();
    }
    super.dispose();
  }

  void _submitBarcode(String value) {
    final code = value.trim();
    if (code.isEmpty) return;
    Navigator.of(context).pop(code);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title ?? 'مسح الباركود')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppLayout.SPACING_UNIT * 3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (cameraSupported) ...[
              SizedBox(
                height: 260,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppLayout.BORDER_RADIUS),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      MobileScanner(
                        controller: _cameraController,
                        onDetect: (capture) {
                          final barcodes = capture.barcodes;
                          if (barcodes.isNotEmpty) {
                            final value = barcodes.first.rawValue;
                            if (value != null) {
                              _cameraController.stop();
                              _submitBarcode(value);
                            }
                          }
                        },
                      ),
                      if (!_cameraReady)
                        const Center(child: CircularProgressIndicator()),
                      // إطار التوجيه
                      Center(
                        child: Container(
                          width: 220,
                          height: 140,
                          decoration: BoxDecoration(
                            border: Border.all(
                                color: AppColors.PRIMARY_BLUE, width: 2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Center(
                child: Text(
                  'وجّه الكاميرا نحو الباركود',
                  style: TextStyle(color: AppColors.TEXT_SECONDARY, fontSize: 13),
                ),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.NEUTRAL_BG,
                    borderRadius:
                        BorderRadius.circular(AppLayout.BORDER_RADIUS),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(
                        color: AppColors.DANGER_RED, fontSize: 13),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 16),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.NEUTRAL_BG,
                  borderRadius: BorderRadius.circular(AppLayout.BORDER_RADIUS),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.qr_code_scanner,
                        color: AppColors.PRIMARY_BLUE, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'الكاميرا غير مدعومة على هذا الجهاز.\nاستخدم قارئ الباركود الخارجي (USB) وامسح الحقل أدناه مباشرة.',
                        style: TextStyle(
                          color: AppColors.TEXT_SECONDARY,
                          fontSize: 13,
                          height: 1.6,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
            Text(
              'الإدخال اليدوي / قارئ خارجي',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: AppColors.PRIMARY_BLUE_DARK,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _manualController,
                    autofocus: true,
                    textInputAction: TextInputAction.go,
                    decoration: const InputDecoration(
                      hintText: 'امسح بالقارئ أو اكتب الكود...',
                      prefixIcon: Icon(Icons.qr_code_2),
                    ),
                    onSubmitted: _submitBarcode,
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: () => _submitBarcode(_manualController.text),
                  child: const Text('تأكيد'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
