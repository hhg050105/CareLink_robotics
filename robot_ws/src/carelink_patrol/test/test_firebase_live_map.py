from io import BytesIO

import pytest
from PIL import Image

from carelink_patrol.firebase_live_map import occupancy_grid_to_png


def test_occupancy_grid_to_png_colours_and_vertical_flip():
    png, width, height = occupancy_grid_to_png(
        2, 2,
        [0, 100, -1, 50],
    )
    image = Image.open(BytesIO(png))
    assert (width, height) == (2, 2)
    assert list(image.getdata()) == [205, 127, 254, 0]


def test_occupancy_grid_to_png_rejects_wrong_size():
    with pytest.raises(ValueError):
        occupancy_grid_to_png(2, 2, [0, 100])
