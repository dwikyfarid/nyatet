import '../data/database/app_database.dart';

/// Hasil evaluasi hak akses satu aksi pada satu transaksi.
class AccessDecision {
  const AccessDecision.allow() : allowed = true, reason = null;
  const AccessDecision.deny(String this.reason) : allowed = false;

  final bool allowed;

  /// Alasan penolakan dalam bahasa user (dipakai di UI & snackbar).
  final String? reason;

  @override
  String toString() => allowed ? 'allow' : 'deny($reason)';
}

/// Hak akses transaksi sesuai D-03 / D-05, ditulis sebagai satu tempat
/// kebenaran yang dipakai UI **dan** diuji — supaya aturan role tidak
/// tersebar sebagai `if` di banyak layar.
///
/// Catatan: ini penegakan sisi klien. Server (Apps Script) tetap penegak
/// utama dan menolak permintaan yang melanggar aturan yang sama.
class AccessPolicy {
  const AccessPolicy({
    required this.email,
    required this.role,
    this.now,
    this.memberEditWindow = const Duration(days: 7),
  });

  final String email;
  final String role;

  /// Waktu acuan (bisa diinjeksi untuk pengujian batas 7 hari).
  final DateTime? now;

  /// Batas edit anggota: 7 hari sejak transaksi **dibuat** (D-05).
  final Duration memberEditWindow;

  bool get isAdmin => role == MemberRole.admin;

  AccessDecision canView(Transaction t) {
    if (isAdmin) return const AccessDecision.allow();
    if (t.memberEmail == email) return const AccessDecision.allow();
    return const AccessDecision.deny('Anggota hanya melihat transaksinya sendiri');
  }

  AccessDecision canCreate() => const AccessDecision.allow();

  AccessDecision canEdit(Transaction t) {
    if (isAdmin) return const AccessDecision.allow();
    if (t.memberEmail != email) {
      return const AccessDecision.deny('Hanya transaksi sendiri yang bisa diedit');
    }
    final created = t.createdAt;
    final reference = now ?? DateTime.now();
    if (reference.difference(created) > memberEditWindow) {
      return const AccessDecision.deny(
        'Transaksi lebih dari 7 hari sejak dibuat tidak bisa diedit',
      );
    }
    return const AccessDecision.allow();
  }

  AccessDecision canDelete(Transaction t) {
    if (isAdmin) return const AccessDecision.allow();
    return const AccessDecision.deny('Anggota tidak bisa menghapus transaksi');
  }

  /// Hanya admin yang mengelola kategori & budget (D-03).
  AccessDecision canManageCategories() => isAdmin
      ? const AccessDecision.allow()
      : const AccessDecision.deny('Hanya admin yang mengelola kategori & budget');

  /// Setoran tujuan boleh dilakukan anggota karena itu transaksinya sendiri
  /// (D-20); perubahan definisi tujuan tetap admin.
  AccessDecision canDepositToGoal() => const AccessDecision.allow();

  AccessDecision canManageGoals() => isAdmin
      ? const AccessDecision.allow()
      : const AccessDecision.deny('Hanya admin yang mengelola tujuan dana');
}
