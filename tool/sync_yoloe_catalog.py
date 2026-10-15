"""Sincroniza os 57 prompts com o snapshot e uma migration incremental.

Execute após alterar assets/data/yoloe_classes.json e antes de reexportar o modelo.
Não muda IDs do catálogo existente. IDs 10000+ são reservados aos prompts YOLOE.
"""
import json
import unicodedata
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def normalized(value):
    return ''.join(c for c in unicodedata.normalize('NFD', value.lower())
                   if unicodedata.category(c) != 'Mn').strip()


def main():
    profile = json.loads((ROOT / 'assets/data/yoloe_classes.json').read_text())
    catalog_path = ROOT / 'assets/data/catalog.json'
    catalog = json.loads(catalog_path.read_text())
    classes = profile['classes']
    catalog['yoloe_classes'] = classes
    reserved_ids = {10000 + i for i in range(len(classes))}
    catalog['objects'] = [r for r in catalog['objects'] if r['object_id'] not in reserved_ids]
    prompt_aliases = {normalized(c['label']) for c in classes}
    catalog['aliases'] = [r for r in catalog['aliases']
                          if r['object_id'] not in reserved_ids
                          and r['normalized_alias'] not in prompt_aliases]
    rows, aliases = [], []
    material_names = {'plastic': 'Plástico', 'paper': 'Papel', 'glass': 'Vidro',
                      'metal': 'Metal', 'organic': 'Orgânico',
                      'special': 'Descarte especial', 'electronic': 'Eletrônico'}
    bins = {'plastic': 'Vermelha', 'paper': 'Azul', 'glass': 'Verde',
            'metal': 'Amarela', 'organic': 'Marrom',
            'special': 'Coleta especial', 'electronic': 'Coleta especial'}
    for i, c in enumerate(classes):
        material = c['material_id']
        row = dict(object_id=10000 + i, object_name=c['object_name'],
                   detection_class=c['label'], is_active=True,
                   is_ambiguous=material is None,
                   material_name=material_names.get(material),
                   category_name=material_names.get(material), bin_name=bins.get(material),
                   recommendation=c['instruction'], preparation_instructions=c['instruction'],
                   special_waste=[material_names[material]] if material in ('special', 'electronic') else [],
                   variant_count=0)
        rows.append(row)
        aliases.append(dict(object_id=row['object_id'], variant_id=None,
                            normalized_alias=normalized(c['label']), is_active=True))
    catalog['objects'].extend(rows)
    catalog['aliases'].extend(aliases)
    catalog['generatedAt'] = '2026-09-30'
    catalog_path.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + '\n')
    def sql_json(value):
        return "'" + json.dumps(value, ensure_ascii=False).replace("'", "''") + "'::jsonb"
    pt_rows = [dict(
        objeto_id=row['object_id'], nome=row['object_name'],
        classe_deteccao=row['detection_class'], ativo=row['is_active'],
        ambiguo=row['is_ambiguous'], nome_material=row['material_name'],
        categoria=row['category_name'], cor_lixeira=row['bin_name'],
        recomendacao=row['recommendation'],
        instrucoes_preparo=row['preparation_instructions'],
        residuos_especiais=row['special_waste'],
        quantidade_variantes=row['variant_count'],
    ) for row in rows]
    pt_aliases = [dict(
        objeto_id=row['object_id'], variante_id=row['variant_id'],
        sinonimo_normalizado=row['normalized_alias'], ativo=row['is_active'],
    ) for row in aliases]
    classes_rows = [dict(
        indice_classe=index, nome_classe=row['classe_deteccao'],
        prompt=row['classe_deteccao'], objeto_id=row['objeto_id'],
    ) for index, row in enumerate(pt_rows)]

    sql = """-- Atualiza prompts YOLO-E depois da migração do esquema em português.
-- Uma transação mantém catálogo, sinônimos e classes consistentes.
begin;
"""
    # Exact prompt rows take precedence in the RPC. Existing generic objects
    # remain available under their original Portuguese names and other aliases.
    labels = [c['label'] for c in classes]
    sql += 'update public.objetos set classe_deteccao = null where objeto_id < 10000 and classe_deteccao in (select value from jsonb_array_elements_text(' + sql_json(labels) + '));\n'
    sql += 'delete from public.sinonimos_objeto where sinonimo_normalizado in (select value from jsonb_array_elements_text(' + sql_json(sorted(prompt_aliases)) + '));\n'
    sql += 'insert into public.objetos (objeto_id,nome,classe_deteccao,ativo,ambiguo,nome_material,categoria,cor_lixeira,recomendacao,instrucoes_preparo,residuos_especiais,quantidade_variantes,material_id) select r.objeto_id,r.nome,r.classe_deteccao,r.ativo,r.ambiguo,r.nome_material,r.categoria,r.cor_lixeira,r.recomendacao,r.instrucoes_preparo,r.residuos_especiais,r.quantidade_variantes,public.resolver_id_material_ecoscan(r.nome_material,r.categoria) from jsonb_populate_recordset(null::public.objetos, ' + sql_json(pt_rows) + ') r on conflict(objeto_id) do update set nome=excluded.nome,classe_deteccao=excluded.classe_deteccao,ativo=excluded.ativo,ambiguo=excluded.ambiguo,nome_material=excluded.nome_material,categoria=excluded.categoria,cor_lixeira=excluded.cor_lixeira,recomendacao=excluded.recomendacao,instrucoes_preparo=excluded.instrucoes_preparo,residuos_especiais=excluded.residuos_especiais,quantidade_variantes=excluded.quantidade_variantes,material_id=excluded.material_id;\n'
    sql += 'insert into public.sinonimos_objeto (objeto_id,variante_id,sinonimo_normalizado,ativo) select objeto_id,variante_id,sinonimo_normalizado,ativo from jsonb_populate_recordset(null::public.sinonimos_objeto, ' + sql_json(pt_aliases) + ') on conflict(objeto_id,variante_id,sinonimo_normalizado) do update set ativo=excluded.ativo;\n'
    sql += 'delete from public.classes_yoloe where versao_modelo_id is null and objeto_id >= 10000;\n'
    sql += 'insert into public.classes_yoloe (versao_modelo_id,indice_classe,nome_classe,prompt,objeto_id) select null,indice_classe,nome_classe,prompt,objeto_id from jsonb_to_recordset(' + sql_json(classes_rows) + ') as r(indice_classe integer,nome_classe text,prompt text,objeto_id bigint);\ncommit;\n'
    migration_dir = ROOT / 'supabase/migrations'
    existing_versions = [
        int(path.name[:12]) for path in migration_dir.glob('*.sql')
        if path.name[:12].isdigit()
    ]
    next_version = max(existing_versions, default=202610160001) + 1
    migration_path = migration_dir / f'{next_version}_yoloe_catalogo_atualizacao.sql'
    migration_path.write_text(sql, encoding='utf-8')
    print(f'{len(classes)} classes sincronizadas; {len(catalog["objects"])} objetos locais.')


if __name__ == '__main__':
    main()
