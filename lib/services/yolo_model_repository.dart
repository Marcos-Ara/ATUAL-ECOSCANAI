import 'yolo_model_repository_contract.dart';
import 'yolo_model_repository_stub.dart'
    if (dart.library.io) 'yolo_model_repository_native.dart' as platform;

class YoloModelRepository {
  YoloModelRepository({YoloModelRepositoryPlatform? implementation})
    : _implementation = implementation ?? platform.createModelRepository();

  final YoloModelRepositoryPlatform _implementation;

  Future<String?> resolvePreferredModel() =>
      _implementation.resolvePreferredModel();
}
