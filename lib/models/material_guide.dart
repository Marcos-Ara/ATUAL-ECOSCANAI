import 'package:flutter/material.dart';

class MaterialGuide {
  const MaterialGuide(
    this.id,
    this.name,
    this.bin,
    this.color,
    this.instruction,
    this.exclusions,
  );
  final String id;
  final String name;
  final String bin;
  final Color color;
  final String instruction;
  final String exclusions;
  bool get recyclable =>
      const ['paper', 'plastic', 'glass', 'metal'].contains(id);
  static const all = [
    MaterialGuide(
      'plastic',
      'Plástico',
      'Vermelha',
      Color(0xFFF44336),
      'Esvazie a embalagem, retire o excesso de resíduos e encaminhe para a coleta seletiva.',
      'Embalagens de produtos perigosos precisam de coleta específica.',
    ),
    MaterialGuide(
      'paper',
      'Papel',
      'Azul',
      Color(0xFF4388F5),
      'Mantenha papel e papelão secos e sem restos de comida para reciclar.',
      'Papel higiênico e papel contaminado não vão na coleta comum de papel.',
    ),
    MaterialGuide(
      'glass',
      'Vidro',
      'Verde',
      Color(0xFF59C15D),
      'Esvazie garrafas e potes. Proteja e identifique cacos antes de entregar à coleta.',
      'Espelhos, cerâmica, porcelana e lâmpadas não vão na coleta comum de vidro.',
    ),
    MaterialGuide(
      'metal',
      'Metal',
      'Amarela',
      Color(0xFFF4C542),
      'Esvazie latas e separe os metais aceitos na coleta da sua cidade.',
      'Recipientes pressurizados ou com produtos perigosos precisam de orientação específica.',
    ),
    MaterialGuide(
      'organic',
      'Orgânico',
      'Marrom',
      Color(0xFFAA795B),
      'Separe restos de frutas, verduras e alimentos para compostagem ou coleta orgânica.',
      'Retire sacolas, etiquetas e embalagens antes do descarte.',
    ),
    MaterialGuide(
      'reject',
      'Rejeito',
      'Cinza',
      Color(0xFF9AA3A5),
      'Use a coleta de rejeitos para materiais sem reciclagem ou compostagem na sua cidade.',
      'Não inclua pilhas, eletrônicos, lâmpadas ou medicamentos.',
    ),
    MaterialGuide(
      'electronic',
      'Eletrônico',
      'Coleta especial',
      Color(0xFFAE92ED),
      'Leve a um ponto autorizado de coleta de eletrônicos. Não coloque nas lixeiras comuns.',
      'Pilhas e baterias devem seguir a coleta específica e ficar protegidas contra curto-circuito.',
    ),
    MaterialGuide(
      'special',
      'Descarte especial',
      'Coleta especial',
      Color(0xFFEA944C),
      'Leve a um ponto de recebimento específico para esse resíduo.',
      'Não misture com recicláveis ou lixo comum. Confirme o destino no EcoPonto.',
    ),
  ];
  static MaterialGuide byId(String id) =>
      all.firstWhere((item) => item.id == id, orElse: () => all.last);
  static MaterialGuide? byName(String name) {
    for (final item in all) {
      if (item.name == name) return item;
    }
    return null;
  }

  static MaterialGuide? fromDatabase(Map<String, dynamic> row) {
    final special = row['special_waste'];
    if (special is List && special.isNotEmpty) {
      final text = special.toString().toLowerCase();
      return byId(text.contains('eletr') ? 'electronic' : 'special');
    }
    final text = [
      row['category_name'],
      row['material_name'],
      row['bin_name'],
    ].join(' ').toLowerCase();
    if (text.contains('eletr') || text.contains('bateria')) {
      return byId('electronic');
    }
    if (text.contains('especial') || text.contains('perigos')) {
      return byId('special');
    }
    if (text.contains('plástico') ||
        text.contains('plásticos') ||
        text.contains('vermelh')) {
      return byId('plastic');
    }
    if (text.contains('papel') || text.contains('azul')) return byId('paper');
    if (text.contains('vidro')) return byId('glass');
    if (text.contains('metal') ||
        text.contains('metais') ||
        text.contains('amarela')) {
      return byId('metal');
    }
    if (text.contains('orgân') ||
        text.contains('alimentar') ||
        text.contains('marrom')) {
      return byId('organic');
    }
    if (text.contains('rejeito') || text.contains('cinza')) {
      return byId('reject');
    }
    return null;
  }
}
