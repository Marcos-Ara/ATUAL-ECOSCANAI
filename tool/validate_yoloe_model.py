"""Confere labels, task, SHA e, opcionalmente, executa o LiteRT no PC.

python tool/validate_yoloe_model.py --model assets/models/ecoscan_yoloe26n_w8a32.tflite --invoke
"""
import argparse
import hashlib
import json
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def validate_model(model: Path, *, invoke=False):
    payload = model.read_bytes()
    if len(payload) < 1024 or payload[4:8] != b'TFL3':
        raise ValueError('Arquivo LiteRT inválido ou vazio.')
    with zipfile.ZipFile(model) as archive:
        metadata = json.loads(archive.read('metadata.json'))
    expected = [c['label'] for c in json.loads(
        (ROOT / 'assets/data/yoloe_classes.json').read_text())['classes']]
    names = metadata.get('names', {})
    actual = [names[str(i)] for i in range(len(names))]
    if metadata.get('task') != 'detect' or actual != expected:
        raise ValueError('Task ou ordem das classes não corresponde ao catálogo EcoScan.')
    result = dict(file=model.name, sha256=hashlib.sha256(payload).hexdigest(),
                  byte_size=len(payload), task='detect', class_count=len(actual),
                  classes=actual, ultralytics_version=metadata.get('version'),
                  quantization=metadata.get('args', {}).get('quantize'),
                  input_size=metadata.get('imgsz'), smoke_inference=False)
    if invoke:
        import numpy as np
        from ai_edge_litert.interpreter import Interpreter
        runtime = Interpreter(model_path=str(model), num_threads=4)
        runtime.allocate_tensors()
        inputs, outputs = runtime.get_input_details(), runtime.get_output_details()
        if len(inputs) != 1 or len(outputs) != 1:
            raise ValueError('Detector deve ter uma entrada e uma saída.')
        shape = inputs[0]['shape'].tolist()
        height, width = metadata['imgsz']
        if shape not in ([1, 3, height, width], [1, height, width, 3]):
            raise ValueError(f'Entrada incompatível: {shape}')
        if inputs[0]['dtype'] != np.float32:
            raise ValueError('Este app requer entrada float32 normalizada.')
        output_shape = outputs[0]['shape'].tolist()
        if len(output_shape) != 3 or output_shape[1] != 4 + len(expected):
            raise ValueError(f'Saída incompatível: {output_shape}')
        runtime.set_tensor(inputs[0]['index'], np.zeros(shape, dtype=np.float32))
        runtime.invoke()
        if not np.isfinite(runtime.get_tensor(outputs[0]['index'])).all():
            raise ValueError('Inferência retornou valores inválidos.')
        result.update(input_shape=shape, output_shape=output_shape, smoke_inference=True)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--model', required=True, type=Path)
    parser.add_argument('--invoke', action='store_true')
    parser.add_argument('--manifest', type=Path)
    args = parser.parse_args()
    result = validate_model(args.model, invoke=args.invoke)
    text = json.dumps(result, ensure_ascii=False, indent=2) + '\n'
    if args.manifest:
        args.manifest.write_text(text)
    print(text)


if __name__ == '__main__':
    main()
