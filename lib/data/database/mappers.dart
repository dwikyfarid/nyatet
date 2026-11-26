import 'package:drift/drift.dart';

import 'app_database.dart';

/// Kunci JSON mengikuti nama kolom Sheet (snake_case), sama dengan kolom
/// SQLite hasil drift sehingga payload sinkron dipakai dua arah.
Map<String, Object?> transactionToMap(Transaction t) => {
      'id': t.id,
      'date': t.date.toUtc().toIso8601String(),
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
      'created_at': t.createdAt.toUtc().toIso8601String(),
      'updated_at': t.updatedAt.toUtc().toIso8601String(),
      'is_deleted': t.isDeleted,
    };

TransactionsCompanion transactionFromMap(Map<String, Object?> m) {
  return TransactionsCompanion(
    id: Value(m['id']! as String),
    date: Value(DateTime.parse(m['date']! as String)),
    type: Value(m['type']! as String),
    amount: Value((m['amount']! as num).toDouble()),
    categoryId: Value(m['category_id'] as String?),
    account: Value((m['account'] as String?) ?? ''),
    merchant: Value(m['merchant'] as String?),
    note: Value(m['note'] as String?),
    memberEmail: Value(m['member_email']! as String),
    source: Value(m['source']! as String),
    goalId: Value(m['goal_id'] as String?),
    receiptUrl: Value(m['receipt_url'] as String?),
    rawText: Value(m['raw_text'] as String?),
    createdAt: Value(DateTime.parse(m['created_at']! as String)),
    updatedAt: Value(DateTime.parse(m['updated_at']! as String)),
    isDeleted: Value((m['is_deleted'] as bool?) ?? false),
  );
}
