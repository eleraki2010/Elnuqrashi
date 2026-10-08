/// بيانات المحل المحلية: مسار شعار المحل على القرص.
class ShopProfile {
  final String id; // 'shop' — صف واحد ثابت
  final String? logoPath;
  final DateTime? updatedAt;

  const ShopProfile({
    this.id = 'shop',
    this.logoPath,
    this.updatedAt,
  });
}
