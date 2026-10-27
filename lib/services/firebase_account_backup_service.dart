import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../core/firebase_backend_config.dart';
import '../models/detection_record.dart';
import '../models/learning_sample.dart';
import 'firebase_session_bridge.dart';

/// Stores one replaceable snapshot of the user's latest meaningful action.
/// Supabase remains the source of account history, settings, photos and scores.
/// No image bytes are uploaded to Firebase Storage.
class FirebaseAccountBackupService {
  FirebaseAccountBackupService._();

  static final FirebaseAccountBackupService shared =
      FirebaseAccountBackupService._();

  bool get isAvailable =>
      FirebaseBackendConfig.isConfigured && Firebase.apps.isNotEmpty;

  DocumentReference<Map<String, dynamic>> _latestAction(String uid) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('state')
          .doc('latest_action');

  Future<void> _requireFirebaseUser(String uid) async {
    if (!isAvailable) return;
    final linked = await FirebaseSessionBridge.syncCurrentSession();
    if (!linked || FirebaseAuth.instance.currentUser?.uid != uid) {
      throw StateError('A sessão do Firebase ainda não está pronta.');
    }
  }

  /// Replaces the sole Firebase action document. Older delayed uploads cannot
  /// overwrite a newer action because the recorded event time is compared.
  Future<void> recordLatestAction(
    String uid, {
    required String type,
    String? resourceId,
    required DateTime occurredAt,
    Map<String, dynamic> details = const <String, dynamic>{},
  }) async {
    if (!isAvailable) return;
    await _requireFirebaseUser(uid);

    final reference = _latestAction(uid);
    final actionTime = occurredAt.toUtc();
    await FirebaseFirestore.instance.runTransaction<void>((transaction) async {
      final previous = await transaction.get(reference);
      final previousValue = previous.data()?['occurredAt'];
      final previousTime = previousValue is Timestamp
          ? previousValue.toDate().toUtc()
          : DateTime.tryParse(previousValue?.toString() ?? '')?.toUtc();
      if (previousTime != null && previousTime.isAfter(actionTime)) return;

      // Intentionally overwrite, leaving only the latest action for this UID.
      transaction.set(reference, <String, dynamic>{
        'uid': uid,
        'type': type,
        'resourceId': resourceId,
        'details': details,
        'occurredAt': Timestamp.fromDate(actionTime),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> saveScan(
    String uid,
    DetectionRecord record, {
    String? supabaseImagePath,
  }) async {
    await recordLatestAction(
      uid,
      type: 'scan_saved',
      resourceId: record.id,
      occurredAt: record.detectedAt,
      details: <String, dynamic>{
        'name': record.name,
        'category': record.category,
        'bin': record.bin,
        'destination': record.destination,
        'confidence': record.confidence,
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
        'hasImage': supabaseImagePath?.isNotEmpty == true,
        'imageProvider': supabaseImagePath?.isNotEmpty == true
            ? 'supabase'
            : null,
        'imagePath': supabaseImagePath,
      },
    );
  }

  Future<void> saveCorrection(
    String uid,
    LearningSample sample, {
    String? supabaseImagePath,
  }) =>
      recordLatestAction(
        uid,
        type: 'correction_saved',
        resourceId: sample.id,
        occurredAt: sample.createdAt,
        details: <String, dynamic>{
          'source': sample.source,
          'detector': sample.detector,
          'detections': sample.detections,
          'reportedLabel': sample.reportedLabel,
          'reportedBin': sample.reportedBin,
          'reportNote': sample.reportNote,
          'aiDetected': sample.aiDetected ?? false,
          'originalLabel': sample.originalLabel,
          'originalConfidence': sample.originalConfidence,
          'hasImage': supabaseImagePath?.isNotEmpty == true,
          'imageProvider': supabaseImagePath?.isNotEmpty == true
              ? 'supabase'
              : null,
          'imagePath': supabaseImagePath,
        },
      );

  Future<void> saveSettings(
    String uid, {
    required bool darkMode,
    required bool sounds,
    required bool notifications,
    required bool mapExplored,
    required String profilePhoto,
  }) =>
      recordLatestAction(
        uid,
        type: 'preferences_updated',
        resourceId: 'preferences',
        occurredAt: DateTime.now().toUtc(),
        details: <String, dynamic>{
          'theme': darkMode ? 'dark' : 'light',
          'sounds': sounds,
          'notifications': notifications,
          'mapExplored': mapExplored,
          'hasProfilePhoto': profilePhoto.isNotEmpty,
          'photoProvider': profilePhoto.isNotEmpty ? 'supabase' : null,
        },
      );

  Future<void> saveProfile(
    String uid, {
    required String displayName,
    required String email,
  }) =>
      recordLatestAction(
        uid,
        type: 'profile_updated',
        resourceId: 'profile',
        occurredAt: DateTime.now().toUtc(),
        details: <String, dynamic>{
          'displayName': displayName,
          'email': email,
        },
      );

  Future<void> saveAchievements(String uid, Iterable<String> ids) {
    final cleaned = ids.where((value) => value.isNotEmpty).toSet().toList();
    return recordLatestAction(
      uid,
      type: 'achievement_unlocked',
      resourceId: cleaned.isEmpty ? null : cleaned.last,
      occurredAt: DateTime.now().toUtc(),
      details: <String, dynamic>{'achievementIds': cleaned},
    );
  }

  Future<void> deleteScans(String uid, Iterable<String> ids) {
    final cleaned = ids.where((value) => value.isNotEmpty).toSet().toList();
    return recordLatestAction(
      uid,
      type: 'scans_deleted',
      resourceId: cleaned.length == 1 ? cleaned.single : null,
      occurredAt: DateTime.now().toUtc(),
      details: <String, dynamic>{
        'deletedCount': cleaned.length,
        'scanIds': cleaned.take(100).toList(growable: false),
        'hasAdditionalIds': cleaned.length > 100,
      },
    );
  }

  Future<void> markCorrectionsSubmitted(String uid, Iterable<String> ids) {
    final cleaned = ids.where((value) => value.isNotEmpty).toSet().toList();
    return recordLatestAction(
      uid,
      type: 'corrections_submitted_for_review',
      resourceId: cleaned.length == 1 ? cleaned.single : null,
      occurredAt: DateTime.now().toUtc(),
      details: <String, dynamic>{
        'submittedCount': cleaned.length,
        'correctionIds': cleaned.take(100).toList(growable: false),
        'hasAdditionalIds': cleaned.length > 100,
      },
    );
  }
}
