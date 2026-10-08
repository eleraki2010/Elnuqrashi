# SPECKIT — Alnokrashy POS & Inventory App
> ملف مرجعي ثابت (Source of Truth). أي AI Model (Claude / GPT / Gemini / DeepSeek / أي موديل رخيص) يبني على هذا المشروع **يجب** يقرأ هذا الملف كامل قبل كتابة أي كود، ويلتزم بكل قاعدة فيه حرفيًا دون اجتهاد شخصي. لو في تعارض بين طلب المستخدم وهذا الملف، هذا الملف هو المرجع الأعلى إلا لو المستخدم عدّله صراحة.

---

## 0. AI_INSTRUCTIONS (اقرأها أولًا)

```
ROLE: You are building "Alnokrashy POS" — a retail POS & inventory app.
RULES:
1. Do NOT invent new features not listed in section 3 (SCOPE). If unsure, implement the smallest reasonable version and add a TODO comment.
2. ALWAYS follow the color tokens in section 2 exactly (hex values given). Never substitute with different shades.
3. ALWAYS follow the data schema in section 4 exactly — field names, types. If a field is missing, add it consistently across all layers (DB, API, UI) instead of guessing per-file.
4. Build MVP scope (section 6, Phase 1) FIRST, fully working, before touching Phase 2/3/4.
5. Keep UI in Arabic (RTL) as default language. All user-facing text = Arabic. All code identifiers (variables, functions, tables) = English.
6. App MUST work fully OFFLINE first. Cloud sync is secondary/optional layer, never a blocker for core features.
7. Every screen must map to section 7 (SCREENS) — do not rename or merge screens without reason.
8. When context is limited (cheap/small model), work file-by-file, always re-reading this SPECKIT before starting a new file, and never contradict earlier decisions already implemented.
9. Do not add a login/auth system unless explicitly working on section 3.11.
10. Currency = Egyptian Pound (EGP / ج.م). Number format: Arabic-Indic optional, but default to Western digits (0-9) for compatibility.
```

---

## 1. PROJECT META

| Key | Value |
|---|---|
| project_name | Alnokrashy POS |
| store_name (display) | النقراشي للأدوات الصحية والسيراميك |
| business_type | Retail (Plumbing / Sanitary ware / Ceramics) — generic enough for hardware, paint, electrical stores |
| primary_language | Arabic (RTL) |
| code_language | English (identifiers, comments) |
| currency | EGP |
| target_platforms | Android, iOS, Web, Windows Desktop |
| recommended_stack | Flutter (single codebase → Android/iOS/Web/Windows) |
| alt_stack | React + Capacitor (mobile) + Electron/Tauri (Windows) + PWA (Web) — use only if Flutter unavailable |
| architecture | Offline-first local DB + optional cloud sync |
| local_db | SQLite (via `sqflite` / `drift` in Flutter, or equivalent) |
| state_mgmt (flutter) | Riverpod or Bloc (pick ONE, stay consistent across whole app) |
| cloud_sync (optional, phase 3+) | Firebase / Supabase (pick ONE) |

---

## 2. DESIGN TOKENS (لا تُغيّر هذه القيم)

```yaml
colors:
  primary_blue:   "#1E5FBF"   # هيدر، أزرار رئيسية، عناصر تفاعلية
  primary_blue_dark: "#123E80"
  success_green:  "#1FAA59"   # بيع ناجح، ربح، متوفر
  danger_red:     "#E23B3B"   # تنبيه، نفاد مخزون، حذف
  neutral_bg:     "#F5F7FA"
  neutral_surface:"#FFFFFF"
  text_primary:   "#1A1A1A"
  text_secondary: "#6B7280"
  warning_amber:  "#F5A623"   # اقتراب من الحد الأدنى (تحذير، ليس نفاد كامل)

typography:
  font_family: "Cairo" # أو أي خط عربي واضح يدعم RTL (Tajawal كبديل)
  base_size: 16
  heading_scale: [28, 22, 18, 16]

layout:
  direction: rtl
  min_touch_target: 48dp
  border_radius: 12
  spacing_unit: 8
```

---

## 3. SCOPE (النطاق — لا تتعدَّاه بدون طلب صريح)

### يشمل:
- CRUD منتجات (إضافة/تعديل/حذف/بحث)
- إدارة مخزون + تنبيه حد أدنى + تنبيه نفاد
- شاشة POS (بيع سريع + حساب الباقي)
- سجل مبيعات + سجل مشتريات
- حساب أرباح (تلقائي = سعر بيع - سعر شراء)
- إدارة عملاء (+ ديون / كشف حساب)
- إدارة موردين (+ مستحقات / كشف حساب)
- تقارير: يومي / شهري / مخصص
- Dashboard برقمي: مبيعات اليوم، عدد فواتير، ربح، تنبيهات مخزون
- دعم باركود (مسح + توليد اختياري)
- طباعة فاتورة حرارية (58/80mm) أو مشاركة PDF

### لا يشمل (إلا لو طُلب لاحقًا):
- محاسبة ضريبية متقدمة / ربط مصلحة الضرائب
- نظام محاسبة عام (دفاتر أستاذ، قيود مزدوجة)
- تعدد فروع كامل (Multi-branch sync) — هذا Phase 4
- نظام صلاحيات متقدم متعدد الأدوار — Phase 3 فقط دور "مالك" و"كاشير"

---

## 4. DATA SCHEMA (ثابت — التزم بالأسماء دي بالحرف)

```
Product {
  id: string (uuid)
  name: string
  barcode: string | null
  category_id: string (FK -> Category)
  unit: string            // e.g. "piece", "meter", "carton", "roll"
  purchase_price: decimal
  sale_price: decimal
  quantity: integer
  min_quantity_alert: integer
  image_url: string | null
  notes: string | null
  created_at, updated_at: datetime
}

Category { id, name, parent_id? }

StockMovement {
  id, product_id (FK), type: enum[sale, purchase, adjustment, damage, count]
  quantity_change: integer   // + دخول / - خروج
  reference_id: string | null // invoice id etc.
  note: string | null
  created_at: datetime
}

Customer {
  id, name, phone, address, notes
  balance_due: decimal   // موجب = عليه دين
  created_at, updated_at
}

Supplier {
  id, name, phone, address, notes
  balance_owed: decimal  // موجب = مستحق له
  created_at, updated_at
}

SaleInvoice {
  id, invoice_number, customer_id?, cashier_id?
  items: [SaleInvoiceItem]
  subtotal, discount, tax, total: decimal
  paid_amount: decimal
  change_due: decimal
  payment_method: enum[cash, wallet, credit]
  status: enum[completed, held, returned, cancelled]
  created_at: datetime
}

SaleInvoiceItem {
  product_id, quantity, unit_price, line_total
}

PurchaseInvoice {
  id, supplier_id, items: [PurchaseInvoiceItem]
  total: decimal, paid_amount: decimal
  created_at: datetime
}

PurchaseInvoiceItem { product_id, quantity, unit_cost, line_total }

Payment {
  id, party_type: enum[customer, supplier]
  party_id, amount, direction: enum[in, out]
  created_at
}

User {
  id, name, phone/username, password_hash, role: enum[owner, cashier]
}

Expense {
  id, title, amount, category, created_at
}
```

---

## 5. CORE BUSINESS RULES (منطق ثابت — لا يُترك للتخمين)

1. `line_total = quantity * unit_price`
2. `subtotal = SUM(line_total)`
3. `total = subtotal - discount + tax`
4. `change_due = paid_amount - total` (لو سالب → يظهر "المتبقي على العميل" بدل "الباقي")
5. عند إتمام بيع (status = completed): يُنشأ `StockMovement` بقيمة سالبة لكل منتج، وتُخصم `quantity` من `Product` فورًا.
6. عند تسجيل شراء: `StockMovement` موجب، وتُضاف الكمية لـ `Product.quantity`.
7. لو `payment_method = credit`: يُضاف `total - paid_amount` إلى `Customer.balance_due`.
8. تنبيه المخزون: لو `Product.quantity <= min_quantity_alert` → أصفر (تحذير)، لو `quantity == 0` → أحمر (نفاد).
9. الربح لكل صنف = `(sale_price - purchase_price) * quantity_sold`.
10. صافي الربح اليومي = `SUM(profit من فواتير اليوم المكتملة) - SUM(Expense لليوم)`.
11. أي عملية حذف/إلغاء فاتورة تُسجَّل في Audit Log ولا تُحذف البيانات فعليًا (Soft Delete) — تعليم `status = cancelled` فقط.

---

## 6. BUILD ORDER (نفّذ بالترتيب — لا تقفز مرحلة)

### Phase 1 — MVP (ابدأ هنا وأنهِه بالكامل أولًا)
1. Setup project + local DB schema (section 4)
2. Products CRUD + Categories
3. Inventory quantity tracking + low-stock alert (basic list, لسه بدون إشعارات push)
4. Search (live search by name/barcode)
5. POS screen: add items → calculate total → enter paid amount → show change → save SaleInvoice
6. Sales history list (read-only)
7. Basic Dashboard: today's sales total, invoice count, low-stock count

### Phase 2
8. Purchases (PurchaseInvoice CRUD) + auto stock update
9. Customers CRUD + credit sales + balance_due tracking + payments
10. Suppliers CRUD + balance_owed tracking + payments
11. Reports: daily / monthly / custom range
12. Profit calculation (per product, per period)

### Phase 3
13. Barcode scanning (camera + external scanner)
14. Thermal printer integration (58/80mm) + PDF export/share
15. Cloud backup + restore
16. User roles: owner vs cashier + login/PIN

### Phase 4
17. Multi-branch support
18. Excel import/export for products
19. WhatsApp reminders for debts

---

## 7. SCREENS MAP (لا تُعيد تسمية الشاشات)

```
- LoginScreen (Phase 3+)
- DashboardScreen
- POSScreen (شاشة البيع الرئيسية)
- ProductsListScreen
  - ProductFormScreen (add/edit)
- InventoryAlertsScreen
- CustomersListScreen
  - CustomerDetailScreen (كشف حساب)
- SuppliersListScreen
  - SupplierDetailScreen
- SalesHistoryScreen
- PurchasesHistoryScreen
  - PurchaseFormScreen
- ReportsScreen
  - DailyReportTab / MonthlyReportTab / CustomRangeTab
- SettingsScreen
  - StoreInfoSettings (اسم المحل، الشعار، الرقم)
  - UsersSettings (Phase 3)
  - BackupSettings (Phase 3)
```

---

## 8. UI COPY DEFAULTS (نصوص عربية جاهزة للاستخدام في الواجهة)

```
app_title: "النقراشي للأدوات الصحية والسيراميك"
btn_new_sale: "بيع جديد"
btn_add_product: "إضافة منتج"
label_total: "الإجمالي"
label_paid: "المدفوع"
label_change: "الباقي"
label_remaining_on_customer: "المتبقي على العميل"
alert_low_stock: "المنتج على وشك النفاد"
alert_out_of_stock: "المنتج غير متوفر"
confirm_delete: "هل أنت متأكد من الحذف؟ لا يمكن التراجع."
toast_sale_success: "تم إتمام عملية البيع بنجاح"
```

---

## 9. NAMING CONVENTIONS

- Files/folders: `snake_case`
- Classes/Widgets: `PascalCase`
- Variables/functions: `camelCase`
- DB tables/columns: `snake_case` (matches section 4 exactly)
- Constants (colors, config): `UPPER_SNAKE_CASE` in a single `app_constants.dart` (or equivalent) file — **never hardcode hex colors inline in UI files**.

---

## 10. DEFINITION OF DONE (لكل Phase)

- [ ] كل الشاشات المذكورة في الـ Phase تعمل وتُحفظ في الـ DB فعليًا (لا Mock data)
- [ ] الألوان مطابقة لـ section 2 بدون استثناء
- [ ] كل النصوص بالعربي RTL
- [ ] يعمل بدون إنترنت بالكامل لميزات هذا الـ Phase
- [ ] تم اختبار: إضافة منتج → بيعه → التأكد أن المخزون نقص → التأكد أن الداشبورد تحدّث

---

## 11. HOW TO USE THIS FILE WITH ANY AI MODEL

1. الصق هذا الملف كامل في أول رسالة/System Prompt مع أي موديل (Claude, GPT, Gemini, Llama, DeepSeek...).
2. قول للموديل: "ابدأ بتنفيذ Phase 1 فقط، ملف بملف، والتزم بالـ SPECKIT ده حرفيًا."
3. بعد كل ملف يتكتب، اطلب منه: "راجع الملف اللي كتبته مقابل SPECKIT وأكّد إنه مطابق قبل ما تكمل."
4. لو غيّرت موديل في نص المشروع، الصق نفس الملف تاني — هو ثابت مهما اختلف الموديل، وده اللي بيضمن نفس النتيجة.
