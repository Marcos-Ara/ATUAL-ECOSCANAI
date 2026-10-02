import 'yolo_model_repository_contract.dart';

YoloModelRepositoryPlatform createModelRepository() =>
    const _UnsupportedModelRepository();

class _UnsupportedModelRepository implements YoloModelRepositoryPlatform {
  const _UnsupportedModelRepository();

  @override
  Future<String?> resolvePreferredModel() async => null;
}
