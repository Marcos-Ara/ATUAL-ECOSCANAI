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
    sql = """-- Prompts YOLOE; executar após as migrations 20260929.
-- Uma transação preserva a consistência entre objetos e aliases.
begin;
"""
    # Exact prompt rows take precedence in the RPC. Existing generic objects
    # remain available under their original Portuguese names and other aliases.
    sql += 'update public.objects set detection_class = null where object_id < 10000 and detection_class in (select value from jsonb_array_elements_text(' + sql_json([c['label'] for c in classes]) + '));\n'
    sql += 'delete from public.object_aliases where normalized_alias in (select value from jsonb_array_elements_text(' + sql_json(sorted(prompt_aliases)) + '));\n'
    sql += 'insert into public.objects select * from jsonb_populate_recordset(null::public.objects, ' + sql_json(rows) + ') on conflict(object_id) do update set object_name=excluded.object_name,detection_class=excluded.detection_class,is_active=excluded.is_active,is_ambiguous=excluded.is_ambiguous,material_name=excluded.material_name,category_name=excluded.category_name,bin_name=excluded.bin_name,recommendation=excluded.recommendation,preparation_instructions=excluded.preparation_instructions,special_waste=excluded.special_waste,variant_count=excluded.variant_count;\n'
    sql += 'insert into public.object_aliases select * from jsonb_populate_recordset(null::public.object_aliases, ' + sql_json(aliases) + ') on conflict(object_id,variant_id,normalized_alias) do update set is_active=excluded.is_active;\ncommit;\n'
    (ROOT / 'supabase/migrations/202609300001_yoloe_catalog.sql').write_text(sql)
    print(f'{len(classes)} classes sincronizadas; {len(catalog["objects"])} objetos locais.')


if __name__ == '__main__':
    main()
