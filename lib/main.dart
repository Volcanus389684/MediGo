import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'models/medication.dart';
import 'services/esp_connection_service.dart';
import 'services/firebase_service.dart';
import 'services/iot_protocol.dart';
import 'services/prescription_extractor.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FirebaseService.instance.initialize();
  runApp(const MediGoApp());
}

class MediGoApp extends StatefulWidget {
  const MediGoApp({super.key, this.requireAuth = true});

  final bool requireAuth;

  @override
  State<MediGoApp> createState() => _MediGoAppState();
}

class _MediGoAppState extends State<MediGoApp> {
  bool _showOnboarding = true;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MediGo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1EB980),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF5FAF8),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0F172A),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
      ),
      home: widget.requireAuth
          ? const AuthGate()
          : (_showOnboarding
              ? MediGoOnboardingScreen(
                  onComplete: () => setState(() => _showOnboarding = false),
                )
              : const PatientJourneyScreen()),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _showOnboarding = true;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.data == null) return const AccountScreen();
        if (_showOnboarding) {
          return MediGoOnboardingScreen(onComplete: () => setState(() => _showOnboarding = false));
        }
        return RoleGate(user: snapshot.data!);
      },
    );
  }
}

class RoleGate extends StatefulWidget {
  const RoleGate({super.key, required this.user});

  final User user;

  @override
  State<RoleGate> createState() => _RoleGateState();
}

class _RoleGateState extends State<RoleGate> {
  late Future<bool> _operatorFuture;

  @override
  void initState() {
    super.initState();
    _operatorFuture = _loadOperatorRole();
  }

  @override
  void didUpdateWidget(covariant RoleGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user.uid != widget.user.uid) {
      _operatorFuture = _loadOperatorRole();
    }
  }

  Future<bool> _loadOperatorRole() async {
    try {
      await FirebaseService.instance.ensureDatabaseReady();
      final snapshot = await FirebaseService.instance.ref('users/${widget.user.uid}/role').get();
      return snapshot.value?.toString() == 'operator';
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _operatorFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        return snapshot.data! ? const OperatorShell() : const CustomerShell();
      },
    );
  }
}

class OperatorDashboard extends StatelessWidget {
  const OperatorDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F8F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF2F8F5),
        foregroundColor: const Color(0xFF0F172A),
        elevation: 0,
        title: const Text('MediGo  /  Operations', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            onPressed: () => FirebaseAuth.instance.signOut(),
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF0F172A), Color(0xFF164E63)], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(26),
              boxShadow: [BoxShadow(color: const Color(0xFF0F172A).withValues(alpha: 0.13), blurRadius: 18, offset: const Offset(0, 9))],
            ),
            child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Good morning, operator', style: TextStyle(color: Colors.white70, fontSize: 14)),
                const SizedBox(height: 8),
                const Text('Keep every compartment stocked.', style: TextStyle(color: Colors.white, fontSize: 24, height: 1.15, fontWeight: FontWeight.w800)),
                const SizedBox(height: 16),
                Container(padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7), decoration: BoxDecoration(color: const Color(0xFF1EB980).withValues(alpha: 0.2), borderRadius: BorderRadius.circular(99)), child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.verified_rounded, color: Color(0xFF7DE2B8), size: 15), SizedBox(width: 6), Text('Operator access active', style: TextStyle(color: Color(0xFFBDF5DA), fontWeight: FontWeight.w700, fontSize: 12))])),
              ])),
              Container(width: 64, height: 64, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)), child: const Icon(Icons.dashboard_customize_rounded, color: Color(0xFF7DE2B8), size: 32)),
            ]),
          ),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(child: _metricCard('Medicines', 'LIVE', Icons.medication_rounded, const Color(0xFF2563EB))),
            const SizedBox(width: 12),
            Expanded(child: _metricCard('Stock source', 'Firebase', Icons.cloud_done_rounded, const Color(0xFFD97706))),
          ]),
          const SizedBox(height: 26),
          const Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('Stock overview', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))), Text('LIVE', style: TextStyle(color: Color(0xFF1EB980), fontSize: 11, fontWeight: FontWeight.w800))]),
          const SizedBox(height: 11),
          const LiveInventoryList(),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: const Color(0xFFE8F8F1), borderRadius: BorderRadius.circular(19)),
            child: const Row(children: [Icon(Icons.lock_outline_rounded, color: Color(0xFF1EB980), size: 20), SizedBox(width: 10), Expanded(child: Text('Patients submit requests directly. Restock a compartment from Inventory whenever you load medicine into the machine.', style: TextStyle(color: Color(0xFF165B43), fontWeight: FontWeight.w600, fontSize: 12)))]),
          ),
        ],
      ),
    );
  }

  Widget _metricCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.035), blurRadius: 10, offset: const Offset(0, 4))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 36, height: 36, decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(11)), child: Icon(icon, color: color, size: 19)),
        const SizedBox(height: 13),
        Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(color: Colors.black54, fontWeight: FontWeight.w600, fontSize: 12)),
      ]),
    );
  }
}

class LiveInventoryList extends StatelessWidget {
  const LiveInventoryList({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Medication>>(
      stream: FirebaseService.instance.watchMedicines(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()));
        final medicines = snapshot.data!;
        if (medicines.isEmpty) return const Text('No medicines have been added to Firebase yet.', style: TextStyle(color: Colors.black54));
        return Column(children: medicines.map((medicine) => Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(19), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.035), blurRadius: 10, offset: const Offset(0, 4))]),
          child: Row(children: [
            Container(width: 44, height: 44, decoration: BoxDecoration(color: const Color(0xFFEAF3FF), borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.medication_outlined, color: Color(0xFF2563EB))),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(medicine.name, style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF0F172A))), const SizedBox(height: 4), Text('Position ${medicine.position}', style: const TextStyle(color: Colors.black54, fontSize: 12))])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [Text('${medicine.stock} left', style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF0F172A))), const SizedBox(height: 5), Text(medicine.available ? 'Available' : 'Not ready', style: TextStyle(color: medicine.available ? const Color(0xFF1EB980) : const Color(0xFFD97706), fontSize: 11, fontWeight: FontWeight.w700))]),
          ]),
        )).toList());
      },
    );
  }
}

class OperatorShell extends StatefulWidget {
  const OperatorShell({super.key});

  @override
  State<OperatorShell> createState() => _OperatorShellState();
}

class _OperatorShellState extends State<OperatorShell> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      const OperatorDashboard(),
      const OperatorRequestsScreen(),
      const OperatorInventoryScreen(),
      const OperatorSettingsScreen(),
    ];
    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (value) => setState(() => _selectedIndex = value),
        backgroundColor: Colors.white,
        indicatorColor: const Color(0xFFDDF5E9),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard_rounded), label: 'Overview'),
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long_rounded), label: 'Requests'),
          NavigationDestination(icon: Icon(Icons.inventory_2_outlined), selectedIcon: Icon(Icons.inventory_2_rounded), label: 'Inventory'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings_rounded), label: 'Settings'),
        ],
      ),
    );
  }
}

/// Read-only log of every request patients have submitted, with prescription
/// images when available. The operator only observes usage here; approving
/// or rejecting individual medicines is no longer part of the workflow.
class OperatorRequestsScreen extends StatelessWidget {
  const OperatorRequestsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F8F5),
      appBar: AppBar(backgroundColor: const Color(0xFFF2F8F5), foregroundColor: const Color(0xFF0F172A), elevation: 0, title: const Text('Dispensing requests', style: TextStyle(fontWeight: FontWeight.w800))),
      body: StreamBuilder<DatabaseEvent>(
        stream: FirebaseService.instance.watchDispensingRequests(),
        builder: (context, snapshot) {
          final raw = snapshot.data?.snapshot.value;
          final records = <Map<String, dynamic>>[];
          if (raw is Map) {
            raw.forEach((key, value) {
              if (value is Map) records.add({'id': key.toString(), ...Map<String, dynamic>.from(value)});
            });
          }
          records.sort((a, b) => _recordTime(b).compareTo(_recordTime(a)));
          return ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 30), children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF0F172A), Color(0xFF164E63)]), borderRadius: BorderRadius.circular(24)),
              child: const Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Usage log', style: TextStyle(color: Colors.white70)),
                  SizedBox(height: 7),
                  Text('Every request patients have submitted.', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
                ])),
                Icon(Icons.receipt_long_rounded, color: Color(0xFF7DE2B8), size: 40),
              ]),
            ),
            const SizedBox(height: 18),
            if (records.isEmpty)
              const Center(child: Padding(padding: EdgeInsets.only(top: 40), child: Text('No requests submitted yet.', style: TextStyle(color: Colors.black54))))
            else
              ...records.map(_requestCard),
          ]);
        },
      ),
    );
  }

  Widget _requestCard(Map<String, dynamic> record) {
    final medicines = record['medicines'] is List ? (record['medicines'] as List).whereType<Map>().toList() : <Map>[];
    final imageBase64 = record['prescriptionImageBase64']?.toString() ?? '';
    final delivery = record['espDelivery'] is Map ? Map<String, dynamic>.from(record['espDelivery'] as Map) : null;
    final deliverySuccess = delivery?['success'] == true;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(record['patientName']?.toString() ?? 'Patient', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
          Text(IotProtocol.statusDispensed, style: const TextStyle(color: Color(0xFF1EB980), fontWeight: FontWeight.w800, fontSize: 11)),
        ]),
        const SizedBox(height: 8),
        ...medicines.map((medicine) => Padding(
          padding: const EdgeInsets.only(bottom: 5),
          child: Text('${medicine['medicine'] ?? 'Medicine'}  \u2022  position ${medicine['position'] ?? '-'}  \u2022  ${medicine['quantity'] ?? 0} unit(s)', style: const TextStyle(color: Colors.black54, fontSize: 12)),
        )),
        if (delivery != null) ...[
          const SizedBox(height: 6),
          Row(children: [
            Icon(deliverySuccess ? Icons.wifi_rounded : Icons.wifi_off_rounded, size: 15, color: deliverySuccess ? const Color(0xFF1EB980) : const Color(0xFFB91C1C)),
            const SizedBox(width: 6),
            Expanded(child: Text(delivery['message']?.toString() ?? '', style: TextStyle(color: deliverySuccess ? const Color(0xFF1EB980) : const Color(0xFFB91C1C), fontSize: 11, fontWeight: FontWeight.w700))),
          ]),
        ],
        if (imageBase64.isNotEmpty) ...[
          const SizedBox(height: 10),
          ClipRRect(borderRadius: BorderRadius.circular(14), child: Image.memory(base64Decode(imageBase64), height: 140, width: double.infinity, fit: BoxFit.cover)),
        ],
      ]),
    );
  }

  int _recordTime(Map<String, dynamic> record) => int.tryParse((record['createdAt'] ?? '0').toString()) ?? 0;
}

/// Operator sets each dispenser compartment's medicine and stock count
/// manually whenever they physically load or restock the machine.
class OperatorInventoryScreen extends StatelessWidget {
  const OperatorInventoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F8F5),
      appBar: AppBar(backgroundColor: const Color(0xFFF2F8F5), foregroundColor: const Color(0xFF0F172A), elevation: 0, title: const Text('Inventory', style: TextStyle(fontWeight: FontWeight.w800))),
      body: StreamBuilder<List<Medication>>(
        stream: FirebaseService.instance.watchMedicines(),
        builder: (context, snapshot) {
          final medicines = snapshot.data ?? const <Medication>[];
          final byPosition = {for (final medicine in medicines) medicine.position: medicine};
          return ListView(padding: const EdgeInsets.all(20), children: [
            const Text('Medicine inventory', style: TextStyle(fontSize: 27, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
            const SizedBox(height: 8),
            const Text('Tap a compartment to set its medicine and stock count after restocking.', style: TextStyle(color: Colors.black54)),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _clearInventory(context),
                icon: const Icon(Icons.delete_sweep_outlined),
                label: const Text('Clear old inventory'),
              ),
            ),
            const SizedBox(height: 16),
            for (var position = 1; position <= IotProtocol.totalPositions; position++)
              _slotCard(context, position.toString(), byPosition[position.toString()]),
          ]);
        },
      ),
    );
  }

  Widget _slotCard(BuildContext context, String position, Medication? medicine) {
    final hasMedicine = medicine != null;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(19), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.035), blurRadius: 10, offset: const Offset(0, 4))]),
      child: Row(children: [
        Container(width: 44, height: 44, decoration: BoxDecoration(color: const Color(0xFFEAF3FF), borderRadius: BorderRadius.circular(14)), child: Center(child: Text(position, style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF2563EB))))),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(hasMedicine ? medicine.name : 'Empty compartment', style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
          const SizedBox(height: 4),
          Text(hasMedicine ? '${medicine.strength}  \u2022  ${medicine.stock} in stock' : 'Not set up yet', style: const TextStyle(color: Colors.black54, fontSize: 12)),
        ])),
        OutlinedButton(onPressed: () => _editSlot(context, position, medicine), child: Text(hasMedicine ? 'Edit' : 'Set up')),
      ]),
    );
  }

  Future<void> _editSlot(BuildContext context, String position, Medication? medicine) async {
    final saved = await showDialog<bool>(context: context, builder: (_) => InventorySlotDialog(position: position, medicine: medicine));
    if (saved == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Compartment updated.')));
    }
  }

  Future<void> _clearInventory(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear old inventory?'),
        content: const Text('This removes all previously saved medicine slots. You can add the current medicines again afterward.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Clear inventory')),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await FirebaseService.instance.clearMedicineInventory();
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Old inventory cleared.')));
    } catch (error) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Inventory could not be cleared: $error')));
    }
  }
}

class InventorySlotDialog extends StatefulWidget {
  const InventorySlotDialog({super.key, required this.position, this.medicine});

  final String position;
  final Medication? medicine;

  @override
  State<InventorySlotDialog> createState() => _InventorySlotDialogState();
}

class _InventorySlotDialogState extends State<InventorySlotDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _strengthController;
  late final TextEditingController _stockController;
  late bool _requiresPrescription;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.medicine?.name ?? '');
    _strengthController = TextEditingController(text: widget.medicine?.strength ?? '');
    _stockController = TextEditingController(text: (widget.medicine?.stock ?? 0).toString());
    _requiresPrescription = widget.medicine?.requiresPrescription ?? false;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _strengthController.dispose();
    _stockController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final stock = int.tryParse(_stockController.text.trim());
    if (name.isEmpty || stock == null || stock < 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a medicine name and a valid stock count.')));
      return;
    }
    setState(() => _saving = true);
    try {
      await FirebaseService.instance.setMedicineSlot(
        position: widget.position,
        name: name,
        strength: _strengthController.text.trim(),
        stock: stock,
        requiresPrescription: _requiresPrescription,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Medicine could not be saved: $error')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Compartment ${widget.position}'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: _nameController, decoration: const InputDecoration(labelText: 'Medicine name')),
        const SizedBox(height: 10),
        TextField(controller: _strengthController, decoration: const InputDecoration(labelText: 'Strength (e.g. 500mg)')),
        const SizedBox(height: 10),
        TextField(controller: _stockController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Stock count')),
        const SizedBox(height: 10),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Requires prescription'), value: _requiresPrescription, onChanged: _saving ? null : (value) => setState(() => _requiresPrescription = value)),
      ])),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton.icon(onPressed: _saving ? null : _save, icon: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_rounded, size: 18), label: Text(_saving ? 'Saving...' : 'Save')),
      ],
    );
  }
}

class OperatorSettingsScreen extends StatelessWidget {
  const OperatorSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F8F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF2F8F5),
        foregroundColor: const Color(0xFF0F172A),
        elevation: 0,
        title: const Text('Operator settings', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
            child: Row(children: [
              const CircleAvatar(backgroundColor: Color(0xFFDDF5E9), child: Icon(Icons.badge_rounded, color: Color(0xFF1EB980))),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Operator account', style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(FirebaseAuth.instance.currentUser?.email ?? '', style: const TextStyle(color: Colors.black54)),
              ])),
            ]),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(20),
              child: ListTile(
                leading: const Icon(Icons.logout_rounded, color: Color(0xFFB91C1C)),
                title: const Text('Sign out'),
                onTap: () => FirebaseAuth.instance.signOut(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class CustomerShell extends StatefulWidget {
  const CustomerShell({super.key});

  @override
  State<CustomerShell> createState() => _CustomerShellState();
}

class _CustomerShellState extends State<CustomerShell> {
  int _selectedIndex = 0;
  int _homeVersion = 0;

  @override
  Widget build(BuildContext context) {
    final page = switch (_selectedIndex) {
      0 => PatientJourneyScreen(key: ValueKey('home-$_homeVersion'), onRequestFinished: () => setState(() => _homeVersion++)),
      1 => const CustomerHistoryScreen(),
      2 => const CustomerProfileScreen(),
      _ => const CustomerSettingsScreen(),
    };
    return Scaffold(
      body: page,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (value) => setState(() {
          if (value == 0 && _selectedIndex != 0) _homeVersion++;
          _selectedIndex = value;
        }),
        backgroundColor: Colors.white,
        indicatorColor: const Color(0xFFDDF5E9),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long_rounded), label: 'History'),
          NavigationDestination(icon: Icon(Icons.person_outline_rounded), selectedIcon: Icon(Icons.person_rounded), label: 'Profile'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings_rounded), label: 'Settings'),
        ],
      ),
    );
  }
}

class CustomerHistoryScreen extends StatelessWidget {
  const CustomerHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return Scaffold(
      backgroundColor: const Color(0xFFF2F8F5),
      appBar: AppBar(backgroundColor: const Color(0xFFF2F8F5), foregroundColor: const Color(0xFF0F172A), elevation: 0, title: const Text('Your history', style: TextStyle(fontWeight: FontWeight.w800))),
      body: StreamBuilder<DatabaseEvent>(
        stream: FirebaseService.instance.watchDispensingRequests(),
        builder: (context, snapshot) {
          final raw = snapshot.data?.snapshot.value;
          final items = <Map<String, dynamic>>[];
          if (raw is Map) {
            raw.forEach((key, value) {
              if (value is Map && (value['userId']?.toString() == uid || uid.isEmpty)) {
                final rawMedicines = value['medicines'];
                final medicines = rawMedicines is List
                  ? rawMedicines.whereType<Map>().map((medicine) => Map<String, dynamic>.from(medicine)).toList()
                  : <Map<String, dynamic>>[{'medicine': value['medicine']?.toString() ?? 'Medicine', 'quantity': value['quantity'] ?? 1}];
                items.add({'id': key.toString(), 'medicines': medicines, 'createdAt': value['createdAt'] ?? 0, 'espDelivery': value['espDelivery']});
              }
            });
          }
          if (items.isEmpty) return _emptyHistory();
          items.sort((a, b) => _recordTime(b).compareTo(_recordTime(a)));
          return ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 30), children: [
            _historyHeader(items.length),
            const SizedBox(height: 18),
            ...items.map(_historyCard),
          ]);
        },
      ),
    );
  }

  Widget _historyHeader(int count) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF0F172A), Color(0xFF164E63)]),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(children: [
        const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Your care trail', style: TextStyle(color: Colors.white70)),
          SizedBox(height: 7),
          Text('Every request in one place.', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 22)),
        ])),
        Container(width: 52, height: 52, decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(16)), child: const Icon(Icons.timeline_rounded, color: Color(0xFF7DE2B8))),
      ]),
    );
  }

  Widget _historyCard(Map<String, dynamic> item) {
    final delivery = item['espDelivery'] is Map ? Map<String, dynamic>.from(item['espDelivery'] as Map) : null;
    final deliverySuccess = delivery?['success'] == true;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
        Container(width: 44, height: 44, decoration: BoxDecoration(color: const Color(0xFF1EB980).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.check_rounded, color: Color(0xFF1EB980))),
        const SizedBox(width: 12),
        const Expanded(child: Text('Dispensed', style: TextStyle(color: Color(0xFF1EB980), fontWeight: FontWeight.w800, fontSize: 12))),
        const Icon(Icons.chevron_right_rounded, color: Colors.black26),
        ]),
        const SizedBox(height: 12),
        ...((item['medicines'] as List<dynamic>? ?? const []).map((medicine) {
          final medicineMap = medicine is Map ? medicine : <String, dynamic>{};
          final name = medicineMap['medicine']?.toString() ?? 'Medicine';
          final quantity = medicineMap['quantity']?.toString() ?? '1';
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              const Icon(Icons.medication_outlined, size: 18, color: Color(0xFF1EB980)),
              const SizedBox(width: 8),
              Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w700))),
              Text('$quantity unit(s)', style: const TextStyle(color: Colors.black54, fontSize: 11)),
            ]),
          );
        })),
        if (delivery != null) ...[
          const SizedBox(height: 8),
          Row(children: [
            Icon(deliverySuccess ? Icons.wifi_rounded : Icons.wifi_off_rounded, size: 15, color: deliverySuccess ? const Color(0xFF1EB980) : const Color(0xFFB91C1C)),
            const SizedBox(width: 6),
            Expanded(child: Text(delivery['message']?.toString() ?? '', style: TextStyle(color: deliverySuccess ? const Color(0xFF1EB980) : const Color(0xFFB91C1C), fontSize: 11, fontWeight: FontWeight.w700))),
          ]),
        ],
      ]),
    );
  }

  int _recordTime(Map<String, dynamic> item) => int.tryParse(item['createdAt']?.toString() ?? '0') ?? 0;

  Widget _emptyHistory() => Center(
        child: Padding(
          padding: const EdgeInsets.all(36),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(width: 76, height: 76, decoration: const BoxDecoration(color: Color(0xFFDDF5E9), shape: BoxShape.circle), child: const Icon(Icons.receipt_long_rounded, size: 34, color: Color(0xFF1EB980))),
            const SizedBox(height: 18),
            const Text('No requests yet', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            const Text('Your dispensing requests and approval status will appear here.', textAlign: TextAlign.center, style: TextStyle(color: Colors.black54)),
          ]),
        ),
      );
}

class CustomerProfileScreen extends StatefulWidget {
  const CustomerProfileScreen({super.key});

  @override
  State<CustomerProfileScreen> createState() => _CustomerProfileScreenState();
}

class _CustomerProfileScreenState extends State<CustomerProfileScreen> {
  Future<Map<String, dynamic>>? _profileFuture;

  @override
  void initState() {
    super.initState();
    _profileFuture = FirebaseService.instance.getCurrentUserProfile();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      backgroundColor: const Color(0xFFF2F8F5),
      appBar: AppBar(backgroundColor: const Color(0xFFF2F8F5), foregroundColor: const Color(0xFF0F172A), elevation: 0, title: const Text('Your profile', style: TextStyle(fontWeight: FontWeight.w800))),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _profileFuture,
        builder: (context, snapshot) {
          final data = snapshot.data ?? <String, dynamic>{};
          final name = data['fullName']?.toString() ?? 'MediGo customer';
          return ListView(padding: const EdgeInsets.all(20), children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF0F172A), Color(0xFF164E63)]), borderRadius: BorderRadius.circular(26)),
              child: Row(children: [
                const CircleAvatar(radius: 30, backgroundColor: Color(0x337DE2B8), child: Icon(Icons.person_rounded, color: Color(0xFF7DE2B8), size: 32)),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(user?.email ?? '', style: const TextStyle(color: Colors.white70)),
                ])),
              ]),
            ),
            const SizedBox(height: 18),
            _profileTile(Icons.person_outline_rounded, 'Full name', name),
            _profileTile(Icons.email_outlined, 'Email', user?.email ?? '-'),
            _profileTile(Icons.badge_outlined, 'Account type', 'Customer'),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => EditProfileScreen(initialData: data))).then((saved) {
                if (saved == true && mounted) {
                  setState(() => _profileFuture = FirebaseService.instance.getCurrentUserProfile());
                }
              }),
              icon: const Icon(Icons.edit_rounded),
              label: const Text('Edit profile'),
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1EB980), padding: const EdgeInsets.symmetric(vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
            ),
          ]);
        },
      ),
    );
  }

  Widget _profileTile(IconData icon, String label, String value) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
        child: Row(children: [
          Icon(icon, color: const Color(0xFF1EB980)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(color: Colors.black54, fontSize: 12)),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
          ])),
        ]),
      );
}

class CustomerSettingsScreen extends StatelessWidget {
  const CustomerSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F8F5),
      appBar: AppBar(backgroundColor: const Color(0xFFF2F8F5), foregroundColor: const Color(0xFF0F172A), elevation: 0, title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.w800))),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
          child: const Row(children: [
            Icon(Icons.shield_outlined, color: Color(0xFF1EB980), size: 28),
            SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('MediGo account', style: TextStyle(fontWeight: FontWeight.w800)),
              SizedBox(height: 4),
              Text('Your account keeps your requests and history together.', style: TextStyle(color: Colors.black54, fontSize: 12)),
            ])),
          ]),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            child: Column(children: [
              ListTile(leading: const Icon(Icons.help_outline_rounded), title: const Text('Help and support'), trailing: const Icon(Icons.chevron_right_rounded, color: Colors.black26), onTap: () {}),
              const Divider(height: 1),
              ListTile(leading: const Icon(Icons.logout_rounded, color: Color(0xFFB91C1C)), title: const Text('Sign out'), onTap: () => FirebaseAuth.instance.signOut()),
            ]),
          ),
        ),
      ]),
    );
  }
}

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key, required this.initialData});

  final Map initialData;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _ageController;
  late final TextEditingController _weightController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialData['fullName']?.toString() ?? '');
    _ageController = TextEditingController(text: widget.initialData['age']?.toString() ?? '');
    _weightController = TextEditingController(text: widget.initialData['weight']?.toString() ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ageController.dispose();
    _weightController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter your full name.')));
      return;
    }
    setState(() => _saving = true);
    try {
      await FirebaseService.instance.updateCurrentUserProfile(
        fullName: _nameController.text.trim(),
        age: int.tryParse(_ageController.text) ?? 0,
        weight: double.tryParse(_weightController.text) ?? 0,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Profile could not be saved: $error')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F8F5),
      appBar: AppBar(backgroundColor: const Color(0xFFF2F8F5), foregroundColor: const Color(0xFF0F172A), elevation: 0, title: const Text('Edit profile', style: TextStyle(fontWeight: FontWeight.w800))),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        const Text('Keep your patient details up to date.', style: TextStyle(color: Colors.black54, fontSize: 16)),
        const SizedBox(height: 20),
        TextField(controller: _nameController, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Full name', prefixIcon: Icon(Icons.person_outline_rounded), filled: true, fillColor: Colors.white)),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: TextField(controller: _ageController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Age', prefixIcon: Icon(Icons.calendar_today_outlined), filled: true, fillColor: Colors.white))),
          const SizedBox(width: 12),
          Expanded(child: TextField(controller: _weightController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Weight (kg)', prefixIcon: Icon(Icons.monitor_weight_outlined), filled: true, fillColor: Colors.white))),
        ]),
        const SizedBox(height: 24),
        FilledButton.icon(onPressed: _saving ? null : _save, icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_rounded), label: Text(_saving ? 'Saving...' : 'Save changes'), style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1EB980), padding: const EdgeInsets.symmetric(vertical: 16))),
      ]),
    );
  }
}

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final _nameController = TextEditingController();
  final _ageController = TextEditingController();
  final _weightController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isRegistering = false;
  bool _isBusy = false;
  @override
  void dispose() {
    _nameController.dispose();
    _ageController.dispose();
    _weightController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_emailController.text.trim().isEmpty || _passwordController.text.length < 6) {
      _showMessage('Enter an email and a password with at least 6 characters.');
      return;
    }
    if (_isRegistering && _nameController.text.trim().isEmpty) {
      _showMessage('Enter your full name to create your profile.');
      return;
    }
    if (_isRegistering && (_ageController.text.trim().isEmpty || _weightController.text.trim().isEmpty)) {
      _showMessage('Enter your age and weight to complete your profile.');
      return;
    }
    setState(() => _isBusy = true);
    try {
      final auth = FirebaseAuth.instance;
      UserCredential result;
      if (_isRegistering) {
        result = await auth.createUserWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
        final user = result.user;
        if (user == null) throw StateError('Firebase account was not created.');
        await FirebaseService.instance.createCustomerProfile(
          fullName: _nameController.text.trim(),
          age: int.tryParse(_ageController.text.trim()) ?? 0,
          weight: double.tryParse(_weightController.text.trim()) ?? 0,
        );
      } else {
        await auth.signInWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
      }
    } on FirebaseAuthException catch (error) {
      _showMessage(error.message ?? 'Account access failed.');
    } catch (error) {
      _showMessage('Account profile could not be saved: $error');
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SizedBox(height: 18),
            Container(
              height: 190,
              width: double.infinity,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(28), color: const Color(0xFF0F172A)),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    'https://images.unsplash.com/photo-1585435557343-3b092031a831?auto=format&fit=crop&w=1200&q=85',
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => const ColoredBox(color: Color(0xFF164E63)),
                  ),
                  DecoratedBox(decoration: BoxDecoration(color: const Color(0xFF0F172A).withValues(alpha: 0.58))),
                  Padding(padding: const EdgeInsets.all(22), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.end, children: [const Text('MediGo', style: TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w800)), const SizedBox(height: 4), Text(_isRegistering ? 'Start your safer care journey' : 'Smart medicine dispensing', style: const TextStyle(color: Colors.white70, fontSize: 14))])),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const SizedBox(height: 18),
            Text(_isRegistering ? 'Create your account' : 'Welcome back', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, color: const Color(0xFF0F172A))),
            const SizedBox(height: 8),
            const Text('Sign in to request medicine and follow the dispenser status.', style: TextStyle(color: Colors.black54, fontSize: 16)),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(child: _loginFeature(Icons.medication_rounded, 'Medicine\nready', const Color(0xFF1EB980))),
                const SizedBox(width: 10),
                Expanded(child: _loginFeature(Icons.verified_user_rounded, 'Secure\nprofile', const Color(0xFF2563EB))),
                const SizedBox(width: 10),
                Expanded(child: _loginFeature(Icons.sync_rounded, 'Live\ntracking', const Color(0xFFD97706))),
              ],
            ),
            const SizedBox(height: 32),
            if (_isRegistering) ...[
              TextField(controller: _nameController, textCapitalization: TextCapitalization.words, decoration: InputDecoration(labelText: 'Full name', prefixIcon: const Icon(Icons.person_outline_rounded), filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none))),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: TextField(controller: _ageController, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Age', prefixIcon: const Icon(Icons.calendar_today_outlined), filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none)))),
                const SizedBox(width: 12),
                Expanded(child: TextField(controller: _weightController, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Weight (kg)', prefixIcon: const Icon(Icons.monitor_weight_outlined), filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none)))),
              ]),
              const SizedBox(height: 14),
            ],
            TextField(controller: _emailController, keyboardType: TextInputType.emailAddress, decoration: InputDecoration(labelText: 'Email', prefixIcon: const Icon(Icons.email_outlined), filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none))),
            const SizedBox(height: 14),
            TextField(controller: _passwordController, obscureText: true, decoration: InputDecoration(labelText: 'Password', prefixIcon: const Icon(Icons.lock_outline_rounded), filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none))),
            if (_isRegistering)
              const Padding(
                padding: EdgeInsets.only(top: 18),
                child: Text('New accounts are customer accounts. A pharmacist creates operator access separately.', style: TextStyle(color: Colors.black54, fontSize: 12)),
              ),
            const SizedBox(height: 26),
            SizedBox(width: double.infinity, child: FilledButton(onPressed: _isBusy ? null : _submit, style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1EB980), padding: const EdgeInsets.symmetric(vertical: 17), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))), child: Text(_isBusy ? 'Please wait...' : (_isRegistering ? 'Create account' : 'Sign in')))),
            const SizedBox(height: 12),
            Center(child: TextButton(onPressed: () => setState(() => _isRegistering = !_isRegistering), child: Text(_isRegistering ? 'Already have an account? Sign in' : 'New to MediGo? Create an account'))),
          ]),
        ),
      ),
    );
  }

  Widget _loginFeature(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: color.withValues(alpha: 0.14)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.035), blurRadius: 12, offset: const Offset(0, 5))],
      ),
      child: Column(
        children: [
          Container(width: 34, height: 34, decoration: BoxDecoration(color: color.withValues(alpha: 0.11), shape: BoxShape.circle), child: Icon(icon, color: color, size: 18)),
          const SizedBox(height: 8),
          Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, height: 1.1, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
        ],
      ),
    );
  }
}

class MediGoOnboardingScreen extends StatefulWidget {
  const MediGoOnboardingScreen({super.key, required this.onComplete});

  final VoidCallback onComplete;

  @override
  State<MediGoOnboardingScreen> createState() => _MediGoOnboardingScreenState();
}

class _MediGoOnboardingScreenState extends State<MediGoOnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<_OnboardingData> _slides = const [
    _OnboardingData(
      title: 'Safer dispensing',
      subtitle: 'Confirm patient details and medication selection before every release.',
      accent: Color(0xFF1EB980),
      icon: Icons.shield_rounded,
    ),
    _OnboardingData(
      title: 'Prescription ready',
      subtitle: 'Upload a prescription photo and keep a digital trail for each request.',
      accent: Color(0xFF2563EB),
      icon: Icons.upload_file_rounded,
    ),
    _OnboardingData(
      title: 'ESP32 status live',
      subtitle: 'Track the device handoff and wait for completion confirmation from Firebase.',
      accent: Color(0xFF0F172A),
      icon: Icons.monitor_heart_rounded,
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLastPage = _currentPage == _slides.length - 1;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'MediGo',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF0F172A),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  onPageChanged: (value) => setState(() => _currentPage = value),
                  itemCount: _slides.length,
                  itemBuilder: (context, index) {
                    final slide = _slides[index];
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutCubic,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            slide.accent.withValues(alpha: 0.18),
                            Colors.white,
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                        borderRadius: BorderRadius.circular(32),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          AnimatedScale(
                            scale: 1 + (_currentPage == index ? 0.08 : 0),
                            duration: const Duration(milliseconds: 300),
                            child: Container(
                              width: 132,
                              height: 132,
                              decoration: BoxDecoration(
                                color: slide.accent,
                                borderRadius: BorderRadius.circular(36),
                                boxShadow: [
                                  BoxShadow(
                                    color: slide.accent.withValues(alpha: 0.25),
                                    blurRadius: 25,
                                    offset: const Offset(0, 12),
                                  ),
                                ],
                              ),
                              child: Icon(slide.icon, size: 62, color: Colors.white),
                            ),
                          ),
                          const SizedBox(height: 28),
                          Text(
                            slide.title,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            slide.subtitle,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  _slides.length,
                  (index) => AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    width: _currentPage == index ? 28 : 8,
                    height: 8,
                    margin: const EdgeInsets.symmetric(horizontal: 5),
                    decoration: BoxDecoration(
                      color: _currentPage == index
                          ? const Color(0xFF1EB980)
                          : const Color(0xFFCDEDE0),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: widget.onComplete,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        side: const BorderSide(color: Color(0xFF1EB980)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text('Skip'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        if (isLastPage) {
                          widget.onComplete();
                          return;
                        }
                        _pageController.nextPage(
                          duration: const Duration(milliseconds: 260),
                          curve: Curves.easeOutCubic,
                        );
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF1EB980),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Text(isLastPage ? 'Get started' : 'Next'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OnboardingData {
  const _OnboardingData({
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final Color accent;
  final IconData icon;
}

class _MediGoScrollBehavior extends MaterialScrollBehavior {
  const _MediGoScrollBehavior();

  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) {
    return child;
  }
}

class PatientJourneyScreen extends StatefulWidget {
  const PatientJourneyScreen({super.key, this.onRequestFinished});

  final VoidCallback? onRequestFinished;

  @override
  State<PatientJourneyScreen> createState() => _PatientJourneyScreenState();
}

class _PatientJourneyScreenState extends State<PatientJourneyScreen> {
  final PageController _pageController = PageController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _ageController = TextEditingController();
  final TextEditingController _weightController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();

  List<Medication> _medications = [];

  int _step = 0;
  bool _hasPrescription = false;
  bool _isPrescriptionCorrection = false;
  bool _isUploading = false;
  bool _isSubmitting = false;
  String? _uploadMessage;
  File? _prescriptionFile;
  Uint8List? _prescriptionBytes;
  String? _prescriptionUrl;
  String? _prescriptionImageBase64;
  List<ExtractedPrescriptionItem> _extractedItems = const [];
  String _extractionMessage = 'Printed medicine extraction is ready for Android.';
  final Map<String, Medication> _selectedMedicines = <String, Medication>{};
  final Map<String, int> _quantities = <String, int>{};
  late final StreamSubscription<List<Medication>> _medicineSubscription;
  late final StreamSubscription<String?> _espSubscription;
  String? _espAddress;

  @override
  void initState() {
    super.initState();
    _loadProfileAndMedicines();
    _medicineSubscription = FirebaseService.instance.watchMedicines().listen((medicines) {
      if (mounted) setState(() => _medications = medicines);
    });
    _espSubscription = FirebaseService.instance.watchPairedEspAddress().listen((address) {
      if (mounted) setState(() => _espAddress = address);
    });
  }

  Future<void> _loadProfileAndMedicines() async {
    final profile = await FirebaseService.instance.getCurrentUserProfile();
    final medicines = await FirebaseService.instance.getMedicines();
    if (!mounted) return;
    setState(() {
      _nameController.text = profile['fullName']?.toString() ?? '';
      _ageController.text = profile['age']?.toString() ?? '';
      _weightController.text = profile['weight']?.toString() ?? '';
      _medications = medicines;
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _nameController.dispose();
    _ageController.dispose();
    _weightController.dispose();
    _medicineSubscription.cancel();
    _espSubscription.cancel();
    super.dispose();
  }

  void _next() {
    if (_step == 0 && _nameController.text.trim().isEmpty) {
      _showJourneyMessage('Please enter the patient name.');
      return;
    }
    if (_step == 1 && _hasPrescription && _prescriptionFile == null) {
      _showJourneyMessage('Upload the prescription before continuing.');
      return;
    }
    if (_step == 2 && _hasPrescription) {
      _applyExtractedMedicines();
      if (_selectedMedicines.isEmpty) {
        _showJourneyMessage('No medicine was extracted. Choose the manual review option below.');
        return;
      }
      setState(() => _step = 4);
      _pageController.animateToPage(_step, duration: const Duration(milliseconds: 240), curve: Curves.easeOutCubic);
      return;
    }
    if (_step == 3 && _selectedMedicines.isEmpty) {
      _showJourneyMessage('Select at least one available medicine to continue.');
      return;
    }
    if (_step == 1 && _hasPrescription) {
      setState(() => _step = 2);
      _pageController.animateToPage(_step, duration: const Duration(milliseconds: 240), curve: Curves.easeOutCubic);
      return;
    }
    if (_step == 1 && !_hasPrescription) {
      setState(() => _step = 3);
      _pageController.animateToPage(_step, duration: const Duration(milliseconds: 240), curve: Curves.easeOutCubic);
      return;
    }
    if (_step < 5) {
      setState(() => _step++);
      _pageController.animateToPage(_step, duration: const Duration(milliseconds: 240), curve: Curves.easeOutCubic);
    } else {
      _submitRequest();
    }
  }

  void _applyExtractedMedicines() {
    for (final item in _extractedItems) {
      final match = _medications.where((medicine) => medicine.name == item.matchedMedicine).toList();
      if (match.isNotEmpty) {
        _selectedMedicines[match.first.name] = match.first;
        _quantities[match.first.name] = item.quantity ?? _quantities[match.first.name] ?? 1;
      }
    }
  }

  void resetJourney() {
    setState(() {
      _step = 0;
      _hasPrescription = false;
      _isPrescriptionCorrection = false;
      _prescriptionFile = null;
      _prescriptionBytes = null;
      _prescriptionUrl = null;
      _prescriptionImageBase64 = null;
      _extractedItems = const [];
      _selectedMedicines.clear();
      _quantities.clear();
    });
    _pageController.jumpToPage(0);
  }

  void _back() {
    if (_step == 0) return;
    if (_step == 3 && !_hasPrescription) {
      setState(() => _step = 1);
      _pageController.animateToPage(_step, duration: const Duration(milliseconds: 240), curve: Curves.easeOutCubic);
      return;
    }
    setState(() => _step--);
    _pageController.animateToPage(_step, duration: const Duration(milliseconds: 240), curve: Curves.easeOutCubic);
  }

  Future<void> _choosePrescription() async {
    final selected = await _imagePicker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (selected == null) return;
    setState(() {
      _prescriptionFile = File(selected.path);
      _prescriptionBytes = null;
      _prescriptionImageBase64 = null;
      _isUploading = true;
      _uploadMessage = 'Reading prescription image...';
    });

    try {
      _prescriptionBytes = await selected.readAsBytes();
      _prescriptionImageBase64 = base64Encode(_prescriptionBytes!);
      if (mounted) {
        setState(() {});
      }
    } catch (_) {
      // Native platforms can continue using the local file path.
    }

    if (!kIsWeb && _medications.isNotEmpty) {
      try {
        final extracted = await PrescriptionExtractor.extractPrintedMedicineLines(
          imagePath: selected.path,
          knownMedicineNames: _medications.map((medicine) => medicine.name).toList(),
        );
        if (mounted) {
          setState(() {
            _extractedItems = extracted;
            _extractionMessage = extracted.isEmpty
                ? 'No known medicine name was detected. The operator must review the document.'
                : '${extracted.length} medicine candidate(s) detected. Please review before submitting.';
            _uploadMessage = 'Prescription image ready. Continue to review the extracted medicines.';
          });
        }
      } catch (_) {
        if (mounted) {
          setState(() {
            _extractionMessage = 'Extraction could not read this image. The operator must review it.';
            _uploadMessage = 'Image ready for operator review.';
          });
        }
      }
    } else if (mounted) {
      setState(() {
        _extractionMessage = 'Chrome preview is ready. Printed extraction runs on Android; the operator will verify this image.';
        _uploadMessage = 'Prescription image ready. Continue to review the summary.';
      });
    }

    final patientId = _nameController.text.trim().replaceAll(RegExp(r'\s+'), '_').toLowerCase();
    try {
      _prescriptionUrl = await FirebaseService.instance.uploadPrescriptionImage(
        patientId: patientId,
        imageFile: _prescriptionFile!,
      );
      await FirebaseService.instance.savePrescriptionRecord(
        patientId: patientId,
        imageUrl: _prescriptionUrl!,
        medicine: 'Pending analysis',
        status: 'UPLOADED',
        imageBase64: _prescriptionImageBase64,
      );
    } catch (_) {
      await FirebaseService.instance.savePrescriptionRecord(
        patientId: patientId,
        imageUrl: '',
        medicine: 'Pending analysis',
        status: 'LOCAL_ONLY',
        imageBase64: _prescriptionImageBase64,
      );
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _submitRequest() async {
    if (_isSubmitting || _selectedMedicines.isEmpty) return;
    setState(() => _isSubmitting = true);
    final medicines = _selectedMedicines.values.toList();
    final primaryMedicine = medicines.first;
    final patient = PatientData(
      name: _nameController.text.trim(),
      age: int.tryParse(_ageController.text) ?? 0,
      weight: double.tryParse(_weightController.text) ?? 0,
      hasPrescription: _hasPrescription,
    );
    try {
      final submission = await FirebaseService.instance.submitDispenseRequest(
        patientId: patient.name.replaceAll(RegExp(r'\s+'), '_').toLowerCase(),
        patientName: patient.name,
        hasPrescription: _hasPrescription,
        prescriptionUrl: _prescriptionUrl,
        prescriptionImageBase64: _prescriptionImageBase64,
        items: medicines.map((item) => <String, dynamic>{
          'medicine': item.name,
          'strength': item.strength,
          'position': item.position,
          'quantity': _quantities[item.name] ?? 1,
          'requiresPrescription': item.requiresPrescription,
        }).toList(),
      );
      final espAddress = _espAddress;
      EspConnectionResult delivery;
      if (espAddress == null || espAddress.isEmpty) {
        delivery = const EspConnectionResult(success: false, message: 'No dispenser paired yet. Scan the QR code on the bus first.');
      } else {
        delivery = await EspConnectionService.instance.sendCommand(address: espAddress, command: submission.command);
      }
      await FirebaseService.instance.updateDispenseDelivery(
        requestId: submission.requestId,
        success: delivery.success,
        message: delivery.message,
        address: espAddress ?? '',
      );
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => DispensingStatusScreen(
          patient: patient,
          medicine: primaryMedicine,
          quantity: _quantities[primaryMedicine.name] ?? 1,
          items: medicines.map((item) => <String, dynamic>{
            'medicine': item.name,
            'strength': item.strength,
            'position': item.position,
            'quantity': _quantities[item.name] ?? 1,
          }).toList(),
          requestId: submission.requestId,
          command: submission.command,
          espAddress: espAddress,
          initialDelivery: delivery,
          onStartNewRequest: widget.onRequestFinished,
        ),
      ));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('The request could not be sent: $error')));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showJourneyMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final titles = ['Patient details', 'Prescription', 'Summary', 'Medicine', 'Quantity', 'Confirm request'];
    return Scaffold(
      backgroundColor: const Color(0xFFF2F8F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF2F8F5),
        foregroundColor: const Color(0xFF0F172A),
        elevation: 0,
        leading: _step == 0 ? null : IconButton(onPressed: _back, icon: const Icon(Icons.arrow_back_rounded)),
        titleSpacing: _step == 0 ? 24 : 0,
        title: Row(
          children: [
            const Text('MediGo', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.2)),
            const SizedBox(width: 10),
            Container(width: 5, height: 5, decoration: const BoxDecoration(color: Color(0xFF1EB980), shape: BoxShape.circle)),
            const SizedBox(width: 10),
            Flexible(child: Text(titles[_step], style: const TextStyle(fontSize: 14, color: Colors.black54, fontWeight: FontWeight.w600))),
          ],
        ),
        actions: [
          IconButton(
            tooltip: _espAddress == null ? 'Connect to dispenser' : 'Dispenser: $_espAddress',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EspPairingScreen())),
            icon: Icon(_espAddress == null ? Icons.qr_code_scanner_rounded : Icons.wifi_rounded, color: _espAddress == null ? const Color(0xFF0F172A) : const Color(0xFF1EB980)),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 18),
            child: Center(
              child: Text('${_step + 1}/6', style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF1EB980))),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 2, 24, 0),
              child: Row(
                children: List.generate(
                  titles.length,
                  (index) => Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 240),
                      height: 5,
                      margin: EdgeInsets.only(right: index == titles.length - 1 ? 0 : 5),
                      decoration: BoxDecoration(
                        color: index <= _step ? const Color(0xFF1EB980) : const Color(0xFFD6E9E0),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _detailsPage(),
                  _prescriptionPage(),
                  _prescriptionSummaryPage(),
                  _medicinePage(),
                  _quantityPage(),
                  _confirmationPage(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pageBody(List<Widget> children) => ScrollConfiguration(
        behavior: const _MediGoScrollBehavior(),
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 36),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
        ),
      );

  Widget _detailsPage() => _pageBody([
        _hero("Let's get started", 'Tell us who the medicine is for.'),
        Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: const Color(0xFFE8F8F1), borderRadius: BorderRadius.circular(16)),
          child: const Row(children: [Icon(Icons.verified_user_rounded, color: Color(0xFF1EB980), size: 20), SizedBox(width: 10), Expanded(child: Text('Using your saved profile details. Update them from Profile.', style: TextStyle(color: Color(0xFF165B43), fontSize: 12, fontWeight: FontWeight.w600)))]),
        ),
        _field('Full name', _nameController, Icons.person_outline_rounded, readOnly: true),
        _field('Age', _ageController, Icons.calendar_today_outlined, numeric: true, readOnly: true),
        _field('Weight (kg)', _weightController, Icons.monitor_weight_outlined, numeric: true, readOnly: true),
        _continueButton('Next'),
      ]);

  Widget _prescriptionPage() => _pageBody([
        _hero('Prescription check', 'A prescription helps us prepare the correct medicine.'),
        _choice('I have a prescription', _hasPrescription, () => setState(() {
          _hasPrescription = true;
          _isPrescriptionCorrection = false;
        })),
        _choice('Continue without prescription', !_hasPrescription, () => setState(() {
          _hasPrescription = false;
          _isPrescriptionCorrection = false;
        })),
        if (_hasPrescription) ...[
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _isUploading ? null : _choosePrescription,
              icon: _isUploading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.photo_camera_back_rounded),
              label: Text(_isUploading ? 'Preparing preview...' : 'Choose prescription image'),
            ),
          ),
          if (_prescriptionFile != null) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: _prescriptionBytes != null
                  ? Image.memory(_prescriptionBytes!, height: 190, width: double.infinity, fit: BoxFit.cover)
                  : Container(height: 190, width: double.infinity, color: const Color(0xFFE8F8F1), child: const Center(child: Icon(Icons.image_rounded, color: Color(0xFF1EB980), size: 48))),
            ),
            const SizedBox(height: 8),
            const Text('Image selected for operator review.', style: TextStyle(color: Colors.black54)),
            if (_uploadMessage != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_uploadMessage!, style: const TextStyle(color: Color(0xFF1EB980), fontWeight: FontWeight.w700, fontSize: 12))),
          ],
        ],
        _continueButton('Continue'),
      ]);

  Widget _prescriptionSummaryPage() => _pageBody([
        _hero('Prescription summary', 'Check the document and your saved patient details before medicine review.'),
        _infoCard('Patient', _nameController.text),
        _infoCard('Age', _ageController.text),
        _infoCard('Weight', '${_weightController.text} kg'),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(17),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
          child: Row(children: [
            const Icon(Icons.image_rounded, color: Color(0xFF2563EB)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Document received', style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              const Text('Prescription image', style: TextStyle(color: Colors.black54)),
            ])),
            const Icon(Icons.check_circle_rounded, color: Color(0xFF1EB980)),
          ]),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Extracted medicine candidates', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            if (_extractedItems.isEmpty)
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_extractionMessage, style: const TextStyle(color: Colors.black54, fontSize: 12)),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () {
                    setState(() => _step = 3);
                    _pageController.animateToPage(3, duration: const Duration(milliseconds: 240), curve: Curves.easeOutCubic);
                  },
                  icon: const Icon(Icons.fact_check_rounded),
                  label: const Text('Review medicines manually'),
                ),
              ])
            else
              ..._extractedItems.map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(children: [
                  const Icon(Icons.check_circle_rounded, color: Color(0xFF1EB980), size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(item.medicine, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                    Text('${item.strength ?? 'Strength to verify'}  \u2022  ${item.quantity == null ? 'Quantity to verify' : 'Quantity: ${item.quantity}'}', style: const TextStyle(color: Colors.black54, fontSize: 12)),
                  ])),
                  Text('${(item.confidence * 100).round()}%', style: const TextStyle(color: Color(0xFF1EB980), fontWeight: FontWeight.w800, fontSize: 11)),
                ]),
              )),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () {
                _applyExtractedMedicines();
                setState(() {
                  _isPrescriptionCorrection = true;
                  _step = 3;
                });
                _pageController.animateToPage(3, duration: const Duration(milliseconds: 240), curve: Curves.easeOutCubic);
              },
              icon: const Icon(Icons.add_circle_outline_rounded),
              label: const Text('Add or correct medicines manually'),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: const Color(0xFFFFF4DE), borderRadius: BorderRadius.circular(16)), child: const Row(children: [Icon(Icons.info_outline_rounded, color: Color(0xFFD97706)), SizedBox(width: 9), Expanded(child: Text('The operator will verify the medicine, dose, signature, and seal before approval.', style: TextStyle(color: Color(0xFF92400E), fontSize: 12, fontWeight: FontWeight.w600)))])),
        _continueButton('Review prescription medicines'),
      ]);

  Widget _medicinePage() {
    final visibleMedicines = _medications.where((medicine) => medicine.stock > 0 && (_hasPrescription || !medicine.requiresPrescription)).toList();
    return _pageBody([
        _hero(
          _isPrescriptionCorrection ? 'Add or correct medicines' : 'Choose your medicine',
          _isPrescriptionCorrection
              ? 'Your extracted medicines are already selected. Add missing medicines or adjust the list.'
              : 'Select an available medicine from the dispenser.',
        ),
        if (_isPrescriptionCorrection)
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: const Color(0xFFE8F8F1), borderRadius: BorderRadius.circular(16)),
            child: const Row(children: [
              Icon(Icons.fact_check_rounded, color: Color(0xFF1EB980)),
              SizedBox(width: 9),
              Expanded(child: Text('Checked medicines remain selected. You can add a missed medicine before submitting.', style: TextStyle(color: Color(0xFF165B43), fontWeight: FontWeight.w600, fontSize: 12))),
            ]),
          )
        else if (!_hasPrescription)
          Container(margin: const EdgeInsets.only(bottom: 14), padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: const Color(0xFFFFF4DE), borderRadius: BorderRadius.circular(16)), child: const Row(children: [Icon(Icons.info_outline_rounded, color: Color(0xFFD97706)), SizedBox(width: 9), Expanded(child: Text('Only over-the-counter medicines are shown without a prescription.', style: TextStyle(color: Color(0xFF92400E), fontWeight: FontWeight.w600, fontSize: 12)))])),
        if (visibleMedicines.isEmpty)
          Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)), child: const Text('No medicines are currently in stock. Please check back later.', style: TextStyle(color: Colors.black54))),
        ...visibleMedicines.map((medicine) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _choice('${medicine.name}  \u2022  ${medicine.strength}', _selectedMedicines.containsKey(medicine.name), () {
                setState(() {
                  if (_selectedMedicines.containsKey(medicine.name)) {
                    _selectedMedicines.remove(medicine.name);
                  } else {
                    _selectedMedicines[medicine.name] = medicine;
                    _quantities.putIfAbsent(medicine.name, () => 1);
                  }
                });
              }, detail: 'Position ${medicine.position}  \u2022  ${medicine.stock} available'),
            )),
        _continueButton('Continue'),
        ]);
      }

  Widget _quantityPage() => _pageBody([
        _hero('Set quantities', 'Adjust each medicine before reviewing the request.'),
        _infoCard('Patient weight', '${_weightController.text} kg'),
        const SizedBox(height: 12),
        ..._selectedMedicines.values.map((medicine) => _quantityEditor(medicine)),
        _continueButton('Review request'),
      ]);

  Widget _confirmationPage() => _pageBody([
        _hero('Ready to dispense?', 'Check the request before sending it to the machine.'),
        _infoCard('Patient', _nameController.text),
        ..._selectedMedicines.values.map((medicine) => _infoCard(
              medicine.name,
              '${_quantities[medicine.name] ?? 1} unit(s)  \u2022  ${medicine.position}',
            )),
        const SizedBox(height: 20),
        _continueButton('Confirm dispensing'),
      ]);

  Widget _quantityEditor(Medication medicine) {
    final quantity = _quantities[medicine.name] ?? 1;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(medicine.name, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('${medicine.strength}  \u2022  ${medicine.position}', style: const TextStyle(color: Colors.black54, fontSize: 12)),
        ])),
        IconButton.filledTonal(onPressed: quantity > 1 ? () => setState(() => _quantities[medicine.name] = quantity - 1) : null, icon: const Icon(Icons.remove, size: 18)),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text('$quantity', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
        IconButton.filledTonal(
          onPressed: quantity < medicine.stock
              ? () => setState(() => _quantities[medicine.name] = quantity + 1)
              : null,
          icon: const Icon(Icons.add, size: 18),
        ),
      ]),
    );
  }

  Widget _hero(String title, String subtitle) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 22),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF0F172A), Color(0xFF164E63)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(26),
          boxShadow: [BoxShadow(color: const Color(0xFF0F172A).withValues(alpha: 0.12), blurRadius: 18, offset: const Offset(0, 9))],
        ),
        child: Row(
          children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 26, height: 1.1, fontWeight: FontWeight.w800, color: Colors.white)),
              const SizedBox(height: 9),
              Text(subtitle, style: const TextStyle(fontSize: 14, height: 1.35, color: Colors.white70)),
            ])),
            const SizedBox(width: 14),
            Container(width: 52, height: 52, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(18)), child: const Icon(Icons.health_and_safety_rounded, color: Color(0xFF7DE2B8), size: 28)),
          ],
        ),
      );

    Widget _field(String label, TextEditingController controller, IconData icon, {bool numeric = false, bool readOnly = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
      child: TextField(readOnly: readOnly, controller: controller, keyboardType: numeric ? TextInputType.number : TextInputType.text, decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon), suffixIcon: readOnly ? const Icon(Icons.lock_outline_rounded, size: 18, color: Colors.black26) : null, filled: true, fillColor: readOnly ? const Color(0xFFF7FAF8) : Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none))),
      );

  Widget _choice(String label, bool selected, VoidCallback onTap, {String? detail}) => AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFE8F8F1) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? const Color(0xFF1EB980) : Colors.transparent, width: 1.5),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.035), blurRadius: 12, offset: const Offset(0, 5))],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
              child: Row(children: [
                Icon(selected ? Icons.check_circle_rounded : Icons.circle_outlined, color: selected ? const Color(0xFF1EB980) : Colors.black26),
                const SizedBox(width: 13),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF0F172A))), if (detail != null) ...[const SizedBox(height: 4), Text(detail, style: const TextStyle(fontSize: 12, color: Colors.black54))]])),
                if (selected) const Icon(Icons.arrow_forward_rounded, color: Color(0xFF1EB980), size: 20),
              ]),
            ),
          ),
        ),
      );

  Widget _infoCard(String label, String value) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.035), blurRadius: 12, offset: const Offset(0, 5))]),
        child: Row(children: [Expanded(child: Text(label, style: const TextStyle(color: Colors.black54, fontWeight: FontWeight.w600))), Flexible(child: Text(value, textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF0F172A))))]),
      );

    Widget _continueButton(String label) => Padding(
        padding: const EdgeInsets.only(top: 18),
      child: SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: _isSubmitting ? null : _next, icon: _isSubmitting ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(_step == 4 ? Icons.send_rounded : Icons.arrow_forward_rounded), style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1EB980), foregroundColor: const Color(0xFF06261A), padding: const EdgeInsets.symmetric(vertical: 17), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17))), label: Text(_isSubmitting ? 'Sending request...' : label, style: const TextStyle(fontWeight: FontWeight.w800)))),
      );
}

class DispensingStatusScreen extends StatefulWidget {
  const DispensingStatusScreen({
    super.key,
    required this.patient,
    required this.medicine,
    required this.quantity,
    required this.items,
    this.requestId,
    this.command,
    this.espAddress,
    this.initialDelivery,
    this.onStartNewRequest,
  });

  final PatientData patient;
  final Medication medicine;
  final int quantity;
  final List<Map<String, dynamic>> items;
  final String? requestId;
  final String? command;
  final String? espAddress;
  final EspConnectionResult? initialDelivery;
  final VoidCallback? onStartNewRequest;

  @override
  State<DispensingStatusScreen> createState() => _DispensingStatusScreenState();
}

class _DispensingStatusScreenState extends State<DispensingStatusScreen> {
  EspConnectionResult? _delivery;
  bool _retrying = false;

  @override
  void initState() {
    super.initState();
    _delivery = widget.initialDelivery;
  }

  Future<void> _retryDelivery() async {
    final address = widget.espAddress;
    final command = widget.command;
    final requestId = widget.requestId;
    if (address == null || address.isEmpty || command == null) return;
    setState(() => _retrying = true);
    final result = await EspConnectionService.instance.sendCommand(address: address, command: command);
    if (requestId != null) {
      await FirebaseService.instance.updateDispenseDelivery(requestId: requestId, success: result.success, message: result.message, address: address);
    }
    if (!mounted) return;
    setState(() {
      _delivery = result;
      _retrying = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final delivery = _delivery;
    final espSuccess = delivery?.success ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('Dispensing progress')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const SizedBox(height: 16),
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(32),
                ),
                child: const Icon(Icons.check_circle_rounded, size: 52, color: Color(0xFF15803D)),
              ),
              const SizedBox(height: 24),
              Text(
                'Request submitted',
                style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              Text(
                'Stock was updated and saved to your history.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(color: Colors.black54),
              ),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Submitted medicines', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                  const SizedBox(height: 10),
                  ...widget.items.map((item) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(children: [
                      const Icon(Icons.medication_rounded, size: 19, color: Color(0xFF1EB980)),
                      const SizedBox(width: 8),
                      Expanded(child: Text('${item['medicine'] ?? 'Medicine'}  (${item['strength'] ?? ''})', style: const TextStyle(fontWeight: FontWeight.w700))),
                      Text('${item['quantity'] ?? 0} unit(s)  /  P${item['position'] ?? '-'}', style: const TextStyle(color: Colors.black54, fontSize: 11)),
                    ]),
                  )),
                ]),
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: const Color(0xFF0F172A), borderRadius: BorderRadius.circular(20)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('ESP32 command', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                  const SizedBox(height: 6),
                  const Text('ASCII command: two decimal digits per position P1-P7. 00 means no dispense.', style: TextStyle(color: Colors.white70, fontSize: 11)),
                  const SizedBox(height: 10),
                  SelectableText(widget.command ?? '-', style: const TextStyle(color: Color(0xFF7DE2B8), fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 2)),
                  const SizedBox(height: 8),
                  Text(_commandBreakdown(), style: const TextStyle(color: Colors.white70, fontSize: 11, height: 1.4)),
                ]),
              ),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: espSuccess ? const Color(0xFFE8F8F1) : const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: espSuccess ? const Color(0xFFBDEBD8) : const Color(0xFFFECACA)),
                ),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(espSuccess ? Icons.wifi_rounded : Icons.wifi_off_rounded, color: espSuccess ? const Color(0xFF1EB980) : const Color(0xFFB91C1C)),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(espSuccess ? 'Dispenser command delivered' : 'Dispenser did not respond', style: TextStyle(color: espSuccess ? const Color(0xFF165B43) : const Color(0xFF991B1B), fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(delivery?.message ?? 'Connecting to the dispenser...', style: TextStyle(color: espSuccess ? const Color(0xFF165B43) : const Color(0xFF991B1B), fontSize: 12)),
                    if (widget.espAddress != null) ...[
                      const SizedBox(height: 4),
                      Text('Address: ${widget.espAddress}', style: TextStyle(color: espSuccess ? const Color(0xFF165B43) : const Color(0xFF991B1B), fontSize: 12, fontWeight: FontWeight.w600)),
                    ],
                    if (!espSuccess) ...[
                      const SizedBox(height: 10),
                      SizedBox(width: double.infinity, child: OutlinedButton.icon(
                        onPressed: _retrying ? null : _retryDelivery,
                        icon: _retrying ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh_rounded, size: 18),
                        label: Text(_retrying ? 'Retrying...' : 'Retry connection'),
                      )),
                    ],
                  ])),
                ]),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  children: [
                    _statusRow('Patient', widget.patient.name),
                    _statusRow('Medicines', '${widget.items.length} selected'),
                    _statusRow('Instructions', widget.medicine.instructions),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    widget.onStartNewRequest?.call();
                    Navigator.of(context).popUntil((route) => route.isFirst);
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0F172A),
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  icon: const Icon(Icons.done_rounded),
                  label: const Text('Finish'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _commandBreakdown() {
    final command = widget.command ?? '';
    final parts = <String>[];
    for (var index = 0; index < command.length; index += 2) {
      final end = (index + 2).clamp(0, command.length);
      parts.add('P${(index ~/ 2) + 1}=${command.substring(index, end)}');
    }
    return parts.join('   ');
  }

  Widget _statusRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(color: Colors.black54, fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}


/// Scans the QR code stuck on the bus (or accepts manual entry for testing)
/// to learn the dispenser's IP/hostname, then tries a real WiFi connection
/// to it before saving it as the paired address everyone else reads from.
class EspPairingScreen extends StatefulWidget {
  const EspPairingScreen({super.key});

  @override
  State<EspPairingScreen> createState() => _EspPairingScreenState();
}

class _EspPairingScreenState extends State<EspPairingScreen> {
  final MobileScannerController _scannerController = MobileScannerController();
  final TextEditingController _manualController = TextEditingController();
  bool _testing = false;
  bool _saving = false;
  String? _scannedValue;
  EspConnectionResult? _testResult;
  bool _showScanner = true;

  @override
  void dispose() {
    _scannerController.dispose();
    _manualController.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (!_showScanner) return;
    if (capture.barcodes.isEmpty) return;
    final value = capture.barcodes.first.rawValue;
    if (value == null || value.isEmpty) return;
    setState(() {
      _scannedValue = value;
      _manualController.text = value;
      _showScanner = false;
      _testResult = null;
    });
  }

  Future<void> _testConnection() async {
    final address = _manualController.text.trim();
    if (address.isEmpty) return;
    setState(() {
      _testing = true;
      _testResult = null;
    });
    final result = await EspConnectionService.instance.testConnection(address);
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testResult = result;
    });
  }

  Future<void> _saveAndClose() async {
    final address = _manualController.text.trim();
    if (address.isEmpty) return;
    setState(() => _saving = true);
    try {
      await FirebaseService.instance.savePairedEsp(address);
      if (mounted) Navigator.pop(context, address);
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save the dispenser address: $error')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F8F5),
      appBar: AppBar(backgroundColor: const Color(0xFFF2F8F5), foregroundColor: const Color(0xFF0F172A), elevation: 0, title: const Text('Connect to dispenser', style: TextStyle(fontWeight: FontWeight.w800))),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: const Color(0xFFE8F8F1), borderRadius: BorderRadius.circular(18)), child: const Row(children: [
          Icon(Icons.info_outline_rounded, color: Color(0xFF1EB980)),
          SizedBox(width: 10),
          Expanded(child: Text('Scan the QR code stuck on the bus. It encodes the dispenser\'s IP address (or hostname) on the local WiFi network.', style: TextStyle(color: Color(0xFF165B43), fontSize: 12, fontWeight: FontWeight.w600))),
        ])),
        const SizedBox(height: 16),
        if (_showScanner)
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: SizedBox(height: 280, child: MobileScanner(controller: _scannerController, onDetect: _onDetect)),
          )
        else
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
            child: Row(children: [
              const Icon(Icons.qr_code_rounded, color: Color(0xFF2563EB)),
              const SizedBox(width: 10),
              Expanded(child: Text('Scanned: $_scannedValue', style: const TextStyle(fontWeight: FontWeight.w700))),
              TextButton(onPressed: () => setState(() { _showScanner = true; _scannedValue = null; }), child: const Text('Rescan')),
            ]),
          ),
        const SizedBox(height: 16),
        TextField(
          controller: _manualController,
          decoration: InputDecoration(
            labelText: 'Dispenser IP / hostname (or paste for testing)',
            hintText: 'e.g. 192.168.1.50',
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 8),
        const Text('No QR yet? Generate one on any free QR-code website with a test IP, or just type a value above to test the flow.', style: TextStyle(color: Colors.black54, fontSize: 12)),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _testing ? null : _testConnection,
          icon: _testing ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.wifi_find_rounded),
          label: Text(_testing ? 'Connecting...' : 'Test connection now'),
        ),
        if (_testResult != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: _testResult!.success ? const Color(0xFFE8F8F1) : const Color(0xFFFEF2F2), borderRadius: BorderRadius.circular(16)),
            child: Row(children: [
              Icon(_testResult!.success ? Icons.check_circle_rounded : Icons.error_outline_rounded, color: _testResult!.success ? const Color(0xFF1EB980) : const Color(0xFFB91C1C)),
              const SizedBox(width: 10),
              Expanded(child: Text(_testResult!.message, style: TextStyle(color: _testResult!.success ? const Color(0xFF165B43) : const Color(0xFF991B1B), fontWeight: FontWeight.w600, fontSize: 12))),
            ]),
          ),
        ],
        const SizedBox(height: 24),
        SizedBox(width: double.infinity, child: FilledButton.icon(
          onPressed: _saving ? null : _saveAndClose,
          icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save_rounded),
          label: Text(_saving ? 'Saving...' : 'Use this dispenser'),
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1EB980), padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
        )),
      ]),
    );
  }
}

