// Entrypoint build `play`: TIDAK memuat cek update GitHub (REL-04), karena
// Play melarang aplikasi memperbarui dirinya di luar Play.
// Provider update dimatikan, jadi layanan update tidak pernah dibaca dan
// tidak ada permintaan ke api.github.com.
//
//   flutter build apk --debug --flavor play -t lib/main_play.dart
import 'main.dart' show bootstrap;

/// Build Play TIDAK boleh memuat cek update (kebijakan Play).
const bool kUpdateCheckerEnabled = false;

Future<void> main() => bootstrap(enableUpdateChecker: kUpdateCheckerEnabled);
