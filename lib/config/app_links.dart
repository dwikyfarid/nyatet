/// Tautan publik aplikasi (D-45). Satu perilaku, tanpa flag build:
/// - URL kosong = halaman belum terbit → baris nonaktif + alasan tertulis.
/// - URL diisi (tanpa mengubah kode UI) = ketukan membuka browser ACTION_VIEW.
///
/// Ganti nilai di satu tempat ini saja; jangan hardcode URL di widget (F9/F12).
class AppLinks {
  const AppLinks._();

  /// Kosong sampai halaman benar-benar terbit (D-45).
  static const String privacyPolicy = '';
  static const String deleteData = '';
}
