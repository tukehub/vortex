"""Two seamless fields for Vlorë's broad scrub patches and exposed limestone."""
from pathlib import Path

import numpy as np
from PIL import Image
from scipy.ndimage import map_coordinates

from common import OUT


def bake(directory):
    rng = np.random.default_rng(7409)
    coords = np.indices((256, 256)) / 256

    def field():
        values = np.zeros((256, 256))
        for cells, weight in ((5, .45), (12, .30), (33, .17), (78, .08)):
            grid = rng.random((cells, cells))
            values += weight * map_coordinates(grid, coords * cells, order=3, mode='grid-wrap')
        return np.uint8(np.clip(values, 0, 1) * 255)

    vegetation, geology = field(), field()
    fine = field()
    ix = np.arange(256)*7 % 256
    pockets = fine[np.ix_(ix, ix)]
    Image.fromarray(np.dstack((vegetation, geology, pockets))).save(directory / 'ground_macro.png')


if __name__ == '__main__':
    bake(Path(OUT) / 'vlore')
