import 'package:drift/drift.dart';

import 'app_database.dart';

/// Tanggal Sheet: `YYYY-MM-DD` **tanggal lokal** (WIB), bukan UTC.
/// Mengirim ISO penuh membuat server menolak `VALIDATION` dan transaksi
/// 00:00–06:59 WIB mundur sehari (D-22).
String dateOnly(DateTime value) {
  final local = value.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '${local.year}-$month-$day';
}

/// Kebalikan [dateOnly]. Menerima `YYYY-MM-DD` maupun ISO penuh (data lama).
DateTime parseDateOnly(String value) {
  if (!value.contains('T')) {
    final parts = value.split('-');
    return DateTime(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
  }
  final local = DateTime.parse(value).toLocal();
  return DateTime(local.year, local.month, local.day);
}

String? _iso(DateTime? value) => value?.toUtc().toIso8601String();

DateTime? _parseIso(Object? value) {
  if (value == null) return null;
  final text = value as String;
  return text.isEmpty ? null : DateTime.parse(text).toUtc();
}

// ---------------------------------------------------------------------------
// transactions
// ---------------------------------------------------------------------------

/// Kunci JSON mengikuti nama kolom Sheet (snake_case), sama dengan kolom
/// SQLite hasil drift sehingga payload sinkron dipakai dua arah.
Map<String, Object?> transactionToMap(Transaction t) => {
      'id': t.id,
      'date': dateOnly(t.date),
      'type': t.type,
      'amount': t.amount,
      'category_id': t.categoryId,
      'account': t.account,
      'merchant': t.merchant,
      'note': t.note,
      'member_email': t.memberEmail,
      'source': t.source,
      'goal_id': t.goalId,
      'receipt_url': t.receiptUrl,
      'raw_text': t.rawText,
      'created_at': _iso(t.createdAt),
      'updated_at': _iso(t.updatedAt),
      'is_deleted': t.isDeleted,
    };

TransactionsCompanion transactionFromMap(Map<String, Object?> m) {
  return TransactionsCompanion(
    id: Value(m['id']! as String),
    date: Value(parseDateOnly(m['date']! as String)),
    type: Value(m['type']! as String),
    amount: Value((m['amount']! as num).toDouble()),
    categoryId: Value(_emptyToNull(m['category_id'])),
    account: Value((m['account'] as String?) ?? ''),
    merchant: Value(_emptyToNull(m['merchant'])),
    note: Value(_emptyToNull(m['note'])),
    memberEmail: Value(m['member_email']! as String),
    source: Value(m['source']! as String),
    goalId: Value(_emptyToNull(m['goal_id'])),
    receiptUrl: Value(_emptyToNull(m['receipt_url'])),
    rawText: Value(_emptyToNull(m['raw_text'])),
    createdAt: Value(_parseIso(m['created_at']) ?? DateTime.now().toUtc()),
    updatedAt: Value(_parseIso(m['updated_at']) ?? DateTime.now().toUtc()),
    isDeleted: Value((m['is_deleted'] as bool?) ?? false),
  );
}

String? _emptyToNull(Object? value) {
  final text = value as String?;
  if (text == null || text.isEmpty) return null;
  return text;
}

// ---------------------------------------------------------------------------
// members
// ---------------------------------------------------------------------------

Map<String, Object?> memberToMap(Member m) => {
      'id': m.id,
      'email': m.email,
      'name': m.name,
      'role': m.role,
      'status': m.status,
      'joined_at': _iso(m.joinedAt),
      'updated_at': _iso(m.updatedAt),
    };

MembersCompanion memberFromMap(Map<String, Object?> m) => MembersCompanion(
      email: Value(m['email']! as String),
      id: Value(_emptyToNull(m['id'])),
      name: Value((m['name'] as String?) ?? ''),
      role: Value((m['role'] as String?) ?? MemberRole.member),
      status: Value((m['status'] as String?) ?? 'active'),
      joinedAt: Value(_parseIso(m['joined_at']) ?? DateTime.now().toUtc()),
      updatedAt: Value(_parseIso(m['updated_at']) ?? DateTime.now().toUtc()),
    );

// ---------------------------------------------------------------------------
// categories
// ---------------------------------------------------------------------------

Map<String, Object?> categoryToMap(Category c) => {
      'id': c.id,
      'name': c.name,
      'type': c.type,
      'icon': c.icon,
      'is_active': c.isActive,
      'updated_at': _iso(c.updatedAt),
    };

CategoriesCompanion categoryFromMap(Map<String, Object?> m) =>
    CategoriesCompanion(
      id: Value(m['id']! as String),
      name: Value((m['name'] as String?) ?? ''),
      type: Value((m['type'] as String?) ?? TransactionType.outFlow),
      icon: Value((m['icon'] as String?) ?? ''),
      isActive: Value((m['is_active'] as bool?) ?? true),
      updatedAt: Value(_parseIso(m['updated_at']) ?? DateTime.now().toUtc()),
    );

// ---------------------------------------------------------------------------
// budgets
// ---------------------------------------------------------------------------

Map<String, Object?> budgetToMap(Budget b) => {
      'id': b.id,
      'month': b.month,
      'category_id': b.categoryId,
      'type': b.type,
      'limit_amount': b.limitAmount,
      'allocated_amount': b.allocatedAmount,
      'updated_at': _iso(b.updatedAt),
    };

BudgetsCompanion budgetFromMap(Map<String, Object?> m) => BudgetsCompanion(
      id: Value(m['id']! as String),
      month: Value(m['month']! as String),
      categoryId: Value(m['category_id']! as String),
      type: Value((m['type'] as String?) ?? BudgetType.limit),
      limitAmount: Value(((m['limit_amount'] as num?) ?? 0).toDouble()),
      allocatedAmount:
          Value(((m['allocated_amount'] as num?) ?? 0).toDouble()),
      updatedAt: Value(_parseIso(m['updated_at']) ?? DateTime.now().toUtc()),
    );

// ---------------------------------------------------------------------------
// goals
// ---------------------------------------------------------------------------

Map<String, Object?> goalToMap(Goal g) => {
      'id': g.id,
      'name': g.name,
      'target_amount': g.targetAmount,
      'monthly_allocation': g.monthlyAllocation,
      'due_date': g.dueDate == null ? null : dateOnly(g.dueDate!),
      'status': g.status,
      'is_deleted': g.isDeleted,
      'updated_at': _iso(g.updatedAt),
    };

GoalsCompanion goalFromMap(Map<String, Object?> m) => GoalsCompanion(
      id: Value(m['id']! as String),
      name: Value((m['name'] as String?) ?? ''),
      targetAmount: Value(((m['target_amount'] as num?) ?? 0).toDouble()),
      monthlyAllocation:
          Value(((m['monthly_allocation'] as num?) ?? 0).toDouble()),
      dueDate: Value(
        m['due_date'] == null || (m['due_date'] as String).isEmpty
            ? null
            : parseDateOnly(m['due_date']! as String),
      ),
      status: Value((m['status'] as String?) ?? 'active'),
      createdAt: Value(_parseIso(m['updated_at']) ?? DateTime.now().toUtc()),
      updatedAt: Value(_parseIso(m['updated_at']) ?? DateTime.now().toUtc()),
      isDeleted: Value((m['is_deleted'] as bool?) ?? false),
    );

// ---------------------------------------------------------------------------
// config_parser
// ---------------------------------------------------------------------------

Map<String, Object?> configParserToMap(ConfigParser c) => {
      'id': c.id,
      'package_name': c.packageName,
      'bank_group': c.bankGroup,
      'app_name': c.appName,
      'pattern': c.pattern,
      'field_map': c.fieldMap,
      'version': c.version,
      'is_active': c.isActive,
      'updated_at': _iso(c.updatedAt),
    };

ConfigParsersCompanion configParserFromMap(Map<String, Object?> m) =>
    ConfigParsersCompanion(
      id: Value(m['id']! as String),
      packageName: Value((m['package_name'] as String?) ?? ''),
      bankGroup: Value((m['bank_group'] as String?) ?? ''),
      appName: Value((m['app_name'] as String?) ?? ''),
      pattern: Value(_emptyToNull(m['pattern'])),
      fieldMap: Value((m['field_map'] as String?) ?? '{}'),
      version: Value(((m['version'] as num?) ?? 1).toInt()),
      isActive: Value((m['is_active'] as bool?) ?? false),
      updatedAt: Value(_parseIso(m['updated_at']) ?? DateTime.now().toUtc()),
    );
