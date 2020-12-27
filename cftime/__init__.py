# When importing from the root of the unpacked tarball or git checkout,
# Python sees the "cftime" source directory and tries to load it, which fails.
# (unless the package was built using "python setup.py build_ext --inplace"
# so that _cftime.so exists in the cftime source dir).
try:
    # init for cftime package
    from ._cftime import datetime
except ImportError:
    import os.path as _op
    if _op.exists(_op.join(_op.dirname(__file__), '..', 'setup.py')):
        msg="You cannot import cftime from inside the install directory.\nChange to another directory first."
        raise ImportError(msg)
    else:
        raise
from ._cftime import utime, JulianDayFromDate, DateFromJulianDay, UNIT_CONVERSION_FACTORS
from ._cftime import _parse_date, date2index, time2index, real_datetime
from ._cftime import DatetimeNoLeap, DatetimeAllLeap, Datetime360Day, DatetimeJulian, \
                     DatetimeGregorian, DatetimeProlepticGregorian
from ._cftime import microsec_units, millisec_units, \
                     sec_units, hr_units, day_units, min_units
from ._cftime import num2date, date2num, date2index, num2pydate
from ._cftime import __version__
