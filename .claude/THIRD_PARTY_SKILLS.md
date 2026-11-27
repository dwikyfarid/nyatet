# Skill dan plugin pihak ketiga

Skill di `.claude/skills/` disalin apa adanya dari repo berikut (lisensi di `.claude/licenses/`).

| Sumber | Commit | Lisensi | Isi |
|---|---|---|---|
| [dart-lang/skills](https://github.com/dart-lang/skills) | f84b168 | BSD-3-Clause | 15 skill `dart-*` |
| [zakariaf/Flutter-Skills](https://github.com/zakariaf/Flutter-Skills) | e073e5e | MIT | 40 skill (Riverpod, Drift, testing, dll.) |
| [evanca/flutter-ai-rules](https://github.com/evanca/flutter-ai-rules) | ced864a | MIT | 36 skill (`code-review` diganti nama jadi `flutter-code-review` agar tidak bentrok dengan `/code-review` bawaan) |
| [kpcrmv4/gas-best-practices](https://github.com/kpcrmv4/gas-best-practices) | b0615a6 | MIT | `gas-best-practices` (Google Apps Script) |

Plugin yang diaktifkan lewat `.claude/settings.json` (Claude Code akan menawarkan instal saat repo dibuka):

- `dart-flutter@dart-flutter` dari [flutter/skills](https://github.com/flutter/skills): skill Flutter resmi + Dart MCP server (butuh `dart` di PATH).
- `dart-analyzer@claude-code-lsps` dari [boostvolt/claude-code-lsps](https://github.com/boostvolt/claude-code-lsps): LSP Dart (butuh Dart SDK).

Update: salin ulang folder skill dari repo sumber dan perbarui kolom commit di atas.
