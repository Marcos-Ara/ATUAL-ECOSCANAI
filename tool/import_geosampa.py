"""Converte uma exportação GeoSampa para WGS84 e gera o asset e o SQL.

Uso: python -m pip install pyproj
     python tool/import_geosampa.py /caminho/geoportal_ecoponto.geojson
Não acessa nem altera o Supabase remoto.
"""
import argparse
import json
import re
import unicodedata
from pathlib import Path


def normalize(text):
    return ''.join(c for c in unicodedata.normalize('NFD', text.lower())
                   if unicodedata.category(c) != 'Mn')


def materials(description):
    text = normalize(description)
    result = set()
    if 'reciclaveis secos' in text:
        result.update(['plastic', 'glass', 'paper', 'metal'])
    for material, words in {
        'plastic': ['plastic'], 'glass': ['vidro', 'glass'],
        'paper': ['papel', 'paper'], 'metal': ['metal', 'alumin'],
        'electronic': ['eletron'], 'battery': ['bateria', 'pilha'],
        'organic': ['organico', 'residuos alimentares'],
        'special': ['entulho', 'volumoso', 'gesso'],
    }.items():
        if any(word in text for word in words):
            result.add(material)
    return sorted(result)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('input', type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    data = json.loads(args.input.read_text(encoding='utf-8-sig'))
    crs = data.get('crs', {}).get('properties', {}).get('name', '')
    match = re.search(r'EPSG(?::|::|/0/)(\d+)$', crs)
    code = int(match[1]) if match else 4326
    if crs and not match and 'CRS84' not in crs:
        raise ValueError(f'CRS não suportado: {crs}')
    transform = None
    if code != 4326:
        from pyproj import Transformer
        transform = Transformer.from_crs(code, 4326, always_xy=True)
    rows = []
    seen = set()
    for feature in data['features']:
        if feature['geometry']['type'] != 'Point':
            raise ValueError('A exportação deve conter apenas pontos.')
        lon, lat = feature['geometry']['coordinates'][:2]
        if transform:
            lon, lat = transform.transform(lon, lat)
        if not (-47 < lon < -46 and -24 < lat < -23):
            raise ValueError('Ponto fora da cobertura esperada de São Paulo.')
        lon, lat = round(lon, 8), round(lat, 8)
        feature['geometry']['coordinates'] = [lon, lat]
        p = feature['properties']
        identifier = 'geosampa:' + str(p['cd_identificador_ecoponto'])
        if identifier in seen:
            raise ValueError(f'Identificador duplicado: {identifier}')
        seen.add(identifier)
        desc = ' · '.join(str(p[k]) for k in (
            'tx_recebimento_comum', 'tx_recebimento_diferenciado') if p.get(k))
        rows.append({
            'id': identifier, 'name': p['nm_ecoponto'],
            'latitude': lat, 'longitude': lon, 'address': p.get('nm_endereco'),
            'opening_hours': p.get('tx_atendimento'),
            'accepted_material_ids': materials(desc),
            'accepted_materials_description': desc,
            'district': p.get('nm_distrito'),
            'administrative_area': p.get('nm_subprefeitura'),
            'source': 'geosampa', 'source_url': 'https://geosampa.prefeitura.sp.gov.br/',
        })
    if not rows:
        raise ValueError('Exportação vazia: nenhuma alteração foi gravada.')
    data['crs'] = {'type': 'name', 'properties': {'name': 'urn:ogc:def:crs:OGC:1.3:CRS84'}}
    asset = root / 'assets/data/ecopoints_geosampa.geojson'
    asset.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding='utf-8')
    fields = list(rows[0])
    cols = ','.join(fields)
    types = ','.join(k + ' ' + ('double precision' if k in ('latitude', 'longitude')
        else 'text[]' if k == 'accepted_material_ids' else 'text') for k in fields)
    literal = "'" + json.dumps(rows, ensure_ascii=False, separators=(',', ':')).replace("'", "''") + "'::jsonb"
    update = ','.join(k + '=excluded.' + k for k in fields if k != 'id')
    sql = f'-- {len(rows)} EcoPontos GeoSampa convertidos para WGS84.\n'
    sql += f'insert into public.ecopoints({cols}) select {cols} from jsonb_to_recordset({literal}) as x({types}) on conflict(id) do update set {update},updated_at=now(),is_active=true;\n'
    # Inactivate removed source IDs only when applying this COMPLETE snapshot.
    ids = ','.join("'" + row['id'].replace("'", "''") + "'" for row in rows)
    sql += f"update public.ecopoints set is_active=false, updated_at=now() where source='geosampa' and id not in ({ids});\n"
    (root / 'supabase/migrations/202609290003_ecopoints.sql').write_text(sql, encoding='utf-8')

    material_ids = {
        'plastic': 'plastico', 'paper': 'papel', 'glass': 'vidro',
        'metal': 'metal', 'cardboard': 'papelao', 'organic': 'organico',
        'reject': 'rejeito', 'electronic': 'eletronico',
        'special': 'especial', 'battery': 'pilhas_baterias',
    }
    points_pt = [{
        'ponto_id': row['id'], 'nome': row['name'],
        'categoria': 'reciclagem', 'latitude': row['latitude'],
        'longitude': row['longitude'], 'endereco': row['address'],
        'horario_atendimento': row['opening_hours'],
        'descricao_materiais_aceitos': row['accepted_materials_description'],
        'distrito': row['district'], 'subprefeitura': row['administrative_area'],
        'fonte': row['source'], 'url_fonte': row['source_url'], 'ativo': True,
    } for row in rows]
    cols_pt = list(points_pt[0])
    types_pt = ','.join(
        f"{key} {'double precision' if key in ('latitude','longitude') else 'boolean' if key == 'ativo' else 'text'}"
        for key in cols_pt
    )
    literal_pt = "'" + json.dumps(points_pt, ensure_ascii=False, separators=(',', ':')).replace("'", "''") + "'::jsonb"
    update_pt = ','.join(f'{key}=excluded.{key}' for key in cols_pt if key != 'ponto_id')
    sql_pt = '-- Atualização do catálogo GeoSampa para o esquema em português.\nbegin;\n'
    sql_pt += f'insert into public.pontos_ecologicos({",".join(cols_pt)}) select {",".join(cols_pt)} from jsonb_to_recordset({literal_pt}) as x({types_pt}) on conflict(ponto_id) do update set {update_pt},atualizado_em=now();\n'
    accepted = [
        {'ponto_id': row['id'], 'material_id': material_ids[material]}
        for row in rows for material in row['accepted_material_ids']
        if material in material_ids
    ]
    accepted_literal = "'" + json.dumps(accepted, ensure_ascii=False, separators=(',', ':')).replace("'", "''") + "'::jsonb"
    sql_pt += f'delete from public.materiais_ponto_ecologico where ponto_id in ({ids});\n'
    if accepted:
        sql_pt += f"insert into public.materiais_ponto_ecologico(ponto_id,material_id) select ponto_id,material_id from jsonb_to_recordset({accepted_literal}) as x(ponto_id text,material_id text) on conflict do nothing;\n"
    sql_pt += f"update public.pontos_ecologicos set ativo=false,atualizado_em=now() where fonte='geosampa' and ponto_id not in ({ids});\ncommit;\n"
    migration_dir = root / 'supabase/migrations'
    existing_versions = [
        int(path.name[:12]) for path in migration_dir.glob('*.sql')
        if path.name[:12].isdigit()
    ]
    next_version = max(existing_versions, default=202610160001) + 1
    migration_path = migration_dir / f'{next_version}_ecopontos_atualizacao.sql'
    migration_path.write_text(sql_pt, encoding='utf-8')

    migrations = sorted((root / 'supabase/migrations').glob('*.sql'))
    full = '-- EcoScan AI: instalação inicial consolidada do banco Supabase, em português.\n'
    full += '-- Execute uma vez em um projeto sem tabelas do EcoScan; não rode também as migrações individuais.\nbegin;\n'
    for migration in migrations:
        body = migration.read_text(encoding='utf-8')
        body = re.sub(r'(?im)^\s*(begin|commit)\s*;\s*(?:--[^\r\n]*)?\r?\n', '', body)
        full += f'\n-- >>> MIGRATION {migration.name}\n{body.strip()}\n-- <<< MIGRATION {migration.name}\n'
    full += '\ncommit;\n'
    full += "select 'objetos' as conjunto, count(*) as quantidade from public.objetos;\n"
    full += "select 'pontos_ecologicos_geosampa' as conjunto, count(*) as quantidade from public.pontos_ecologicos where fonte='geosampa' and ativo;\n"
    full += "select public.buscar_objeto_ecoscan('bottle') is null as classe_ambigua_nao_classificada_sozinha;\n"
    (root / 'supabase/ECOSCAN_SUPABASE_NOVO.sql').write_text(full, encoding='utf-8')
    print(f'{len(rows)} EcoPontos validados. Asset e SQL atualizados.')


if __name__ == '__main__':
    main()
