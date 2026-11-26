import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:workmanager/workmanager.dart';

import 'sync_engine.dart';

/// Nama task periodik WorkManager.
const String backgroundSyncTask = 'nyatet.backgroundSync';

/// Entry point isolat latar belakang (tanpa binding Flutter UI).
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      final engine = await SyncEngine.openDefault();
      await engine.run();
    } catch (_) {
      // Gagal sementara; periodic task berikutnya mencoba lagi.
    }
    return true;
  });
}

/// Daftarkan sinkronisasi periodik tiap 15 menit (WorkManager).
Future<void> registerBackgroundSync() async {
  await Workmanager().initialize(callbackDispatcher);
  await Workmanager().registerPeriodicTask(
    backgroundSyncTask,
    backgroundSyncTask,
    frequency: const Duration(minutes: 15),
  );
}

/// Jalankan sinkronisasi segera saat perangkat kembali daring. Mengembalikan
/// subscription yang harus dipertahankan pemanggil agar tidak di-GC.
StreamSubscription<List<ConnectivityResult>> registerConnectivityTrigger() {
  return Connectivity().onConnectivityChanged.listen((results) async {
    final hasNetwork = results.any((r) => r != ConnectivityResult.none);
    if (!hasNetwork) return;
    try {
      final engine = await SyncEngine.openDefault();
      await engine.run();
    } catch (_) {
      // Abaikan; WorkManager periodik tetap menjadi jaring pengaman.
    }
  });
}
