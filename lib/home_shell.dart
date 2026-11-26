// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/database/app_database.dart';
import 'data/seed/dev_seeder.dart';
import 'ui/providers.dart';
import 'ui/screens/allocation_screen.dart';
import 'ui/screens/cockpit_screen.dart';
import 'ui/screens/goals_screen.dart';
import 'ui/screens/transactions_screen.dart';

/// 4 tujuan navigasi (UX-08) + FAB quick-add (D-18). Beranda = cockpit.
/// Antrean draf dibuka dari kartu "draf menunggu" di beranda, bukan tab,
/// supaya bottom nav tetap 4 tujuan.
class HomeShell extends ConsumerWidget {
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(homeTabProvider).clamp(0, 3);
    final pending = ref.watch(pendingDraftsProvider);
    final pendingCount = pending.maybeWhen(
      data: (list) => list.length,
      orElse: () => 0,
    );

    return Scaffold(
      body: IndexedStack(
        index: index,
        children: const [
          CockpitScreen(),
          TransactionsScreen(),
          AllocationScreen(),
          GoalsScreen(),
        ],
      ),
      floatingActionButton: index == 1
          ? FloatingActionButton.extended(
              onPressed: () => openQuickAdd(context),
              icon: const Icon(Icons.add),
              label: const Text('Catat'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) =>
            ref.read(homeTabProvider.notifier).state = i,
        destinations: [
          NavigationDestination(
            icon: Badge(
              isLabelVisible: pendingCount > 0,
              label: Text('$pendingCount'),
              child: const Icon(Icons.dashboard_outlined),
            ),
            selectedIcon: Badge(
              isLabelVisible: pendingCount > 0,
              label: Text('$pendingCount'),
              child: const Icon(Icons.dashboard),
            ),
            label: 'Beranda',
          ),
          const NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Transaksi',
          ),
          const NavigationDestination(
            icon: Icon(Icons.donut_small_outlined),
            selectedIcon: Icon(Icons.donut_small),
            label: 'Alokasi',
          ),
          const NavigationDestination(
            icon: Icon(Icons.savings_outlined),
            selectedIcon: Icon(Icons.savings),
            label: 'Tujuan',
          ),
        ],
      ),
    );
  }
}

/// Menu pengujian: ganti sesi admin/anggota dan muat 200 transaksi (Q-07).
class DevMenu extends ConsumerWidget {
  const DevMenu({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    return PopupMenuButton<String>(
      tooltip: 'Menu pengujian',
      onSelected: (value) async {
        switch (value) {
          case 'admin':
          case 'member':
            ref.read(sessionProvider.notifier).state = value == MemberRole.admin
                ? const Session(
                    email: 'bapak@example.com',
                    role: MemberRole.admin,
                    name: 'Bapak',
                  )
                : const Session(
                    email: 'anak@example.com',
                    role: MemberRole.member,
                    name: 'Anak',
                  );
            ref.invalidate(visibleTransactionsProvider);
            ref.invalidate(cashSummaryProvider);
            ref.invalidate(goalsProvider);
            ref.invalidate(allocationRowsProvider);
          case 'seed':
            final db = ref.read(databaseProvider);
            final created = await DevSeeder(db).seedTransactions();
            ref.invalidate(visibleTransactionsProvider);
            ref.invalidate(cashSummaryProvider);
            ref.invalidate(unallocatedProvider);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    created == 0
                        ? 'Seed dilewati — database sudah berisi transaksi'
                        : '$created transaksi uji dimuat',
                  ),
                ),
              );
            }
        }
      },
      itemBuilder: (ctx) => [
        PopupMenuItem(
          value: 'admin',
          child: Text('Sesi admin${session.isAdmin ? ' ✓' : ''}'),
        ),
        PopupMenuItem(
          value: 'member',
          child: Text('Sesi anggota${session.isAdmin ? '' : ' ✓'}'),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'seed',
          child: Text('Muat 200 transaksi uji'),
        ),
      ],
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 12),
        child: Icon(Icons.more_vert),
      ),
    );
  }
}
