import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/firebase_backend_config.dart';
import '../models/detection_record.dart';
import '../models/learning_sample.dart';
import 'firebase_session_bridge.dart';

/// Mirrors account data to Firestore and private Cloud Storage. Supabase
/// remains the authentication provider and continues to serve app features.
class FirebaseAccountBackupService {
  FirebaseAccountBackupService._();

  static final FirebaseAccountBackupService shared =
      FirebaseAccountBackupService._();

  bool get isAvailable =>
      FirebaseBackendConfig.isConfigured && Firebase.apps.isNotEmpty;

  DocumentReference<Map<String, dynamic>> _userDocument(String uid) =>
      FirebaseFirestore.instance.collection('users').doc(uid);

  CollectionReference<Map<String, dynamic>> _scans(String uid) =>
      _userDocument(uid).collection('scans');

  CollectionReference<Map<String, dynamic>> _corrections(String uid) =>
      _userDocument(uid).collection('corrections');

  Future<void> _requireFirebaseUser(String uid) async {
    if (!isAvailable) return;
    final linked = await FirebaseSessionBridge.syncCurrentSession();
    if (!linked || FirebaseAuth.instance.currentUser?.uid != uid) {
      throw StateError('A sessão do Firebase ainda não está pronta.');
    }
  }

  Future<String?> saveScan(String uid, DetectionRecord record) async {
    if (!isAvailable) return null;
    await _requireFirebaseUser(uid);
    final id = _safeId(record.id);
    final imagePath = await _uploadImage(
      uid,
      'scans/$id.jpg',
      record.imagePath,
    );
    await _scans(uid).doc(id).set({
      'scanId': record.id,
      'name': record.name,
      'category': record.category,
      'bin': record.bin,
      'destination': record.destination,
      'confidence': record.confidence,
      'imagePath': imagePath,
      'detectedAt': record.detectedAt.toUtc().toIso8601String(),
      'source': record.source,
      'confirmedByUser': record.confirmedByUser,
      'latitude': record.latitude,
      'longitude': record.longitude,
      'detectedObject': record.detectedObject,
      'detector': record.detector,
      'objectId': record.objectId,
      'variantId': record.variantId,
      'detectionLabel': record.detectionLabel,
      'classIndex': record.classIndex,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await _recordAction(uid, 'scan_saved', id);
    return imagePath;
  }

  Future<void> saveCorrection(String uid, LearningSample sample) async {
    if (!isAvailable) return;
    await _requireFirebaseUser(uid);
    final id = _safeId(sample.id);
    final imagePath = await _uploadImage(
      uid,
      'corrections/$id.jpg',
      sample.thumbnailDataUrl,
    );
    await _corrections(uid).doc(id).set({
      'correctionId': sample.id,
      'imagePath': imagePath,
      'source': sample.source,
      'detector': sample.detector,
      'detections': sample.detections,
      'reportedLabel': sample.reportedLabel,
      'reportedBin': sample.reportedBin,
      'reportNote': sample.reportNote,
      'aiDetected': sample.aiDetected ?? false,
      'originalLabel': sample.originalLabel,
      'originalConfidence': sample.originalConfidence,
      'createdAt': sample.createdAt.toUtc().toIso8601String(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await _recordAction(uid, 'correction_saved', id);
  }

  Future<void> saveProfile(
    String uid, {
    required String displayName,
    required String email,
  }) async {
    if (!isAvailable) return;
    await _requireFirebaseUser(uid);
    final profile = await _userDocument(uid).get();
    final existing = profile.data() ?? const <String, dynamic>{};
    if (existing['displayName'] == displayName && existing['email'] == email) {
      return;
    }
    await _userDocument(uid).set({
      'uid': uid,
      'displayName': displayName,
      'email': email,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await _recordAction(uid, 'profile_updated', 'profile');
  }

  Future<void> saveSettings(
    String uid, {
    required bool darkMode,
    required bool sounds,
    required bool notifications,
    required bool mapExplored,
    required String profilePhoto,
  }) async {
    if (!isAvailable) return;
    await _requireFirebaseUser(uid);
    final photoPath = await _uploadImage(
      uid,
      'profile/avatar.jpg',
      profilePhoto,
    );
    await _userDocument(uid).collection('settings').doc('preferences').set({
      'theme': darkMode ? 'dark' : 'light',
      'sounds': sounds,
      'notifications': notifications,
      'mapExplored': mapExplored,
      'profileImagePath': photoPath,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await _recordAction(uid, 'settings_updated', 'preferences');
  }

  Future<void> saveAchievements(String uid, Iterable<String> ids) async {
    if (!isAvailable) return;
    await _requireFirebaseUser(uid);
    final cleaned = ids.where((value) => value.isNotEmpty).toSet();
    if (cleaned.isEmpty) return;
    final batch = FirebaseFirestore.instance.batch();
    for (final id in cleaned) {
      batch.set(
        _userDocument(uid).collection('achievements').doc(_safeId(id)),
        {'achievementId': id, 'unlockedAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );
    }
    await batch.commit();
    await _recordAction(uid, 'achievements_updated', 'achievements');
  }

  Future<void> deleteScans(String uid, Iterable<String> ids) async {
    if (!isAvailable) return;
    await _requireFirebaseUser(uid);
    final firestore = FirebaseFirestore.instance;
    final batch = firestore.batch();
    final storage = FirebaseStorage.instance;
    final cleaned = ids.where((id) => id.isNotEmpty).toSet();
    for (final id in cleaned) {
      batch.delete(_scans(uid).doc(_safeId(id)));
    }
    if (cleaned.isNotEmpty) await batch.commit();
    for (final id in cleaned) {
      try {
        await storage.ref('users/$uid/scans/${_safeId(id)}.jpg').delete();
      } on FirebaseException catch (error) {
        if (error.code != 'object-not-found') rethrow;
      }
    }
    if (cleaned.isNotEmpty) {
      await _recordAction(uid, 'scans_deleted', cleaned.join(','));
    }
  }

  Future<bool> needsLegacyMigration(String uid) async {
    if (!isAvailable) return false;
    await _requireFirebaseUser(uid);
    final migration = _userDocument(uid).collection('meta').doc('migration_v1');
    final existing = await migration.get();
    return existing.data()?['legacyDataCopied'] != true;
  }

  Future<void> markLegacyMigrationComplete(String uid) async {
    if (!isAvailable) return;
    await _requireFirebaseUser(uid);
    final migration = _userDocument(uid).collection('meta').doc('migration_v1');
    await migration.set({
      'legacyDataCopied': true,
      'completedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<Map<String, dynamic>?> fetchSettings(String uid) async {
    if (!isAvailable) return null;
    await _requireFirebaseUser(uid);
    final snapshot = await _userDocument(uid)
        .collection('settings')
        .doc('preferences')
        .get();
    final data = snapshot.data();
    if (data == null) return null;
    final path = data['profileImagePath']?.toString() ?? '';
    if (path.isNotEmpty) {
      try {
        final bytes = await FirebaseStorage.instance.ref(path).getData(
          10 * 1024 * 1024,
        );
        if (bytes != null && bytes.isNotEmpty) {
          data['profileImageDataUrl'] =
              'data:image/jpeg;base64,${base64Encode(bytes)}';
        }
      } on FirebaseException catch (error) {
        if (error.code != 'object-not-found') rethrow;
      }
    }
    return data;
  }

  Future<Set<String>> fetchAchievementIds(String uid) async {
    if (!isAvailable) return const <String>{};
    await _requireFirebaseUser(uid);
    final snapshot = await _userDocument(uid).collection('achievements').get();
    return snapshot.docs
        .map((document) =>
            document.data()['achievementId']?.toString() ?? document.id)
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  Future<void> markCorrectionsSubmitted(
    String uid,
    Iterable<String> ids,
  ) async {
    if (!isAvailable) return;
    await _requireFirebaseUser(uid);
    final cleaned = ids.where((id) => id.isNotEmpty).toSet();
    if (cleaned.isEmpty) return;
    final firestore = FirebaseFirestore.instance;
    final batch = firestore.batch();
    for (final id in cleaned) {
      batch.set(
        _corrections(uid).doc(_safeId(id)),
        {'submittedAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );
    }
    await batch.commit();
    await _recordAction(uid, 'corrections_submitted', cleaned.join(','));
  }

  Future<List<DetectionRecord>> fetchScans(String uid) async {
    if (!isAvailable) return const [];
    await _requireFirebaseUser(uid);
    final snapshot = await _scans(uid).get();
    return snapshot.docs.map((doc) {
      final data = doc.data();
      final path = data['imagePath']?.toString() ?? '';
      return DetectionRecord(
        id: data['scanId']?.toString() ?? doc.id,
        name: data['name']?.toString() ?? '',
        category: data['category']?.toString() ?? '',
        bin: data['bin']?.toString() ?? '',
        destination: data['destination']?.toString() ?? '',
        confidence: (data['confidence'] as num?)?.toDouble() ?? 0,
        imagePath: path.isEmpty ? '' : 'firebase-storage://$path',
        detectedAt: DateTime.tryParse(data['detectedAt']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        source: data['source']?.toString() ?? 'camera',
        confirmedByUser: data['confirmedByUser'] == true,
        latitude: (data['latitude'] as num?)?.toDouble(),
        longitude: (data['longitude'] as num?)?.toDouble(),
        detectedObject: data['detectedObject']?.toString(),
        detector: data['detector']?.toString(),
        objectId: data['objectId']?.toString(),
        variantId: data['variantId']?.toString(),
        detectionLabel: data['detectionLabel']?.toString(),
        classIndex: (data['classIndex'] as num?)?.toInt(),
      );
    }).toList()
      ..sort((a, b) => b.detectedAt.compareTo(a.detectedAt));
  }

  Future<List<LearningSample>> fetchCorrections(String uid) async {
    if (!isAvailable) return const [];
    await _requireFirebaseUser(uid);
    final snapshot = await _corrections(uid).get();
    final restored = <LearningSample>[];
    for (final document in snapshot.docs) {
      final data = document.data();
      if (data['submittedAt'] != null) continue;
      final path = data['imagePath']?.toString() ?? '';
      if (path.isEmpty) continue;
      try {
        final bytes = await FirebaseStorage.instance.ref(path).getData(
          10 * 1024 * 1024,
        );
        if (bytes == null || bytes.isEmpty) continue;
        final rawDetections = data['detections'];
        final detections = rawDetections is List
            ? rawDetections
                  .whereType<Map>()
                  .map((value) => Map<String, dynamic>.from(value))
                  .toList(growable: false)
            : const <Map<String, dynamic>>[];
        final confidence = data['originalConfidence'];
        restored.add(
          LearningSample(
            id: data['correctionId']?.toString() ?? document.id,
            createdAt:
                DateTime.tryParse(data['createdAt']?.toString() ?? '') ??
                DateTime.now(),
            source: data['source']?.toString() ?? 'unknown',
            detector: data['detector']?.toString() ?? 'unknown',
            thumbnailDataUrl: 'data:image/jpeg;base64,${base64Encode(bytes)}',
            detections: detections,
            reportedLabel: data['reportedLabel']?.toString(),
            reportedBin: data['reportedBin']?.toString(),
            reportNote: data['reportNote']?.toString(),
            aiDetected: data['aiDetected'] is bool
                ? data['aiDetected'] as bool
                : null,
            originalLabel: data['originalLabel']?.toString(),
            originalConfidence: confidence is num
                ? confidence.toDouble()
                : double.tryParse(confidence?.toString() ?? ''),
          ),
        );
      } on FirebaseException catch (error) {
        if (error.code == 'object-not-found') continue;
        rethrow;
      }
    }
    return restored;
  }

  Future<String?> _uploadImage(String uid, String relativePath, String source) async {
    if (source.isEmpty) return null;
    if (source.startsWith('firebase-storage://')) {
      return source.substring('firebase-storage://'.length);
    }
    final bytes = await _imageBytes(source);
    if (bytes == null || bytes.isEmpty) {
      throw StateError('A imagem ainda não está disponível para enviar ao Firebase.');
    }
    if (bytes.length >= 10 * 1024 * 1024) {
      throw StateError('A imagem precisa ter menos de 10 MB para o Firebase.');
    }
    final path = 'users/$uid/$relativePath';
    await FirebaseStorage.instance.ref(path).putData(
      bytes,
      SettableMetadata(contentType: _contentType(source)),
    );
    return path;
  }

  static Future<Uint8List?> _imageBytes(String source) async {
    if (source.startsWith('data:image/')) {
      final comma = source.indexOf(',');
      if (comma < 0) return null;
      try {
        return base64Decode(source.substring(comma + 1));
      } catch (_) {
        return null;
      }
    }
    if (source.startsWith('https://') ||
        source.startsWith('http://') ||
        (kIsWeb && source.startsWith('blob:'))) {
      final response = await http.get(Uri.parse(source));
      return response.statusCode == 200 ? response.bodyBytes : null;
    }
    if (kIsWeb) return null;
    final file = File(source);
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  static String _contentType(String source) {
    final value = source.toLowerCase();
    if (value.contains('image/png') || value.endsWith('.png')) return 'image/png';
    if (value.contains('image/webp') || value.endsWith('.webp')) {
      return 'image/webp';
    }
    return 'image/jpeg';
  }

  static String _safeId(String value) =>
      value.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

  Future<void> _recordAction(String uid, String action, String resourceId) async {
    final safeResourceId = _safeId(resourceId);
    final eventId = '${_safeId(action)}_$safeResourceId';
    final now = FieldValue.serverTimestamp();
    await _userDocument(uid).set({
      'uid': uid,
      'lastAction': {
        'type': action,
        'resourceId': resourceId,
        'updatedAt': now,
      },
      'updatedAt': now,
    }, SetOptions(merge: true));
    await _userDocument(uid).collection('activity').doc(eventId).set({
      'eventId': eventId,
      'type': action,
      'resourceId': resourceId,
      'createdAt': now,
    }, SetOptions(merge: true));
  }
}
