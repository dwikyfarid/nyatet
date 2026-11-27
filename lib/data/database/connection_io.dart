import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Koneksi Android/iOS — perilaku lama, tidak berubah.
QueryExecutor openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'nyatet.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}

/// Untuk uji (tidak dipakai aplikasi di web).
QueryExecutor memoryConnection() => NativeDatabase.memory();
