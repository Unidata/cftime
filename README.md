# cftime
Time-handling functionality from netcdf4-python

[![Linux Build Status](https://travis-ci.org/Unidata/cftime.svg?branch=master)](https://travis-ci.org/Unidata/cftime)
[![Windows Build Status](https://ci.appveyor.com/api/projects/status/fl9taa9je4e6wi7n/branch/master?svg=true)](https://ci.appveyor.com/project/jswhit/cftime/branch/master)
[![PyPI package](https://badge.fury.io/py/cftime.svg)](http://python.org/pypi/cftime)
[![Coverage Status](https://coveralls.io/repos/github/Unidata/cftime/badge.svg?branch=master)](https://coveralls.io/github/Unidata/cftime?branch=master)
[![Tag Status](https://img.shields.io/github/tag/UniData/cftime.svg)](https://github.com/Unidata/cftime/tags)
[![Release Status](https://img.shields.io/github/release/UniData/cftime.svg)](https://github.com/Unidata/cftime/releases)
[![Commits Status](https://img.shields.io/github/commits-since/UniData/cftime/latest.svg)](https://github.com/UniData/cftime/commits/master)

## News
For details on the latest updates, see the [Changelog](https://github.com/Unidata/cftime/blob/master/Changelog).

3/16/2020:  version 1.1.1 released.  Fix bug in microsecond formatting, ensure identical num2date results if input is an array of times, or a single scalar ([issue #143](https://github.com/Unidata/cftime/issues/143)).

2/12/2020:  version 1.1.0 released.  `cftime.datetime` instances are returned by default from `num2date`
(instead of returning python datetime instances where possible ([issue #136](https://github.com/Unidata/cftime/issues/136))).  `num2pydate`
convenience function added (always returns python datetime instances, [issue #134](https://github.com/Unidata/cftime/issues/134)). Fix for
fraction seconds in reference date string ([issue #140](https://github.com/Unidata/cftime/issues/140)). Added `daysinmonth` attribute 
([issue #137](https://github.com/Unidata/cftime/issues/137)).

10/25/2019:  version 1.0.4.2 released (fix for [issue #126](https://github.com/Unidata/cftime/issues/126)).

10/21/2019:  version 1.0.4 released.

12/05/2018:  version 1.0.3.4 released (just to fix a problem with the source 
tarball on pypi).

12/05/2018:  version 1.0.3.1 released.  Bugfix release (fixed issue with installation
when cython not installed, regression on 32-bit platforms, workaround for pandas 
compatibility).

12/01/2018:  version 1.0.3 released. Test coverage with coveralls.io, improved round-tripping accuracy for non-real world calendars (like `360_day`).

10/27/2018:  version 1.0.2 released. Improved accuracy (from approximately 1000 microseconds to 10 microseconds on x86
platforms). Refactored calendar calculations now allow for negative reference years. num2date function now more than an
order of magnitude faster. `months since` units now allowed, but only for `360_day` calendar.

08/15/2018:  version 1.0.1 released.

11/8/2016: `cftime` was split out of the [netcdf4-python](https://github.com/Unidata/netcdf4-python) package.

## Quick Start
* Clone GitHub repository (`git clone https://github.com/Unidata/cftime.git`), or get source tarball from [PyPI](https://pypi.python.org/pypi/cftime). Links to Windows and OS X precompiled binary packages are also available on [PyPI](https://pypi.python.org/pypi/cftime).

* Make sure [numpy](http://www.numpy.org/) and [Cython](http://cython.org/) are
  installed and you have [Python](https://www.python.org) 2.7 or newer.

* Run `python setup.py build`, then `python setup.py install` (with `sudo` if necessary).

* To run all the tests, execute `py.test`.

## Documentation
See the online [docs](http://unidata.github.io/cftime) for more details.
