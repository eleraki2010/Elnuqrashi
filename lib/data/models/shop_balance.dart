/// لحظة مالية شاملة للمحل: السيولة النقدية + قيمة المخزون + الديون.
///
/// المصادر:
/// - النقد من المبيعات = ما استُلم فعلياً (MIN(paid_amount, total)): الآجل
///   لا يُحتسب إلا الجزء المسدد فقط.
/// - تحصيلات العملاء = المدفوعات الواردة (payments direction = 'in').
/// - مدفوعات الموردين = المدفوعات الصادرة (payments direction = 'out').
/// - المصروفات = مصروفات تشغيلية مسجلة.
/// - مرتجعات نقدية = قيمة مرتجعات فواتير الكاش/المحفظة (عادت نقداً من الصندوق).
class ShopBalance {
  final double cashFromSales;
  final double collectionsIn;
  final double supplierPaymentsOut;
  final double expensesOut;
  final double returnsRefundOut;
  final double inventoryValue;
  final double customerDebt;
  final double supplierOwed;

  const ShopBalance({
    this.cashFromSales = 0.0,
    this.collectionsIn = 0.0,
    this.supplierPaymentsOut = 0.0,
    this.expensesOut = 0.0,
    this.returnsRefundOut = 0.0,
    this.inventoryValue = 0.0,
    this.customerDebt = 0.0,
    this.supplierOwed = 0.0,
  });

  /// الرصيد النقدي في الصندوق (الداخل − الخارج).
  /// يتضمن فقط ما استُلم فعلياً — لا يُحتسب دين الآجل ولا المرتجعات
  /// الائمانية (التي تُخصم من دين العميل لا من النقد).
  double get cashBalance =>
      cashFromSales +
      collectionsIn -
      supplierPaymentsOut -
      expensesOut -
      returnsRefundOut;

  /// صافي مركز المحل: النقد + قيمة البضاعة + ما لك من ديون − ما عليك من مستحقات.
  double get netWorth =>
      cashBalance + inventoryValue + customerDebt - supplierOwed;
}
