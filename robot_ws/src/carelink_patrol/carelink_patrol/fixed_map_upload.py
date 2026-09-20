"""Upload saved maps independently of ROS startup, with retries and readback."""
import argparse
import base64
import hashlib
import io
import time
from pathlib import Path


def load_map(yaml_path):
    import yaml
    from PIL import Image
    yaml_path = Path(yaml_path).expanduser()
    yaml_bytes = yaml_path.read_bytes()
    metadata = yaml.safe_load(yaml_bytes)
    image_bytes = (yaml_path.parent / str(metadata['image'])).read_bytes()
    with Image.open(io.BytesIO(image_bytes)) as image:
        grayscale = image.convert('L')
        width, height = grayscale.size
        pixels = list(grayscale.getdata())
        output = io.BytesIO()
        grayscale.save(output, format='PNG', optimize=True)
    if len(output.getvalue()) > 700_000:
        raise ValueError('Map PNG exceeds the safe Firestore document size')
    version = hashlib.sha256(yaml_bytes + b'\0' + image_bytes).hexdigest()
    origin = [float(value) for value in metadata['origin']]
    payload = {
        'imageBase64': base64.b64encode(output.getvalue()).decode('ascii'),
        'imageMimeType': 'image/png', 'width': width, 'height': height,
        'resolution': float(metadata['resolution']), 'origin': origin,
        'frameId': 'map', 'source': 'fixed_map', 'mapVersion': version,
        'pixelOrigin': 'top_left', 'pixelXDirection': 'right',
        'pixelYDirection': 'down',
    }
    info = dict(width=width, height=height, resolution=payload['resolution'],
                origin=origin, negate=int(metadata.get('negate', 0)),
                free_thresh=float(metadata.get('free_thresh', 0.196)),
                pixels=pixels, version=version)
    return payload, info


def upload_verified(document, payload, timestamp, attempts=5, report=print,
                    sleep=time.sleep):
    if attempts < 1:
        raise ValueError('attempts must be positive')
    for attempt in range(1, attempts + 1):
        try:
            document.set(dict(payload, updatedAt=timestamp), merge=True,
                         timeout=10.0, retry=None)
            snapshot = document.get(timeout=10.0, retry=None)
            stored = snapshot.to_dict() or {}
            if not snapshot.exists or any(stored.get(k) != v for k, v in payload.items()):
                raise RuntimeError('Firebase map readback does not match the saved map')
            return
        except Exception as error:
            report(f'Firebase map upload attempt {attempt}/{attempts} failed: {error}')
            if attempt == attempts:
                raise
            sleep(min(2 ** attempt, 10))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('map_yaml')
    parser.add_argument('--credential', default='/home/carelink/camera_stack/secrets/firebase-service-account.json')
    parser.add_argument('--document', default='robot_maps/main')
    parser.add_argument('--attempts', type=int, default=5)
    args = parser.parse_args()
    try:
        from firebase_admin import credentials, firestore
        import firebase_admin
        payload, info = load_map(args.map_yaml)
        if not firebase_admin._apps:
            firebase_admin.initialize_app(credentials.Certificate(args.credential))
        document = firestore.client().document(args.document)
        upload_verified(document, payload, firestore.SERVER_TIMESTAMP,
                        attempts=args.attempts, report=lambda msg: print(msg, flush=True))
        print(f'Firebase map upload verified: {args.document}, version={info["version"]}', flush=True)
    except Exception as error:
        parser.exit(1, f'Firebase map upload failed; local map is retained: {error}\n')


if __name__ == '__main__':
    main()
