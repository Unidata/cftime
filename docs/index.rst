cftime
======

Python library for decoding time units and variable values in a netCDF file
conforming to the `Climate and Forecasting (CF) netCDF conventions <http://cfconventions.org/cf-conventions/cf-conventions#time-coordinate>`__.

Example
-------

Convert numeric time coordinates to dates with :func:`cftime.num2date`,
and convert dates back to numeric coordinates with :func:`cftime.date2num`.
The units specify both a time interval and a reference date::

    >>> import cftime
    >>> units = 'common_years since 0347-01-01'
    >>> date = cftime.num2date(1, units, calendar='noleap')
    >>> (date.year, date.month, date.day)
    (348, 1, 1)
    >>> int(cftime.date2num(date, units, calendar='noleap'))
    1

``noleap`` and ``365_day`` are names for the same calendar, in which every
year has 365 days. Either name can be used with ``common_years`` units.
Include the day in the reference date (``0347-01-01``, not ``0347-01``).

Contents
--------

.. toctree::
   :maxdepth: 2

   installing
   api

Indices and tables
------------------

* :ref:`genindex`
* :ref:`modindex`
* :ref:`search`
