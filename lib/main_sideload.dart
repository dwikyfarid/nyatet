// Entrypoint build `sideload`: APK uji / di luar Play, memuat cek update
// GitHub (REL-03). Build Play memakai `main_play.dart` (REL-04).
//
//   flutter build apk --debug --flavor sideload -t lib/main_sideload.dart
import 'main.dart' show bootstrap;

Future<void> main() => bootstrap(enableUpdateChecker: true);
