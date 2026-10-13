/// لحظة مالية شاملة للمحل منضبطة بالقواعد والمعايير المحاسبية:
///
/// 1. رصيد الصندوق (السيولة النقدية الفعلية):
///    - داخل (+): ما دُفع نقداً في المبيعات + تحصيلات ديون العملاء + أي نقد مسترد من الموردين.
///    - خارج (−): مدفوعات الموردين + المصروفات التشغيلية + المبالغ المردودة نقداً للعملاء في المرتجعات.
///
/// 2. صافي مركز المحل (حقوق الملكية / رأس المال):
///    - الأصول (Assets): النقد في الصندوق + المخزون بالتكلفة + ديون العملاء (لنا) + دفعات مقدمة للموردين.
///    - الخصوم (Liabilities): مستحقات الموردين (علينا) + أرصدة دائنة للعملاء (أمانات).
///    - صافي المركز = الأصول − الخصوم.
class ShopBalance {
  final double cashFromSales;
  final double collectionsIn;
  final double supplierRefundsIn;
  final double supplierPaymentsOut;
  final double expensesOut;
  final double returnsRefundOut;
  final double inventoryValue;
  final double customerDebt;
  final double customerCredit;
  final double supplierOwed;
  final double supplierAdvance;

  const ShopBalance({
    this.cashFromSales = 0.0,
    this.collectionsIn = 0.0,
    this.supplierRefundsIn = 0.0,
    this.supplierPaymentsOut = 0.0,
    this.expensesOut = 0.0,
    this.returnsRefundOut = 0.0,
    this.inventoryValue = 0.0,
    this.customerDebt = 0.0,
    this.customerCredit = 0.0,
    this.supplierOwed = 0.0,
    this.supplierAdvance = 0.0,
  });

  /// إجمالي المقبوضات النقدية الداخلة للخزينة
  double get totalCashIn =>
      cashFromSales + collectionsIn + supplierRefundsIn;

  /// إجمالي المدفوعات النقدية الخارجة من الخزينة
  double get totalCashOut =>
      supplierPaymentsOut + expensesOut + returnsRefundOut;

  /// الرصيد النقدي الفعلي في الصندوق
  double get cashBalance => totalCashIn - totalCashOut;

  /// إجمالي أصول المحل (Assets)
  double get totalAssets =>
      cashBalance + inventoryValue + customerDebt + supplierAdvance;

  /// إجمالي التزامات وخصوم المحل (Liabilities)
  double get totalLiabilities => supplierOwed + customerCredit;

  /// صافي مركز المحل (Equity / Net Worth)
  double get netWorth => totalAssets - totalLiabilities;
}
