import 'apps_script_api.dart';

/// Cara menghapus akun menurut kondisi (F12/D-33).
enum DeletionMode {
  /// Anggota biasa: `account.delete` untuk akunnya sendiri.
  member,

  /// Admin yang masih punya anggota aktif: tidak boleh hapus keluarga,
  /// harus pindah admin / hapus anggota dulu.
  adminWithOthers,

  /// Admin terakhir: `family.delete` dengan mengetik nama keluarga.
  lastAdmin,
}

class DeletionPlan {
  const DeletionPlan({
    required this.mode,
    required this.familyName,
    this.message,
  });

  final DeletionMode mode;
  final String familyName;
  final String? message;
}

class DeletionOutcome {
  const DeletionOutcome({
    required this.ok,
    required this.message,
    this.alreadyDeleted = false,
  });

  final bool ok;
  final String message;
  final bool alreadyDeleted;
}

/// Logika hapus akun. Tidak pernah menyentuh data lokal: transaksi keluarga
/// bukan milik satu anggota, dan kegagalan tidak boleh terlihat seperti sukses.
class AccountDeletionService {
  AccountDeletionService({
    required this.api,
    required this.token,
    required this.email,
    required this.role,
    required this.familyName,
    required this.signOut,
  });

  final AppsScriptApi api;
  final String token;
  final String email;
  final String role;
  final String familyName;
  final Future<void> Function() signOut;

  Future<DeletionPlan> plan() async {
    if (role != 'admin') {
      return DeletionPlan(mode: DeletionMode.member, familyName: familyName);
    }
    final members = await api.memberList(token);
    final others = members.where(
      (m) => m.isActive && m.email != email,
    );
    if (others.isNotEmpty) {
      return const DeletionPlan(
        mode: DeletionMode.adminWithOthers,
        familyName: '',
        message: 'Masih ada anggota aktif lain. Pindahkan peran admin atau '
            'hapus anggota tersebut dulu; menghapus seluruh keluarga tidak '
            'tersedia selama mereka masih ada.',
      );
    }
    return DeletionPlan(mode: DeletionMode.lastAdmin, familyName: familyName);
  }

  /// `account.delete` — anggota mana pun, admin hanya jika tidak ada anggota
  /// aktif lain (server yang menegakkan). Sukses = sesi berakhir.
  Future<DeletionOutcome> deleteAccount() async {
    try {
      final result = await api.deleteAccount(token);
      if (!result.ok) {
        return const DeletionOutcome(
          ok: false,
          message: 'Server belum mengonfirmasi penghapusan akun.',
        );
      }
      await signOut();
      return DeletionOutcome(
        ok: true,
        alreadyDeleted: result.alreadyDeleted,
        message: result.alreadyDeleted
            ? 'Akun ini sudah terhapus sebelumnya — sesi diakhiri.'
            : 'Akun dihapus. Transaksi keluarga tetap ada sebagai '
                '"Anggota dihapus".',
      );
    } on ApiException catch (e) {
      return DeletionOutcome(ok: false, message: _errorMessage(e));
    } catch (_) {
      return const DeletionOutcome(
        ok: false,
        message: 'Tidak bisa menghapus akun (jaringan). Coba lagi.',
      );
    }
  }

  /// `family.delete` — hanya admin terakhir; `confirmName` harus sama persis.
  Future<DeletionOutcome> deleteFamily(String confirmName) async {
    if (confirmName != familyName) {
      return const DeletionOutcome(
        ok: false,
        message: 'Nama keluarga tidak cocok — tombol tidak mengirim apa pun.',
      );
    }
    try {
      final result = await api.deleteFamily(token, confirmName: confirmName);
      if (!result.ok) {
        return const DeletionOutcome(
          ok: false,
          message: 'Server belum mengonfirmasi penghapusan keluarga.',
        );
      }
      await signOut();
      final rows = result.rowsRemoved ?? 0;
      return DeletionOutcome(
        ok: true,
        alreadyDeleted: result.alreadyDeleted,
        message: 'Keluarga dihapus: $rows baris di 7 tab'
            '${result.fileTrashed == true ? ', file di-trash' : ''}'
            '${result.receiptFolderTrashed == true ? ', folder nota ikut di-trash' : ''}.',
      );
    } on ApiException catch (e) {
      return DeletionOutcome(ok: false, message: _errorMessage(e));
    } catch (_) {
      return const DeletionOutcome(
        ok: false,
        message: 'Tidak bisa menghapus keluarga (jaringan). Coba lagi.',
      );
    }
  }

  String _errorMessage(ApiException e) {
    if (e.code == ApiErrorCode.forbidden) {
      return 'Ditolak server: ${e.message}';
    }
    if (e.code == ApiErrorCode.unauthenticated) {
      return 'Sesi berakhir — masuk lagi lalu ulangi. Tidak ada data yang '
          'dihapus.';
    }
    if (e.code == ApiErrorCode.validation) {
      return 'Ditolak server: ${e.message}';
    }
    return 'Gagal menghubungi server. Tidak ada data yang dihapus.';
  }
}
