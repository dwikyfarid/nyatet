/// Tautan publik aplikasi. Nilai sementara: halaman belum terbit.
/// Ganti di satu tempat ini saja — jangan hardcode URL di widget (F9/F12).
class AppLinks {
  const AppLinks._();

  static const String privacyPolicy = 'https://nyatet.app/privasi';
  static const String deleteData = 'https://nyatet.app/hapus-data';

  /// Halaman belum terbit → aplikasi menampilkan penjelasan jujur, bukan
  /// membuka tautan yang mati tanpa keterangan.
  static const Set<String> notPublishedYet = {privacyPolicy, deleteData};
}
