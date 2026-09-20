import hashlib
from types import SimpleNamespace
from unittest.mock import Mock

import pytest
from PIL import Image

from carelink_patrol.fixed_map_upload import load_map, upload_verified


def test_saved_map_preserves_version_coordinates_and_png(tmp_path):
    image = tmp_path / 'map.pgm'
    Image.new('L', (4, 3), 254).save(image)
    metadata = tmp_path / 'map.yaml'
    metadata.write_text('image: map.pgm\nresolution: 0.05\norigin: [-1, -2, 0]\nnegate: 0\nfree_thresh: 0.196\n')
    payload, info = load_map(metadata)
    assert payload['mapVersion'] == hashlib.sha256(
        metadata.read_bytes() + b'\0' + image.read_bytes()).hexdigest()
    assert payload['origin'] == [-1., -2., 0.]
    assert (payload['width'], payload['height']) == (4, 3)
    assert info['pixels'] == [254] * 12
    assert info['version'] == payload['mapVersion']
    assert payload['pixelOrigin'] == 'top_left'


def snapshot(payload):
    return SimpleNamespace(exists=True, to_dict=lambda: payload)


def test_network_failure_retries_and_verifies():
    doc = Mock()
    payload = {'mapVersion': 'new', 'imageBase64': 'image'}
    doc.set.side_effect = [TimeoutError('offline'), None]
    doc.get.return_value = snapshot(payload)
    sleep = Mock()
    upload_verified(doc, payload, 'timestamp', sleep=sleep, report=Mock())
    assert doc.set.call_count == 2
    sleep.assert_called_once_with(2)
    doc.get.assert_called_once_with(timeout=10., retry=None)


def test_wrong_image_readback_is_not_success():
    doc = Mock()
    doc.get.return_value = snapshot({'mapVersion': 'new', 'imageBase64': 'old'})
    with pytest.raises(RuntimeError, match='readback'):
        upload_verified(doc, {'mapVersion': 'new', 'imageBase64': 'new'},
                        'timestamp', attempts=2, sleep=Mock(), report=Mock())
    assert doc.set.call_count == 2


def test_permanent_failure_propagates_after_last_attempt():
    doc = Mock()
    doc.set.side_effect = TimeoutError('offline')
    sleep = Mock()
    with pytest.raises(TimeoutError):
        upload_verified(doc, {}, 'timestamp', attempts=3, sleep=sleep, report=Mock())
    assert doc.set.call_count == 3
    assert sleep.call_count == 2
    doc.get.assert_not_called()
