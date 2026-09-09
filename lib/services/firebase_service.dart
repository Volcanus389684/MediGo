import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import '../firebase_options.dart';
import '../models/medication.dart';
import 'iot_protocol.dart';

class FirebaseService {
  FirebaseService._();

  static final FirebaseService instance = FirebaseService._();

  FirebaseDatabase? _database;
  FirebaseStorage? _storage;
  String? lastInitError;

  bool get isReady => _database != null;
  bool get isStorageReady => _storage != null;

  static const String projectId = DefaultFirebaseOptions.projectId;
  static const String databaseUrl = DefaultFirebaseOptions.databaseUrl;
  static const String storageBucket = DefaultFirebaseOptions.storageBucket;

  Future<void> initialize() async {
    if (_database != null) return;
    try {
      FirebaseApp app;
      try {
        app = await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      } on FirebaseException catch (error) {
        // The native Android/iOS SDK can auto-initialize the default app from
        // google-services.json/GoogleService-Info.plist before Flutter gets here.
        if (error.code == 'duplicate-app') {
          app = Firebase.app();
        } else {
          rethrow;
        }
      }
      try {
        _database = FirebaseDatabase.instanceFor(app: app, databaseURL: databaseUrl);
      } catch (error, stack) {
        lastInitError = 'Realtime Database init failed: $error';
        debugPrint('$lastInitError\n$stack');
        _database = null;
      }
      try {
        _storage = FirebaseStorage.instanceFor(app: app, bucket: storageBucket);
      } catch (error) {
        debugPrint('Firebase Storage init failed: $error');
        _storage = null;
      }
    } catch (error, stack) {
      lastInitError = 'Firebase.initializeApp failed: $error';
      debugPrint('$lastInitError\n$stack');
      _database = null;
      _storage = null;
    }
  }

  DatabaseReference ref(String path) {
    if (_database == null) throw StateError('Firebase database is not initialized.');
    return _database!.ref(path);
  }

  Future<void> ensureDatabaseReady() async {
    if (isReady) return;
    await initialize();
    if (!isReady) throw StateError(lastInitError ?? 'Firebase Realtime Database is not ready.');
  }

  Future<Map<String, dynamic>> getCurrentUserProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _database == null) return {};
    final value = (await ref('users/${user.uid}').get()).value;
    return value is Map ? Map<String, dynamic>.from(value) : {};
  }

  Future<void> updateCurrentUserProfile({
    required String fullName,
    required int age,
    required double weight,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _database == null) return;
    await ref('users/${user.uid}').update({
      'fullName': fullName,
      'age': age,
      'weight': weight,
      'updatedAt': ServerValue.timestamp,
    });
  }

  Future<void> createCustomerProfile({
    required String fullName,
    required int age,
    required double weight,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('No signed-in Firebase user exists.');
    if (_database == null) throw StateError('Firebase Realtime Database is not initialized.');
    await ref('users/${user.uid}').set({
      'fullName': fullName,
      'age': age,
      'weight': weight,
      'email': user.email ?? '',
      'role': 'customer',
      'createdAt': ServerValue.timestamp,
    });
  }

  Future<List<Medication>> getMedicines() async {
    if (_database == null) return [];
    final value = (await ref('medicines').get()).value;
    return _parseMedicines(value);
  }

  Stream<List<Medication>> watchMedicines() {
    if (_database == null) return const Stream.empty();
    return ref('medicines').onValue.asyncMap((event) {
      return _parseMedicines(event.snapshot.value);
    });
  }

  List<Medication> _parseMedicines(Object? value) {
    final entries = switch (value) {
      Map map => map.values,
      List list => list,
      _ => const <Object?>[],
    };
    return entries.whereType<Map>().map((raw) {
      final item = Map<Object?, Object?>.from(raw);
      final stock = int.tryParse(item['stock']?.toString() ?? '0') ?? 0;
      return Medication(
        name: item['name']?.toString() ?? 'Unnamed medicine',
        strength: item['strength']?.toString() ?? '',
        position: item['position']?.toString() ?? '',
        available: stock > 0 && item['available'] == true,
        stock: stock,
        requiresPrescription: item['requiresPrescription'] != false,
        imageUrl: item['imageUrl']?.toString(),
        instructions: item['instructions']?.toString() ?? 'Take as directed.',
      );
    }).toList();
  }

  Reference storageRef(String path) {
    if (_storage == null) throw StateError('Firebase storage is not initialized.');
    return _storage!.ref(path);
  }

  Future<String> uploadPrescriptionImage({required String patientId, required File imageFile}) async {
    if (!isStorageReady) throw StateError('Firebase storage is not ready.');
    final fileRef = storageRef('prescriptions/${patientId}_${DateTime.now().millisecondsSinceEpoch}.jpg');
    final snapshot = await fileRef.putFile(imageFile, SettableMetadata(contentType: 'image/jpeg'));
    return snapshot.ref.getDownloadURL();
  }

  Future<void> savePrescriptionRecord({
    required String patientId,
    required String imageUrl,
    required String medicine,
    required String status,
    String? imageBase64,
  }) async {
    if (!isReady) return;
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    await ref('prescriptions/$id').set({
      'userId': FirebaseAuth.instance.currentUser?.uid ?? '',
      'patientId': patientId,
      'imageUrl': imageUrl,
      'fileType': 'image/jpeg',
      'medicine': medicine,
      'status': status,
      'imageBase64': imageBase64 ?? '',
      'createdAt': ServerValue.timestamp,
    });
  }

  /// Sets up (or restocks) one dispenser compartment. Called by the operator
  /// after physically loading medicine into the machine, replacing the old
  /// approve/reject workflow: the operator only manages stock counts now.
  Future<void> setMedicineSlot({
    required String position,
    required String name,
    required String strength,
    required int stock,
    required bool requiresPrescription,
    String instructions = 'Take as directed.',
  }) async {
    await ensureDatabaseReady();
    final slotRef = ref('medicines/$position');
    await slotRef.set({
      'name': name,
      'strength': strength,
      'position': position,
      'stock': stock,
      'available': stock > 0,
      'requiresPrescription': requiresPrescription,
      'instructions': instructions,
      'updatedAt': ServerValue.timestamp,
    });
    final saved = await slotRef.get();
    if (saved.value is! Map) {
      throw StateError('Firebase saved the slot, but the inventory record could not be read back.');
    }
  }

  Future<void> clearMedicineInventory() async {
    await ensureDatabaseReady();
    await ref('medicines').remove();
  }

  /// Stores the dispenser's paired address (IP, hostname, or MAC read from the
  /// QR code stuck on the bus) so every screen can reach the same machine.
  Future<void> savePairedEsp(String address) async {
    await ensureDatabaseReady();
    await ref('device/esp').set({
      'address': address,
      'pairedAt': ServerValue.timestamp,
    });
  }

  Future<String?> getPairedEspAddress() async {
    if (!isReady) return null;
    final value = (await ref('device/esp/address').get()).value;
    return value?.toString();
  }

  Stream<String?> watchPairedEspAddress() {
    if (_database == null) return const Stream.empty();
    return ref('device/esp/address').onValue.map((event) => event.snapshot.value?.toString());
  }

  /// Records whether the ESP32 actually accepted the command over WiFi, so
  /// both the patient and operator can see real delivery status, not just
  /// that Firebase was updated.
  Future<void> updateDispenseDelivery({
    required String requestId,
    required bool success,
    required String message,
    required String address,
  }) async {
    if (!isReady) return;
    await ref('dispensing/$requestId/espDelivery').set({
      'success': success,
      'message': message,
      'address': address,
      'updatedAt': ServerValue.timestamp,
    });
  }

  /// Submits a patient dispense request. Stock for each requested medicine is
  /// decremented atomically (no operator approval step); if any medicine no
  /// longer has enough stock the whole request is rejected before anything is
  /// written. The resulting ESP32 command is stored for the IoT team to
  /// consume, and a read-only log entry is kept for history/usage tracking.
  Future<DispenseSubmission> submitDispenseRequest({
    required String patientId,
    required String patientName,
    required List<Map<String, dynamic>> items,
    required bool hasPrescription,
    String? prescriptionUrl,
    String? prescriptionImageBase64,
  }) async {
    await ensureDatabaseReady();
    if (items.isEmpty) throw StateError('Select at least one medicine before submitting.');

    final quantityByPosition = <String, int>{};
    for (final item in items) {
      final position = item['position']?.toString() ?? '';
      final quantity = int.tryParse(item['quantity']?.toString() ?? '') ?? 0;
      if (position.isEmpty || quantity <= 0) continue;

      final result = await ref('medicines/$position/stock').runTransaction((currentData) {
        final currentStock = int.tryParse(currentData?.toString() ?? '0') ?? 0;
        if (currentStock < quantity) return Transaction.abort();
        return Transaction.success(currentStock - quantity);
      });
      if (!result.committed) {
        throw StateError('${item['medicine'] ?? 'A medicine'} no longer has enough stock. Please refresh and try again.');
      }
      final remainingStock = int.tryParse(result.snapshot.value?.toString() ?? '0') ?? 0;
      await ref('medicines/$position/available').set(remainingStock > 0);
      quantityByPosition[position] = quantity;
    }

    final requestId = DateTime.now().millisecondsSinceEpoch.toString();
    final command = IotProtocol.buildDispenseCommand(quantityByPosition);
    await ref('dispensing/$requestId').set({
      'userId': FirebaseAuth.instance.currentUser?.uid ?? '',
      'patientId': patientId,
      'patientName': patientName,
      'medicines': items,
      'binaryCommand': command,
      'status': IotProtocol.statusDispensed,
      'hasPrescription': hasPrescription,
      'prescriptionUrl': prescriptionUrl ?? '',
      'prescriptionImageBase64': prescriptionImageBase64 ?? '',
      'createdAt': ServerValue.timestamp,
    });
    await ref('device/command').set({
      'requestId': requestId,
      'command': command,
      'createdAt': ServerValue.timestamp,
    });
    return DispenseSubmission(requestId: requestId, command: command);
  }

  Stream<DatabaseEvent> watchDispensingRequests() => _database == null ? const Stream.empty() : ref('dispensing').onValue;
  Stream<DatabaseEvent> watchDispensingRequest(String requestId) => _database == null ? const Stream.empty() : ref('dispensing/$requestId').onValue;
}

/// Result of [FirebaseService.submitDispenseRequest]: the request's Firebase
/// id plus the ESP32 command that still needs to be delivered over WiFi.
class DispenseSubmission {
  const DispenseSubmission({required this.requestId, required this.command});

  final String requestId;
  final String command;
}
