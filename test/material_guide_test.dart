import 'package:ecoscan_mobile/models/material_guide.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('exibe categorias em vez de nomes específicos de objetos', () {
    expect(MaterialGuide.byId('electronic').displayName, 'Eletrônicos');
    expect(MaterialGuide.byName('Rejeito')?.displayName,
        'Resíduo não reciclável');
    expect(MaterialGuide.byName('residuo nao reciclavel')?.id, 'reject');
  });

  test('conteúdo educativo mostra somente as seis lixeiras principais', () {
    expect(MaterialGuide.teachingBins.map((guide) => guide.id), [
      'plastic',
      'paper',
      'glass',
      'metal',
      'organic',
      'reject',
    ]);
    expect(MaterialGuide.byId('electronic').displayName, 'Eletrônicos');
  });
}
