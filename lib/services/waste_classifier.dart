import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';

import '../models/material_guide.dart';

class LabelCandidate {
  const LabelCandidate(this.label, this.confidence);
  final String label;
  final double confidence;
}

class WasteClassification {
  const WasteClassification({
    this.material,
    this.confidence = 0,
    this.options = const [],
    this.source = 'image',
    this.instruction,
    this.detectedObject,
    this.objectId,
    this.variantId,
    this.detectionLabel,
    this.classIndex,
  });

  final MaterialGuide? material;
  final double confidence;
  final List<MaterialGuide> options;
  final String source;
  final String? instruction;
  final String? detectedObject;
  final String? objectId;
  final String? variantId;
  final String? detectionLabel;
  final int? classIndex;

  bool get isKnown => material != null;
  bool get isManual => source == 'manual';
  bool get isAutomatic => isKnown && !isManual;

  String get name => material?.name ?? 'Material não identificado';
  String get category => name;
  String get bin => material?.bin ?? '—';
  String get destination =>
      instruction ??
      material?.instruction ??
      'A IA não conseguiu identificar o material com segurança. Tire outra foto aproximando apenas um objeto e usando boa iluminação.';

  WasteClassification confirmed(MaterialGuide choice) => WasteClassification(
    material: choice,
    source: 'manual',
    detectedObject: detectedObject,
    objectId: objectId,
    variantId: variantId,
    detectionLabel: detectionLabel,
    classIndex: classIndex,
  );

  WasteClassification copyWith({
    MaterialGuide? material,
    double? confidence,
    List<MaterialGuide>? options,
    String? source,
    String? instruction,
    String? detectedObject,
    String? objectId,
    String? variantId,
    String? detectionLabel,
    int? classIndex,
  }) => WasteClassification(
    material: material ?? this.material,
    confidence: confidence ?? this.confidence,
    options: options ?? this.options,
    source: source ?? this.source,
    instruction: instruction ?? this.instruction,
    detectedObject: detectedObject ?? this.detectedObject,
    objectId: objectId ?? this.objectId,
    variantId: variantId ?? this.variantId,
    detectionLabel: detectionLabel ?? this.detectionLabel,
    classIndex: classIndex ?? this.classIndex,
  );
}

/// Mapeia rótulos de visão computacional para o fluxo do EcoScan.
///
/// A IA identifica o objeto primeiro e depois resolve automaticamente o material
/// quando existe evidência suficiente. O aplicativo nunca obriga o usuário a
/// escolher manualmente o material: em caso de baixa confiança ele pede uma nova
/// foto, evitando registrar um descarte incorreto como se fosse certeza.
abstract final class WasteClassifier {
  static WasteClassification fromMlLabels(List<ImageLabel> labels) =>
      classifyCandidates(
        labels.map((l) => LabelCandidate(l.label, l.confidence)).toList(),
      );

  static const unknown = WasteClassification();

  static String normalize(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[_-]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ');

  static const directLabels = <String, List<String>>{
    'electronic': [
      'mobile phone',
      'cell phone',
      'cellular telephone',
      'smartphone',
      'computer',
      'desktop computer',
      'laptop',
      'notebook computer',
      'keyboard',
      'computer keyboard',
      'computer mouse',
      'desktop',
      'monitor',
      'computer monitor',
      'screen',
      'display',
      'cellphone',
      'cellular phone',
      'tv',
      'remote',
      'mouse computer',
      'headphones',
      'headphone',
      'earphones',
      'earbud',
      'charger',
      'remote control',
      'television',
      'tablet computer',
      'tablet',
      'hand-held computer',
      'handheld computer',
      'digital cellular phone',
      'electronic device',
      'printer',
      'computer printer',
      'speaker',
      'loudspeaker',
      'digital camera',
      'camera',
      'game controller',
      'joystick',
      'router',
      'modem',
      'power bank',
    ],
    'special': [
      'battery',
      'light bulb',
      'fluorescent lamp',
      'medicine',
      'syringe',
      'power cell',
      'button battery',
      'rechargeable battery',
    ],
    'plastic': [
      'plastic',
      'plastic bottle',
      'pop bottle',
      'soda bottle',
      'shampoo bottle',
      'lotion bottle',
      'detergent bottle',
      'plastic bag',
      'polyethylene',
      'pet bottle',
      'plastic container',
    ],
    'paper': [
      'paper',
      'cardboard',
      'paperboard',
      'newspaper',
      'cardboard box',
      'carton',
      'envelope',
      'book',
      'notebook',
      'paper bag',
    ],
    'glass': [
      'glass',
      'glass bottle',
      'glass jar',
      'glass container',
      'beer bottle',
      'wine bottle',
      'perfume bottle',
      'mason jar',
      'wine glass',
    ],
    'metal': [
      'aluminum',
      'aluminium',
      'tin can',
      'can',
      'beer can',
      'beverage can',
      'aluminum can',
      'steel',
      'metal bottle',
      'metal container',
    ],
    'organic': [
      'food',
      'fruit',
      'vegetable',
      'banana',
      'apple',
      'orange',
      'broccoli',
      'carrot',
      'bread',
      'food waste',
      'banana peel',
      'vegetables',
      'lemon',
      'pear',
      'pineapple',
      'strawberry',
    ],
  };

  static const _strongElectronicLabels = <String>{
    'mobile phone',
    'cell phone',
    'cellular telephone',
    'smartphone',
    'cellphone',
    'cellular phone',
    'digital cellular phone',
    'laptop',
    'notebook computer',
    'keyboard',
    'computer keyboard',
    'computer mouse',
    'desktop computer',
    'computer monitor',
    'tablet computer',
    'tablet',
    'hand-held computer',
    'handheld computer',
    'printer',
    'computer printer',
    'headphones',
    'headphone',
    'earphones',
    'earbud',
    'router',
    'modem',
    'power bank',
    'game controller',
    'joystick',
  };

  static const _phoneLabels = <String>{
    'mobile phone',
    'cell phone',
    'cellular telephone',
    'smartphone',
    'cellphone',
    'cellular phone',
    'digital cellular phone',
  };

  static const _specificMaterialLabels = <String>{
    'plastic bottle',
    'water bottle',
    'pop bottle',
    'soda bottle',
    'shampoo bottle',
    'lotion bottle',
    'detergent bottle',
    'pill bottle',
    'plastic bag',
    'pet bottle',
    'plastic container',
    'glass bottle',
    'glass jar',
    'glass container',
    'beer bottle',
    'wine bottle',
    'perfume bottle',
    'mason jar',
    'wine glass',
    'tin can',
    'beer can',
    'aluminum can',
    'beverage can',
    'metal bottle',
    'metal container',
  };

  static const _objectNames = <String, String>{
    'bottle': 'Garrafa',
    'beer bottle': 'Garrafa de vidro',
    'wine bottle': 'Garrafa de vidro',
    'glass bottle': 'Garrafa de vidro',
    'water bottle': 'Garrafa plástica',
    'pop bottle': 'Garrafa plástica',
    'soda bottle': 'Garrafa plástica',
    'plastic bottle': 'Garrafa plástica',
    'shampoo bottle': 'Frasco de shampoo',
    'lotion bottle': 'Frasco plástico',
    'detergent bottle': 'Frasco de detergente',
    'jar': 'Pote',
    'glass jar': 'Pote de vidro',
    'mason jar': 'Pote de vidro',
    'cup': 'Copo',
    'wine glass': 'Taça de vidro',
    'can': 'Lata',
    'tin can': 'Lata metálica',
    'beer can': 'Lata metálica',
    'aluminum can': 'Lata de alumínio',
    'beverage can': 'Lata metálica',
    'cardboard box': 'Caixa de papelão',
    'box': 'Caixa',
    'paper': 'Papel',
    'book': 'Livro',
    'newspaper': 'Jornal',
    'banana': 'Banana',
    'apple': 'Maçã',
    'orange': 'Laranja',
    'broccoli': 'Brócolis',
    'carrot': 'Cenoura',
    'mobile phone': 'Celular',
    'cell phone': 'Celular',
    'cellular telephone': 'Celular',
    'smartphone': 'Celular',
    'laptop': 'Notebook',
    'notebook computer': 'Notebook',
    'keyboard': 'Teclado',
    'computer keyboard': 'Teclado',
    'computer mouse': 'Mouse',
    'computer': 'Computador',
    'desktop computer': 'Computador',
    'desktop': 'Computador',
    'monitor': 'Monitor',
    'computer monitor': 'Monitor',
    'screen': 'Tela eletrônica',
    'display': 'Tela eletrônica',
    'cellphone': 'Celular',
    'cellular phone': 'Celular',
    'tv': 'Televisão',
    'remote': 'Controle remoto',
    'remote control': 'Controle remoto',
    'television': 'Televisão',
    'battery': 'Bateria/Pilha',
    'light bulb': 'Lâmpada',
    'tablet': 'Tablet',
    'tablet computer': 'Tablet',
    'hand-held computer': 'Dispositivo eletrônico',
    'handheld computer': 'Dispositivo eletrônico',
    'digital cellular phone': 'Celular',
    'electronic device': 'Eletrônico',
    'printer': 'Impressora',
    'computer printer': 'Impressora',
    'speaker': 'Caixa de som',
    'loudspeaker': 'Caixa de som',
    'digital camera': 'Câmera',
    'camera': 'Câmera',
    'game controller': 'Controle de videogame',
    'joystick': 'Controle de videogame',
    'router': 'Roteador',
    'modem': 'Modem',
    'power bank': 'Carregador portátil',
  };

  /// Confidence floor depends on how specific the model label is.
  /// Exact device/product labels can be trusted at a lower score than broad
  /// material words such as "plastic" or "glass". This makes product photos
  /// (especially phones and small electronics) work without inventing a
  /// material from weak generic evidence.
  static double minimumConfidenceForLabel(String value) {
    final label = normalize(value);
    if (_strongElectronicLabels.contains(label)) return 0.20;
    if (directLabels['electronic']!.contains(label)) return 0.45;
    if (directLabels['special']!.contains(label)) return 0.35;
    if (_specificMaterialLabels.contains(label)) return 0.42;
    return 0.55;
  }

  static bool isStrongSpecificLabel(String value) {
    final label = normalize(value);
    return _strongElectronicLabels.contains(label) ||
        directLabels['special']!.contains(label) ||
        _specificMaterialLabels.contains(label);
  }

  static LabelCandidate? _bestPhoneCandidate(List<LabelCandidate> candidates) {
    LabelCandidate? best;
    for (final candidate in candidates) {
      if (!candidate.confidence.isFinite || candidate.confidence < 0.20) {
        continue;
      }
      final label = normalize(candidate.label);
      if (!_phoneLabels.contains(label) &&
          !label.contains('cellular') &&
          !label.contains('phone')) {
        continue;
      }
      if (best == null || candidate.confidence > best.confidence) {
        best = candidate;
      }
    }
    return best;
  }

  static WasteClassification classifyCandidates(
    List<LabelCandidate> candidates,
  ) {
    final evidence = <String, double>{};
    for (final candidate in candidates) {
      if (!candidate.confidence.isFinite) continue;
      final label = normalize(candidate.label);
      final minimum = minimumConfidenceForLabel(label);
      if (candidate.confidence < minimum) continue;
      for (final entry in directLabels.entries) {
        if (entry.value.contains(label)) {
          final previous = evidence[entry.key] ?? 0;
          if (candidate.confidence > previous) {
            evidence[entry.key] = candidate.confidence;
          }
        }
      }
    }

    for (final special in ['special', 'electronic']) {
      if ((evidence[special] ?? 0) >= (special == 'electronic' ? 0.20 : 0.35)) {
        final objectName = bestObjectName(candidates);
        final preferredPhone = special == 'electronic'
            ? _bestPhoneCandidate(candidates)
            : null;
        return WasteClassification(
          material: MaterialGuide.byId(special),
          // When a second model provides specific phone evidence, keep the
          // displayed confidence tied to that chosen object instead of showing
          // a stronger contradictory TV/monitor score.
          confidence: objectName == 'Celular' && preferredPhone != null
              ? preferredPhone.confidence
              : evidence[special]!,
          detectedObject: objectName,
        );
      }
    }

    final ordered = evidence.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (ordered.isNotEmpty) {
      if (ordered.length > 1 && ordered[0].value - ordered[1].value < 0.12) {
        return WasteClassification(
          options: ordered.map((e) => MaterialGuide.byId(e.key)).toList(),
          detectedObject: bestObjectName(candidates),
        );
      }
      return WasteClassification(
        material: MaterialGuide.byId(ordered.first.key),
        confidence: ordered.first.value,
        detectedObject: bestObjectName(candidates),
      );
    }

    return WasteClassification(detectedObject: bestObjectName(candidates));
  }

  /// Finalização usada pelo Scanner. Remove a etapa de confirmação manual.
  /// Se o catálogo ficou ambíguo, tenta novamente com os rótulos específicos
  /// (inclusive rótulos de baixa confiança que são úteis para material).
  static WasteClassification finalizeAutomatic(
    WasteClassification result,
    List<LabelCandidate> candidates,
  ) {
    final objectName = result.detectedObject ?? bestObjectName(candidates);
    if (result.source == 'catalog-yoloe') {
      return result.copyWith(detectedObject: objectName, options: const []);
    }
    final direct = classifyCandidates(candidates);
    if (direct.material?.id == 'electronic' ||
        direct.material?.id == 'special') {
      return direct.copyWith(detectedObject: objectName, options: const []);
    }
    if (result.isKnown) {
      return result.copyWith(
        source: result.source == 'manual' ? 'ai' : result.source,
        detectedObject: objectName,
        options: const [],
      );
    }

    return WasteClassification(
      source: 'ai-unresolved',
      detectedObject: objectName,
      instruction:
          'Não consegui identificar o material com segurança. Tire outra foto aproximando apenas o objeto, com boa luz e fundo simples.',
    );
  }

  static String? bestObjectName(List<LabelCandidate> candidates) {
    // Phones are frequently confused with TV/monitor by general-purpose COCO
    // models in portrait product photos. A measured phone label >= 20% is more
    // specific than the generic screen label, so prefer it without inflating
    // its confidence.
    if (_bestPhoneCandidate(candidates) != null) return 'Celular';

    final sorted = [...candidates]
      ..sort((a, b) => b.confidence.compareTo(a.confidence));
    for (final candidate in sorted) {
      if (!candidate.confidence.isFinite) continue;
      final label = normalize(candidate.label);
      final minimum = isStrongSpecificLabel(label) ? 0.18 : 0.40;
      if (candidate.confidence < minimum) continue;
      final exact = _objectNames[label];
      if (exact != null) return exact;

      if (label.contains('bottle')) return 'Garrafa';
      if (label.contains('jar')) return 'Pote';
      if (label.contains('phone') || label.contains('cellular')) {
        return 'Celular';
      }
      if (label.contains('computer')) return 'Computador';
      if (label.contains('tablet')) return 'Tablet';
      if (label.contains('printer')) return 'Impressora';
      if (label.contains('camera')) return 'Câmera';
      if (label.contains('speaker')) return 'Caixa de som';
      if (label.contains('cardboard')) return 'Papelão';
    }
    return null;
  }
}
