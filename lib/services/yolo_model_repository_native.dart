import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_config.dart';
import 'yolo_model_repository_contract.dart';

YoloModelRepositoryPlatform createModelRepository() =>
    const _SupabaseModelRepository();

class _SupabaseModelRepository implements YoloModelRepositoryPlatform {
  const _SupabaseModelRepository();

  @override
  Future<String?> resolvePreferredModel() async {
    if (!AppConfig.useSupabaseModel ||
        (!Platform.isAndroid && !Platform.isIOS)) {
      return null;
    }
    try {
      final client = Supabase.instance.client;
      if (client.auth.currentUser == null) return null;
      final platformName = Platform.isAndroid ? 'android' : 'ios';
      final rows = await client
          .from('ecoscan_model_releases')
          .select('version,bucket_id,object_path,sha256,byte_size,created_at')
          .eq('platform', platformName)
          .eq('is_active', true)
          .order('created_at', ascending: false)
          .limit(1)
          .timeout(const Duration(seconds: 15));
      if (rows.isEmpty) return null;
      final release = Map<String, dynamic>.from(rows.first);
      final bucket = release['bucket_id']?.toString() ?? 'ecoscan-models';
      final objectPath = release['object_path']?.toString() ?? '';
      final expectedHash = release['sha256']?.toString().toLowerCase() ?? '';
      final expectedSize = (release['byte_size'] as num?)?.toInt();
      final version = _safeSegment(release['version']?.toString() ?? 'active');
      final fileName = p.basename(objectPath);
      if (objectPath.isEmpty ||
          fileName.isEmpty ||
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(expectedHash)) {
        return null;
      }
      final extensionOk = Platform.isAndroid
          ? fileName.toLowerCase().endsWith('.tflite')
          : fileName.toLowerCase().endsWith('.mlpackage.zip');
      if (!extensionOk) return null;

      final support = await getApplicationSupportDirectory();
      final folder = Directory(p.join(support.path, 'ecoscan', 'models'));
      await folder.create(recursive: true);
      final target = File(p.join(folder.path, '${version}_$fileName'));
      if (await target.exists() &&
          (expectedSize == null || await target.length() == expectedSize) &&
          await _hashFile(target) == expectedHash) {
        return target.path;
      }

      final bytes = await client.storage
          .from(bucket)
          .download(objectPath)
          .timeout(const Duration(seconds: 90));
      if (expectedSize != null && bytes.lengthInBytes != expectedSize) {
        throw const FormatException('Tamanho do modelo EcoScan inválido.');
      }
      final actualHash = sha256.convert(bytes).toString();
      if (actualHash != expectedHash) {
        throw const FormatException('Checksum do modelo EcoScan inválido.');
      }
      final partial = File('${target.path}.part');
      await partial.writeAsBytes(bytes, flush: true);
      if (await target.exists()) await target.delete();
      await partial.rename(target.path);
      return target.path;
    } catch (_) {
      // Missing migrations, network errors or an unauthenticated guest must not
      // disable scanning. YoloService continues with the official model.
      return null;
    }
  }

  static Future<String> _hashFile(File file) async =>
      (await sha256.bind(file.openRead()).first).toString();

  static String _safeSegment(String value) => value
      .replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_')
      .replaceAll(RegExp(r'_+'), '_');
}
