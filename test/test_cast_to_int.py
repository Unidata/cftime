import numpy as np

from cftime._cftime import cast_to_int


def test_cast_to_int():
    assert 1 == cast_to_int(np.longdouble(1))
