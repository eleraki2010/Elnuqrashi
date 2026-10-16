import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:printing/printing.dart';

/// خدمة مشاركة المستندات (فواتير، كشوف حسابات، تقارير) كصور عالية الدقة (PNG).
/// تتيح إرسال المحتوى مباشرة كصورة إلى واتساب، فيسبوك، ماسنجر، وتيليجرام
/// بدلاً من إرسالها كملف PDF يحتاج إلى تنزيل وتطبيق خارجي لفتحه.
class DocumentShareService {
  DocumentShareService._();

  /// تحويل مستند PDF إلى صورة PNG كاملة ومشاركتها مع تطبيقات المشاركة.
  /// إذا كان المستند صفحة واحدة يتم إرسالها كصورة عالية الدقة.
  /// وإذا كان متعدد الصفحات يتم دمجها عمودياً بانسيابية تامة في صورة واحدة مستمرة.
  static Future<void> sharePdfAsImage({
    required Uint8List pdfBytes,
    required String filename,
    double dpi = 200,
  }) async {
    // إزالة امتداد .pdf إن وجد لضمان التسمية بامتداد .png
    final cleanName = filename.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');
    final pngFilename = cleanName.endsWith('.png') ? cleanName : '$cleanName.png';

    try {
      final rasterPages = await Printing.raster(pdfBytes, dpi: dpi).toList();
      if (rasterPages.isEmpty) {
        throw Exception('لم يتم استخراج أي صفحات من المستند');
      }

      final pngBytesList = <Uint8List>[];
      for (final page in rasterPages) {
        final bytes = await page.toPng();
        pngBytesList.add(bytes);
      }

      final finalImageBytes = await combinePngImages(pngBytesList);

      await Printing.sharePdf(
        bytes: finalImageBytes,
        filename: pngFilename,
      );
    } catch (_) {
      // بديل احتياطي فوري إذا تعذرت معالجة الرسوميات على بيئات خاصة
      await Printing.sharePdf(
        bytes: pdfBytes,
        filename: '$cleanName.pdf',
      );
    }
  }

  /// دمج قائمة من صور PNG عمودياً في صورة واحدة عالية الدقة
  static Future<Uint8List> combinePngImages(List<Uint8List> pngList) async {
    if (pngList.isEmpty) {
      throw ArgumentError('قائمة الصور لا يمكن أن تكون فارغة');
    }
    if (pngList.length == 1) {
      return pngList.first;
    }

    final images = <ui.Image>[];
    int totalHeight = 0;
    int maxWidth = 0;

    for (final bytes in pngList) {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final img = frame.image;
      images.add(img);
      totalHeight += img.height;
      if (img.width > maxWidth) {
        maxWidth = img.width;
      }
    }

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(
      recorder,
      ui.Rect.fromLTWH(0, 0, maxWidth.toDouble(), totalHeight.toDouble()),
    );

    // تعبئة الخلفية باللون الأبيض لضمان وضوح النص
    final bgPaint = ui.Paint()..color = const ui.Color(0xFFFFFFFF);
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, maxWidth.toDouble(), totalHeight.toDouble()),
      bgPaint,
    );

    double dy = 0;
    for (final img in images) {
      final dx = (maxWidth - img.width) / 2.0;
      canvas.drawImage(img, ui.Offset(dx, dy), ui.Paint());
      dy += img.height;
    }

    final picture = recorder.endRecording();
    final combinedImage = await picture.toImage(maxWidth, totalHeight);
    final byteData = await combinedImage.toByteData(format: ui.ImageByteFormat.png);

    return byteData!.buffer.asUint8List();
  }
}
