import 'package:flutter_test/flutter_test.dart';
import 'package:nyatet/data/database/app_database.dart';
import 'package:nyatet/domain/access_policy.dart';

Transaction _txn({
  String id = 't1',
  String memberEmail = 'anak@example.com',
  DateTime? createdAt,
}) {
  final created = createdAt ?? DateTime.utc(2026, 11, 20);
  return Transaction(
    id: id,
    date: created,
    type: 'out',
    amount: 10000,
    categoryId: null,
    account: '',
    merchant: null,
    note: null,
    memberEmail: memberEmail,
    source: 'manual',
    goalId: null,
    receiptUrl: null,
    rawText: null,
    createdAt: created,
    updatedAt: created,
    isDeleted: false,
  );
}

void main() {
  group('AccessPolicy — admin', () {
    const policy = AccessPolicy(email: 'bapak@example.com', role: 'admin');

    test('boleh melihat transaksi siapa pun', () {
      expect(policy.canView(_txn()).allowed, isTrue);
      expect(
        policy.canView(_txn(memberEmail: 'ibu@example.com')).allowed,
        isTrue,
      );
    });

    test('boleh edit & hapus semua transaksi tanpa batas waktu', () {
      final old = _txn(createdAt: DateTime.utc(2020, 1, 1));
      expect(policy.canEdit(old).allowed, isTrue);
      expect(policy.canDelete(old).allowed, isTrue);
    });

    test('boleh mengelola kategori dan tujuan', () {
      expect(policy.canManageCategories().allowed, isTrue);
      expect(policy.canManageGoals().allowed, isTrue);
    });
  });

  group('AccessPolicy — anggota (D-03, D-05)', () {
    final now = DateTime.utc(2026, 11, 25);
    final policy = AccessPolicy(
      email: 'anak@example.com',
      role: 'member',
      now: now,
    );

    test('hanya melihat transaksi miliknya', () {
      expect(policy.canView(_txn()).allowed, isTrue);
      final other = _txn(memberEmail: 'bapak@example.com');
      expect(policy.canView(other).allowed, isFalse);
      expect(policy.canView(other).reason, contains('sendiri'));
    });

    test('edit milik sendiri dalam 7 hari diizinkan', () {
      final recent = _txn(createdAt: now.subtract(const Duration(days: 6)));
      expect(policy.canEdit(recent).allowed, isTrue);
    });

    test('edit milik sendiri lewat 7 hari ditolak dengan alasan', () {
      final old = _txn(createdAt: now.subtract(const Duration(days: 8)));
      final decision = policy.canEdit(old);
      expect(decision.allowed, isFalse);
      expect(decision.reason, contains('7 hari'));
    });

    test('batas tepat 7 hari masih diizinkan', () {
      final exact = _txn(createdAt: now.subtract(const Duration(days: 7)));
      expect(policy.canEdit(exact).allowed, isTrue);
    });

    test('edit transaksi orang lain ditolak', () {
      final other = _txn(memberEmail: 'bapak@example.com');
      expect(policy.canEdit(other).allowed, isFalse);
    });

    test('tidak boleh menghapus transaksi apa pun', () {
      expect(policy.canDelete(_txn()).allowed, isFalse);
      expect(policy.canDelete(_txn()).reason, contains('tidak bisa menghapus'));
    });

    test('tidak boleh mengelola kategori/tujuan, tapi boleh setor tujuan', () {
      expect(policy.canManageCategories().allowed, isFalse);
      expect(policy.canManageGoals().allowed, isFalse);
      expect(policy.canDepositToGoal().allowed, isTrue);
    });
  });
}
