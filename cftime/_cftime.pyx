"""
Performs conversions of netCDF time coordinate data to/from datetime objects.
"""

from cpython.object cimport (PyObject_RichCompare, Py_LT, Py_LE, Py_EQ,
                             Py_NE, Py_GT, Py_GE)
from numpy cimport int64_t, int32_t
import cython
import numpy as np
import re
import sys
import time
from datetime import datetime as datetime_python
from datetime import timedelta, MINYEAR
import time                     # strftime
try:
    from itertools import izip as zip
except ImportError:  # python 3.x
    pass


microsec_units = ['microseconds','microsecond', 'microsec', 'microsecs']
millisec_units = ['milliseconds', 'millisecond', 'millisec', 'millisecs', 'msec', 'msecs', 'ms']
sec_units =      ['second', 'seconds', 'sec', 'secs', 's']
min_units =      ['minute', 'minutes', 'min', 'mins']
hr_units =       ['hour', 'hours', 'hr', 'hrs', 'h']
day_units =      ['day', 'days', 'd']
month_units =    ['month', 'months'] # only allowed for 360_day calendar
_units = microsec_units+millisec_units+sec_units+min_units+hr_units+day_units
# supported calendars. Includes synonyms ('standard'=='gregorian',
# '366_day'=='all_leap','365_day'=='noleap')
# see http://cfconventions.org/cf-conventions/cf-conventions.html#calendar
# for definitions.
_calendars = ['standard', 'gregorian', 'proleptic_gregorian',
              'noleap', 'julian', 'all_leap', '365_day', '366_day', '360_day']
# Following are number of Days Per Month
cdef int[12] _dpm      = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
cdef int[12] _dpm_leap = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
cdef int[12] _dpm_360  = [30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30]
# Same as above, but SUM of previous months (no leap years).
cdef int[13] _spm_365day = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334, 365]
cdef int[13] _spm_366day = [0, 31, 60, 91, 121, 152, 182, 213, 244, 274, 305, 335, 366]

# Slightly more performant cython lookups than a 2D table
# The first 12 entries correspond to month lengths for non-leap years.
# The remaining 12 entries give month lengths for leap years
cdef int32_t* days_per_month_array = [
    31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31,
    31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]

# Reverse operator lookup for datetime.__richcmp__
_rop_lookup = {Py_LT: '__gt__', Py_LE: '__ge__', Py_EQ: '__eq__',
               Py_GT: '__lt__', Py_GE: '__le__', Py_NE: '__ne__'}

__version__ = '1.1.1.2'

# Adapted from http://delete.me.uk/2005/03/iso8601.html
# Note: This regex ensures that all ISO8601 timezone formats are accepted - but, due to legacy support for other timestrings, not all incorrect formats can be rejected.
#       For example, the TZ spec "+01:0" will still work even though the minutes value is only one character long.
ISO8601_REGEX = re.compile(r"(?P<year>[+-]?[0-9]{1,4})(-(?P<month>[0-9]{1,2})(-(?P<day>[0-9]{1,2})"
                           r"(((?P<separator1>.)(?P<hour>[0-9]{1,2}):(?P<minute>[0-9]{1,2})(:(?P<second>[0-9]{1,2})(\.(?P<fraction>[0-9]+))?)?)?"
                           r"((?P<separator2>.?)(?P<timezone>Z|(([-+])([0-9]{2})((:([0-9]{2}))|([0-9]{2}))?)))?)?)?)?"
                           )
# Note: The re module apparently does not support branch reset groups that allow redifinition of the same group name in alternative branches as PCRE does.
#       Using two different group names is also somewhat ugly, but other solutions might hugely inflate the expression. feel free to contribute a better solution.
TIMEZONE_REGEX = re.compile(
    "(?P<prefix>[+-])(?P<hours>[0-9]{2})(?:(?::(?P<minutes1>[0-9]{2}))|(?P<minutes2>[0-9]{2}))?")


# Taken from pandas ccalendar.pyx
@cython.wraparound(False)
@cython.boundscheck(False)
cpdef int32_t get_days_in_month(bint isleap, int month) nogil:
    """
    Return the number of days in the given month of the given year.
    Parameters
    ----------
    leap : int [0,1]
    month : int

    Returns
    -------
    days_in_month : int
    Notes
    -----
    Assumes that the arguments are valid.  Passing a month not between 1 and 12
    risks a segfault.
    """
    return days_per_month_array[12 * isleap + month - 1]


class real_datetime(datetime_python):
    """add dayofwk, dayofyr attributes to python datetime instance"""
    @property
    def dayofwk(self):
        # 0=Monday, 6=Sunday
        return self.weekday()
    @property
    def dayofyr(self):
        return self.timetuple().tm_yday
    nanosecond = 0 # workaround for pandas bug (cftime issue #77)

# start of the gregorian calendar
gregorian = real_datetime(1582,10,15)

def _datesplit(timestr):
    """split a time string into two components, units and the remainder
    after 'since'
    """
    try:
        (units, sincestring, remainder) = timestr.split(None,2)
    except ValueError as e:
        raise ValueError('Incorrectly formatted CF date-time unit_string')

    if sincestring.lower() != 'since':
        raise ValueError("no 'since' in unit_string")

    return units.lower(), remainder

def _dateparse(timestr):
    """parse a string of the form time-units since yyyy-mm-dd hh:mm:ss,
    return a datetime instance"""
    # same as version in cftime, but returns a timezone naive
    # python datetime instance with the utc_offset included.

    (units, isostring) = _datesplit(timestr)

    # parse the date string.
    year, month, day, hour, minute, second, microsecond, utc_offset =\
        _parse_date( isostring.strip() )
    if year >= MINYEAR:
        basedate = real_datetime(year, month, day, hour, minute, second,
                microsecond)
        # subtract utc_offset from basedate time instance (which is timezone naive)
        basedate -= timedelta(days=utc_offset/1440.)
    else:
        if not utc_offset:
            basedate = datetime(year, month, day, hour, minute, second,
                    microsecond)
        else:
            raise ValueError('cannot use utc_offset for reference years <= 0')
    return basedate

def _round_half_up(x):
    # 'round half up' so 0.5 rounded to 1 (instead of 0 as in numpy.round)
    return np.ceil(np.floor(2.*x)/2.)

cdef _parse_date_and_units(timestr,calendar='standard'):
    """parse a string of the form time-units since yyyy-mm-dd hh:mm:ss
    return a tuple (units,utc_offset, datetimeinstance)"""
    (units, isostring) = _datesplit(timestr)
    if not ((units in month_units and calendar=='360_day') or units in _units):
        if units in month_units and calendar != '360_day':
            raise ValueError("'months since' units only allowed for '360_day' calendar")
        else:
            raise ValueError(
            "units must be one of 'seconds', 'minutes', 'hours' or 'days' (or singular version of these), got '%s'" % units)
    # parse the date string.
    year, month, day, hour, minute, second, microsecond, utc_offset = _parse_date(
        isostring.strip())
    return units, utc_offset, datetime(year, month, day, hour, minute, second)


def date2num(dates,units,calendar='standard'):
        """date2num(dates,units,calendar='standard')

    Return numeric time values given datetime objects. The units
    of the numeric time values are described by the `units` argument
    and the `calendar` keyword. The datetime objects must
    be in UTC with no time-zone offset.  If there is a
    time-zone offset in `units`, it will be applied to the
    returned numeric values.

    **`dates`**: A datetime object or a sequence of datetime objects.
    The datetime objects should not include a time-zone offset.

    **`units`**: a string of the form `<time units> since <reference time>`
    describing the time units. `<time units>` can be days, hours, minutes,
    seconds, milliseconds or microseconds. `<reference time>` is the time
    origin. `months_since` is allowed *only* for the `360_day` calendar.

    **`calendar`**: describes the calendar used in the time calculations.
    All the values currently defined in the
    [CF metadata convention](http://cfconventions.org)
    Valid calendars `'standard', 'gregorian', 'proleptic_gregorian'
    'noleap', '365_day', '360_day', 'julian', 'all_leap', '366_day'`.
    Default is `'standard'`, which is a mixed Julian/Gregorian calendar.

    returns a numeric time value, or an array of numeric time values
    with approximately 100 microsecond accuracy.
        """
        calendar = calendar.lower()
        basedate = _dateparse(units)
        (unit, ignore) = _datesplit(units)
        # real-world calendars limited to positive reference years.
        if calendar in ['julian', 'standard', 'gregorian', 'proleptic_gregorian']:
            if basedate.year == 0:
                msg='zero not allowed as a reference year, does not exist in Julian or Gregorian calendars'
                raise ValueError(msg)

        if (calendar == 'proleptic_gregorian' and basedate.year >= MINYEAR) or \
           (calendar in ['gregorian','standard'] and basedate > gregorian):
            # use python datetime module,
            isscalar = False
            try:
                dates[0]
            except:
                isscalar = True
            if isscalar:
                dates = np.array([dates])
            else:
                dates = np.array(dates)
                shape = dates.shape
            ismasked = False
            if np.ma.isMA(dates) and np.ma.is_masked(dates):
                mask = dates.mask
                ismasked = True
            times = []
            for date in dates.flat:
                if getattr(date, 'tzinfo',None) is not None:
                    date = date.replace(tzinfo=None) - date.utcoffset()

                if ismasked and not date:
                    times.append(None)
                else:
                    td = date - basedate
                    # total time in microseconds.
                    totaltime = td.microseconds + (td.seconds + td.days * 24 * 3600) * 1.e6
                    if unit in microsec_units:
                        times.append(totaltime)
                    elif unit in millisec_units:
                        times.append(totaltime/1.e3)
                    elif unit in sec_units:
                        times.append(totaltime/1.e6)
                    elif unit in min_units:
                        times.append(totaltime/1.e6/60)
                    elif unit in hr_units:
                        times.append(totaltime/1.e6/3600)
                    elif unit in day_units:
                        times.append(totaltime/1.e6/3600./24.)
                    else:
                        raise ValueError('unsupported time units')
            if isscalar:
                return times[0]
            else:
                return np.reshape(np.array(times), shape)
        else: # use cftime module for other calendars
            cdftime = utime(units,calendar=calendar)
            return cdftime.date2num(dates)


def num2pydate(times,units,calendar='standard'):
    """num2pydate(times,units,calendar='standard')
    Always returns python datetime.datetime
    objects and raise an error if this is not possible.

    Same as
    num2date(times,units,calendar,only_use_cftime_datetimes=False,only_use_python_datetimes=True)
    """
    return num2date(times,units,calendar,only_use_cftime_datetimes=False,only_use_python_datetimes=True)

def num2date(times,units,calendar='standard',\
             only_use_cftime_datetimes=True,only_use_python_datetimes=False):
    """num2date(times,units,calendar='standard',only_use_cftime_datetimes=True,only_use_python_datetimes=False)

    Return datetime objects given numeric time values. The units
    of the numeric time values are described by the `units` argument
    and the `calendar` keyword. The returned datetime objects represent
    UTC with no time-zone offset, even if the specified
    `units` contain a time-zone offset.

    **`times`**: numeric time values.

    **`units`**: a string of the form `<time units> since <reference time>`
    describing the time units. `<time units>` can be days, hours, minutes,
    seconds, milliseconds or microseconds. `<reference time>` is the time
    origin. `months_since` is allowed *only* for the `360_day` calendar.

    **`calendar`**: describes the calendar used in the time calculations.
    All the values currently defined in the
    [CF metadata convention](http://cfconventions.org)
    Valid calendars `'standard', 'gregorian', 'proleptic_gregorian'
    'noleap', '365_day', '360_day', 'julian', 'all_leap', '366_day'`.
    Default is `'standard'`, which is a mixed Julian/Gregorian calendar.

    **`only_use_cftime_datetimes`**: if False, python datetime.datetime
    objects are returned from num2date where possible; if True dates which
    subclass cftime.datetime are returned for all calendars. Default `True`.

    **`only_use_python_datetimes`**: always return python datetime.datetime
    objects and raise an error if this is not possible. Ignored unless
    `only_use_cftime_datetimes=False`. Default `False`.

    returns a datetime instance, or an array of datetime instances with
    approximately 100 microsecond accuracy.

    ***Note***: If only_use_cftime_datetimes=False and
    use_only_python_datetimes=False, the datetime instances
    returned are 'real' python datetime
    objects if `calendar='proleptic_gregorian'`, or
    `calendar='standard'` or `'gregorian'`
    and the date is after the breakpoint between the Julian and
    Gregorian calendars (1582-10-15). Otherwise, they are ctime.datetime
    objects which support some but not all the methods of native python
    datetime objects. The datetime instances
    do not contain a time-zone offset, even if the specified `units`
    contains one.
    """
    calendar = calendar.lower()
    basedate = _dateparse(units)

    can_use_python_datetime=\
      ((calendar == 'proleptic_gregorian' and basedate.year >= MINYEAR) or \
       (calendar in ['gregorian','standard'] and basedate > gregorian))
    if not only_use_cftime_datetimes and only_use_python_datetimes:
        if not can_use_python_datetime:
            msg='illegal calendar or reference date for python datetime'
            raise ValueError(msg)

    (unit, ignore) = _datesplit(units)

    # real-world calendars limited to positive reference years.
    if calendar in ['julian', 'standard', 'gregorian', 'proleptic_gregorian']:
        if basedate.year == 0:
            msg='zero not allowed as a reference year, does not exist in Julian or Gregorian calendars'
            raise ValueError(msg)

    if only_use_cftime_datetimes or not \
       (only_use_python_datetimes and can_use_python_datetime):
        cdftime = utime(units, calendar=calendar,
                        only_use_cftime_datetimes=only_use_cftime_datetimes)
        return cdftime.num2date(times)
    else: # use python datetime module
        isscalar = False
        try:
            times[0]
        except:
            isscalar = True
        if isscalar:
            times = np.array([times],dtype='d')
        else:
            times = np.array(times, dtype='d')
            shape = times.shape
        ismasked = False
        if np.ma.isMA(times) and np.ma.is_masked(times):
            mask = times.mask
            ismasked = True
        dates = []
        for time in times.flat:
            if ismasked and not time:
                dates.append(None)
            else:
                # convert to total seconds
                if unit in microsec_units:
                    tsecs = time/1.e6
                elif unit in millisec_units:
                    tsecs = time/1.e3
                elif unit in sec_units:
                    tsecs = time
                elif unit in min_units:
                    tsecs = time*60.
                elif unit in hr_units:
                    tsecs = time*3600.
                elif unit in day_units:
                    tsecs = time*86400.
                else:
                    raise ValueError('unsupported time units')
                # compute time delta.
                days = tsecs // 86400.
                msecsd = tsecs*1.e6 - days*86400.*1.e6
                secs = msecsd // 1.e6
                msecs = np.round(msecsd - secs*1.e6)
                td = timedelta(days=days,seconds=secs,microseconds=msecs)
                # add time delta to base date.
                try:
                    date = basedate + td
                except OverflowError:
                    msg="""
OverflowError in python datetime, probably because year < datetime.MINYEAR"""
                    raise ValueError(msg)
                dates.append(date)
        if isscalar:
            return dates[0]
        else:
            return np.reshape(np.array(dates), shape)


def date2index(dates, nctime, calendar=None, select='exact'):
    """date2index(dates, nctime, calendar=None, select='exact')

    Return indices of a netCDF time variable corresponding to the given dates.

    **`dates`**: A datetime object or a sequence of datetime objects.
    The datetime objects should not include a time-zone offset.

    **`nctime`**: A netCDF time variable object. The nctime object must have a
    `units` attribute.

    **`calendar`**: describes the calendar used in the time calculations.
    All the values currently defined in the
    [CF metadata convention](http://cfconventions.org)
    Valid calendars `'standard', 'gregorian', 'proleptic_gregorian'
    'noleap', '365_day', '360_day', 'julian', 'all_leap', '366_day'`.
    Default is `'standard'`, which is a mixed Julian/Gregorian calendar.
    If `calendar` is None, its value is given by `nctime.calendar` or
    `standard` if no such attribute exists.

    **`select`**: `'exact', 'before', 'after', 'nearest'`
    The index selection method. `exact` will return the indices perfectly
    matching the dates given. `before` and `after` will return the indices
    corresponding to the dates just before or just after the given dates if
    an exact match cannot be found. `nearest` will return the indices that
    correspond to the closest dates.

    returns an index (indices) of the netCDF time variable corresponding
    to the given datetime object(s).
    """
    try:
        nctime.units
    except AttributeError:
        raise AttributeError("netcdf time variable is missing a 'units' attribute")
    if calendar == None:
        calendar = getattr(nctime, 'calendar', 'standard')
    calendar = calendar.lower()
    basedate = _dateparse(nctime.units)
    # real-world calendars limited to positive reference years.
    if calendar in ['julian', 'standard', 'gregorian', 'proleptic_gregorian']:
        if basedate.year == 0:
            msg='zero not allowed as a reference year, does not exist in Julian or Gregorian calendars'
            raise ValueError(msg)

    if (calendar == 'proleptic_gregorian' and basedate.year >= MINYEAR) or \
       (calendar in ['gregorian','standard'] and basedate > gregorian):
        # use python datetime
        times = date2num(dates,nctime.units,calendar=calendar)
        return time2index(times, nctime, calendar, select)
    else: # use cftime module for other cases
        return _date2index(dates, nctime, calendar, select)


def JulianDayFromDate(date, calendar='standard'):
    """JulianDayFromDate(date, calendar='standard')

    creates a Julian Day from a 'datetime-like' object.  Returns the fractional
    Julian Day (approximately 100 microsecond accuracy).

    if calendar='standard' or 'gregorian' (default), Julian day follows Julian
    Calendar on and before 1582-10-5, Gregorian calendar after 1582-10-15.

    if calendar='proleptic_gregorian', Julian Day follows gregorian calendar.

    if calendar='julian', Julian Day follows julian calendar.
    """

    # check if input was scalar and change return accordingly
    isscalar = False
    try:
        date[0]
    except:
        isscalar = True

    date = np.atleast_1d(np.array(date))
    year = np.empty(len(date), dtype=np.int32)
    month = year.copy()
    day = year.copy()
    hour = year.copy()
    minute = year.copy()
    second = year.copy()
    microsecond = year.copy()
    jd = np.empty(year.shape, np.longdouble)
    cdef long double[:] jd_view = jd
    cdef Py_ssize_t i_max = len(date)
    cdef Py_ssize_t i
    for i in range(i_max):
        d = date[i]
        if getattr(d, 'tzinfo', None) is not None:
            d = d.replace(tzinfo=None) - d.utcoffset()

        year[i] = d.year
        month[i] = d.month
        day[i] = d.day
        hour[i] = d.hour
        minute[i] = d.minute
        second[i] = d.second
        microsecond[i] = d.microsecond
        jd_view[i] = <double>_IntJulianDayFromDate(<int>year[i],<int>month[i],<int>day[i],calendar)

    # at this point jd is an integer representing noon UTC on the given
    # year,month,day.
    # compute fractional day from hour,minute,second,microsecond
    fracday = hour / 24.0 + minute / 1440.0 + (second + microsecond/1.e6) / 86400.0
    jd = jd - 0.5 + fracday

    if isscalar:
        return jd[0]
    else:
        return jd

def DateFromJulianDay(JD, calendar='standard', only_use_cftime_datetimes=True,
                      return_tuple=False):
    """

    returns a 'datetime-like' object given Julian Day. Julian Day is a
    fractional day with approximately 100 microsecond accuracy.

    if calendar='standard' or 'gregorian' (default), Julian day follows Julian
    Calendar on and before 1582-10-5, Gregorian calendar after  1582-10-15.

    if calendar='proleptic_gregorian', Julian Day follows gregorian calendar.

    if calendar='julian', Julian Day follows julian calendar.

    If only_use_cftime_datetimes is set to True, then cftime.datetime
    objects are returned for all calendars.  Otherwise the datetime object is a
    native python datetime object if the date falls in the Gregorian calendar
    (i.e. calendar='proleptic_gregorian', or  calendar = 'standard'/'gregorian'
    and the date is after 1582-10-15).
    """

    julian = np.atleast_1d(np.array(JD, dtype=np.longdouble))

    def getdateinfo(julian):
        # get the day (Z) and the fraction of the day (F)
        # use 'round half up' rounding instead of numpy's even rounding
        # so that 0.5 is rounded to 1.0, not 0 (cftime issue #49)
        Z = np.atleast_1d(np.int32(_round_half_up(julian)))
        F = (julian + 0.5 - Z).astype(np.longdouble)

        cdef Py_ssize_t i_max = len(Z)
        year = np.empty(i_max, dtype=np.int32)
        month = np.empty(i_max, dtype=np.int32)
        day = np.empty(i_max, dtype=np.int32)
        dayofyr = np.zeros(i_max,dtype=np.int32)
        dayofwk = np.zeros(i_max,dtype=np.int32)
        cdef int ijd
        cdef Py_ssize_t i
        for i in range(i_max):
            ijd = Z[i]
            year[i],month[i],day[i],dayofwk[i],dayofyr[i] = _IntJulianDayToDate(ijd,calendar)

        if calendar in ['standard', 'gregorian']:
            ind_before = np.where(julian < 2299160.5)
            ind_before = np.asarray(ind_before).any()
        else:
            ind_before = False

        # compute hour, minute, second, microsecond, convert to int32
        hour = np.clip((F * 24.).astype(np.int64), 0, 23)
        F   -= hour / 24.
        minute = np.clip((F * 1440.).astype(np.int64), 0, 59)
        second = np.clip((F - minute / 1440.) * 86400., 0, None)
        microsecond = (second % 1)*1.e6
        hour = hour.astype(np.int32)
        minute = minute.astype(np.int32)
        second = second.astype(np.int32)
        microsecond = microsecond.astype(np.int32)

        return year,month,day,hour,minute,second,microsecond,dayofyr,dayofwk,ind_before

    year,month,day,hour,minute,second,microsecond,dayofyr,dayofwk,ind_before =\
    getdateinfo(julian)
    # round to nearest second if within ms_eps microseconds
    # (to avoid ugly errors in datetime formatting - alternative
    # to adding small offset all the time as was done previously)
    # see netcdf4-python issue #433 and cftime issue #78
    # this is done by rounding microsends up or down, then
    # recomputing year,month,day etc
    # ms_eps is proportional to julian day,
    # about 47 microseconds in 2000 for Julian base date in -4713
    ms_eps = np.atleast_1d(np.array(np.finfo(np.float64).eps,np.longdouble))
    ms_eps = 86400000000.*np.maximum(ms_eps*julian, ms_eps)
    microsecond = np.where(microsecond < ms_eps, 0, microsecond)
    indxms = microsecond > 1000000-ms_eps
    if indxms.any():
        julian[indxms] = julian[indxms] + 2*ms_eps[indxms]/86400000000.
        year[indxms],month[indxms],day[indxms],hour[indxms],minute[indxms],second[indxms],microsecond2,dayofyr[indxms],dayofwk[indxms],ind_before2 =\
        getdateinfo(julian[indxms])
        microsecond[indxms] = 0

    # check if input was scalar and change return accordingly
    isscalar = False
    try:
        JD[0]
    except:
        isscalar = True

    is_real_dateime = False
    if calendar == 'proleptic_gregorian':
        # datetime.datetime does not support years < 1
        #if year < 0:
        if only_use_cftime_datetimes:
            datetime_type = DatetimeProlepticGregorian
        else:
            if (year < 0).any(): # netcdftime issue #28
               datetime_type = DatetimeProlepticGregorian
            else:
               is_real_datetime = True
               datetime_type = real_datetime
    elif calendar in ('standard', 'gregorian'):
        # return a 'real' datetime instance if calendar is proleptic
        # Gregorian or Gregorian and all dates are after the
        # Julian/Gregorian transition
        if ind_before and not only_use_cftime_datetimes:
            is_real_datetime = True
            datetime_type = real_datetime
        else:
            is_real_datetime = False
            datetime_type = DatetimeGregorian
    elif calendar == "julian":
        datetime_type = DatetimeJulian
    elif calendar in ["noleap","365_day"]:
        datetime_type = DatetimeNoLeap
    elif calendar in ["all_leap","366_day"]:
        datetime_type = DatetimeAllLeap
    elif calendar == "360_day":
        datetime_type = Datetime360Day
    else:
        raise ValueError("unsupported calendar: {0}".format(calendar))

    if not isscalar:
        if return_tuple:
            return np.array([args for args in
                            zip(year, month, day, hour, minute, second,
                                microsecond,dayofwk,dayofyr)])
        else:
            if is_real_datetime:
                return np.array([datetime_type(*args)
                                 for args in
                                 zip(year, month, day, hour, minute, second,
                                     microsecond)])
            else:
                return np.array([datetime_type(*args)
                                 for args in
                                 zip(year, month, day, hour, minute, second,
                                     microsecond,dayofwk,dayofyr)])

    else:
        if return_tuple:
            return (year[0], month[0], day[0], hour[0],
                    minute[0], second[0], microsecond[0],
                    dayofwk[0], dayofyr[0])
        else:
            if is_real_datetime:
                return datetime_type(year[0], month[0], day[0], hour[0],
                                     minute[0], second[0], microsecond[0])
            else:
                return datetime_type(year[0], month[0], day[0], hour[0],
                                     minute[0], second[0], microsecond[0],
                                     dayofwk[0], dayofyr[0])

class utime:

    """
Performs conversions of netCDF time coordinate
data to/from datetime objects.

To initialize: C{t = utime(unit_string,calendar='standard')}

where

B{C{unit_string}} is a string of the form
C{'time-units since <time-origin>'} defining the time units.

Valid time-units are days, hours, minutes and seconds (the singular forms
are also accepted). An example unit_string would be C{'hours
since 0001-01-01 00:00:00'}. months is allowed as a time unit
*only* for the 360_day calendar.

The B{C{calendar}} keyword describes the calendar used in the time calculations.
All the values currently defined in the U{CF metadata convention
<http://cf-pcmdi.llnl.gov/documents/cf-conventions/1.1/cf-conventions.html#time-coordinate>}
are accepted. The default is C{'standard'}, which corresponds to the mixed
Gregorian/Julian calendar used by the C{udunits library}. Valid calendars
are:

C{'gregorian'} or C{'standard'} (default):

Mixed Gregorian/Julian calendar as defined by udunits.

C{'proleptic_gregorian'}:

A Gregorian calendar extended to dates before 1582-10-15. That is, a year
is a leap year if either (i) it is divisible by 4 but not by 100 or (ii)
it is divisible by 400.

C{'noleap'} or C{'365_day'}:

Gregorian calendar without leap years, i.e., all years are 365 days long.
all_leap or 366_day Gregorian calendar with every year being a leap year,
i.e., all years are 366 days long.

C{'360_day'}:

All years are 360 days divided into 30 day months.

C{'julian'}:

Proleptic Julian calendar, extended to dates after 1582-10-5. A year is a
leap year if it is divisible by 4.

The C{L{num2date}} and C{L{date2num}} class methods can used to convert datetime
instances to/from the specified time units using the specified calendar.

The datetime instances returned by C{num2date} are native python datetime
objects if the date falls in the Gregorian calendar (i.e.
C{calendar='proleptic_gregorian', 'standard'} or C{'gregorian'} and
the date is after 1582-10-15). Otherwise, they are native datetime
objects which are actually instances of C{L{cftime.datetime}}.  This is
because the python datetime module cannot handle the weird dates in some
calendars (such as C{'360_day'} and C{'all_leap'}) which don't exist in any real
world calendar.

Example usage:

>>> from cftime import utime
>>> from datetime import  datetime
>>> cdftime = utime('hours since 0001-01-01 00:00:00')
>>> date = datetime.now()
>>> print date
2016-10-05 08:46:27.245015
>>>
>>> t = cdftime.date2num(date)
>>> print t
17669840.7742
>>>
>>> date = cdftime.num2date(t)
>>> print date
2016-10-05 08:46:27.244996
>>>

The resolution of the transformation operation is approximately a millisecond.

Warning:  Dates between 1582-10-5 and 1582-10-15 do not exist in the
C{'standard'} or C{'gregorian'} calendars.  An exception will be raised if you pass
a 'datetime-like' object in that range to the C{L{date2num}} class method.

Words of Wisdom from the British MetOffice concerning reference dates:

"udunits implements the mixed Gregorian/Julian calendar system, as
followed in England, in which dates prior to 1582-10-15 are assumed to use
the Julian calendar. Other software cannot be relied upon to handle the
change of calendar in the same way, so for robustness it is recommended
that the reference date be later than 1582. If earlier dates must be used,
it should be noted that udunits treats 0 AD as identical to 1 AD."

@ivar origin: datetime instance defining the origin of the netCDF time variable.
@ivar calendar:  the calendar used (as specified by the C{calendar} keyword).
@ivar unit_string:  a string defining the the netCDF time variable.
@ivar units:  the units part of C{unit_string} (i.e. 'days', 'hours', 'seconds').
    """

    def __init__(self, unit_string, calendar='standard',
                 only_use_cftime_datetimes=True):
        """
@param unit_string: a string of the form
C{'time-units since <time-origin>'} defining the time units.

Valid time-units are days, hours, minutes and seconds (the singular forms
are also accepted). An example unit_string would be C{'hours
since 0001-01-01 00:00:00'}. months is allowed as a time unit
*only* for the 360_day calendar.

@keyword calendar: describes the calendar used in the time calculations.
All the values currently defined in the U{CF metadata convention
<http://cf-pcmdi.llnl.gov/documents/cf-conventions/1.1/cf-conventions.html#time-coordinate>}
are accepted. The default is C{'standard'}, which corresponds to the mixed
Gregorian/Julian calendar used by the C{udunits library}. Valid calendars
are:
 - C{'gregorian'} or C{'standard'} (default):
 Mixed Gregorian/Julian calendar as defined by udunits.
 - C{'proleptic_gregorian'}:
 A Gregorian calendar extended to dates before 1582-10-15. That is, a year
 is a leap year if either (i) it is divisible by 4 but not by 100 or (ii)
 it is divisible by 400.
 - C{'noleap'} or C{'365_day'}:
 Gregorian calendar without leap years, i.e., all years are 365 days long.
 - C{'all_leap'} or C{'366_day'}:
 Gregorian calendar with every year being a leap year, i.e.,
 all years are 366 days long.
 -C{'360_day'}:
 All years are 360 days divided into 30 day months.
 -C{'julian'}:
 Proleptic Julian calendar, extended to dates after 1582-10-5. A year is a
 leap year if it is divisible by 4.

@keyword only_use_cftime_datetimes: if False, datetime.datetime
objects are returned from num2date where possible; if True dates which subclass
cftime.datetime are returned for all calendars. Default True.

@returns: A class instance which may be used for converting times from netCDF
units to datetime objects.
        """
        calendar = calendar.lower()
        if calendar in _calendars:
            self.calendar = calendar
        else:
            raise ValueError(
                "calendar must be one of %s, got '%s'" % (str(_calendars), calendar))
        units, tzoffset, self.origin =\
        _parse_date_and_units(unit_string,calendar)
        # real-world calendars limited to positive reference years.
        if self.calendar in ['julian', 'standard', 'gregorian', 'proleptic_gregorian']:
            if self.origin.year == 0:
                msg='zero not allowed as a reference year, does not exist in Julian or Gregorian calendars'
                raise ValueError(msg)
        self.tzoffset = np.array(tzoffset,dtype=np.longdouble)  # time zone offset in minutes
        self.units = units
        self.unit_string = unit_string
        if self.calendar in ['noleap', '365_day'] and self.origin.month == 2 and self.origin.day == 29:
            raise ValueError(
                'cannot specify a leap day as the reference time with the noleap calendar')
        if self.calendar == '360_day' and self.origin.day > 30:
            raise ValueError(
                'there are only 30 days in every month with the 360_day calendar')
        self._jd0 = JulianDayFromDate(self.origin, calendar=self.calendar)
        self.only_use_cftime_datetimes = only_use_cftime_datetimes

    def date2num(self, date):
        """
        Returns C{time_value} in units described by L{unit_string}, using
        the specified L{calendar}, given a 'datetime-like' object.

        The datetime object must represent UTC with no time-zone offset.
        If there is a time-zone offset implied by L{unit_string}, it will
        be applied to the returned numeric values.

        Resolution is approximately a millisecond.

        If C{calendar = 'standard'} or C{'gregorian'} (indicating
        that the mixed Julian/Gregorian calendar is to be used), an
        exception will be raised if the 'datetime-like' object describes
        a date between 1582-10-5 and 1582-10-15.

        Works for scalars, sequences and numpy arrays.
        Returns a scalar if input is a scalar, else returns a numpy array.
        """
        isscalar = False
        try:
            date[0]
        except:
            isscalar = True
        if not isscalar:
            date = np.array(date)
            shape = date.shape
        if isscalar:
            jdelta = JulianDayFromDate(date, self.calendar)-self._jd0
        else:
            jdelta = JulianDayFromDate(date.flat, self.calendar)-self._jd0
        if not isscalar:
            jdelta = np.array(jdelta)
        # convert to desired units, add time zone offset.
        if self.units in microsec_units:
            jdelta = jdelta * 86400. * 1.e6  + self.tzoffset * 60. * 1.e6
        elif self.units in millisec_units:
            jdelta = jdelta * 86400. * 1.e3  + self.tzoffset * 60. * 1.e3
        elif self.units in sec_units:
            jdelta = jdelta * 86400. + self.tzoffset * 60.
        elif self.units in min_units:
            jdelta = jdelta * 1440. + self.tzoffset
        elif self.units in hr_units:
            jdelta = jdelta * 24. + self.tzoffset / 60.
        elif self.units in day_units:
            jdelta = jdelta + self.tzoffset / 1440.
        elif self.units in month_units and self.calendar == '360_day':
            jdelta = jdelta/30. + self.tzoffset / (30. * 1440.)
        else:
            raise ValueError('unsupported time units')
        if isscalar:
            return jdelta.astype(np.float64)
        else:
            return np.reshape(jdelta.astype(np.float64), shape)

    def num2date(self, time_value):
        """
        Return a 'datetime-like' object given a C{time_value} in units
        described by L{unit_string}, using L{calendar}.

        dates are in UTC with no offset, even if L{unit_string} contains
        a time zone offset from UTC.

        Resolution is approximately a millisecond.

        Works for scalars, sequences and numpy arrays.
        Returns a scalar if input is a scalar, else returns a numpy array.

        The datetime instances returned by C{num2date} are native python datetime
        objects if the date falls in the Gregorian calendar (i.e.
        C{calendar='proleptic_gregorian'}, or C{calendar = 'standard'/'gregorian'} and
        the date is after 1582-10-15). Otherwise, they are cftime.datetime
        objects which are actually instances of cftime.datetime.  This is
        because the python datetime module cannot handle the weird dates in some
        calendars (such as C{'360_day'} and C{'all_leap'}) which
        do not exist in any real world calendar.
        """
        isscalar = False
        try:
            time_value[0]
        except:
            isscalar = True
        ismasked = False
        if np.ma.isMA(time_value) and np.ma.is_masked(time_value):
            mask = time_value.mask
            ismasked = True
        if not isscalar:
            time_value = np.array(time_value, dtype='d')
            shape = time_value.shape
        # convert to desired units, subtract time zone offset.
        if self.units in microsec_units:
            jdelta = time_value / 86400000000. - self.tzoffset / 1440.
        elif self.units in millisec_units:
            jdelta = time_value / 86400000. - self.tzoffset / 1440.
        elif self.units in sec_units:
            jdelta = time_value / 86400. - self.tzoffset / 1440.
        elif self.units in min_units:
            jdelta = time_value / 1440. - self.tzoffset / 1440.
        elif self.units in hr_units:
            jdelta = time_value / 24. - self.tzoffset / 1440.
        elif self.units in day_units:
            jdelta = time_value - self.tzoffset / 1440.
        elif self.units in month_units and self.calendar == '360_day':
            # only allowed for 360_day calendar
            jdelta = time_value * 30. - self.tzoffset / 1440.
        else:
            raise ValueError('unsupported time units')
        jd = self._jd0 + jdelta
        if not isscalar:
            if ismasked:
                date = []
                for j, m in zip(jd.flat, mask.flat):
                    if not m:
                        date.append(DateFromJulianDay(j, self.calendar,
                                                      self.only_use_cftime_datetimes))
                    else:
                        date.append(None)
            else:
                date = DateFromJulianDay(jd.flat, self.calendar,
                                         self.only_use_cftime_datetimes)
        else:
            if ismasked and mask.item():
                date = None
            else:
                date = DateFromJulianDay(jd, self.calendar,
                                         self.only_use_cftime_datetimes)
        if isscalar:
            return date
        else:
            return np.reshape(np.array(date), shape)


cdef _parse_timezone(tzstring):
    """Parses ISO 8601 time zone specs into tzinfo offsets

    Adapted from pyiso8601 (http://code.google.com/p/pyiso8601/)
    """
    if tzstring == "Z":
        return 0
    # This isn't strictly correct, but it's common to encounter dates without
    # time zones so I'll assume the default (which defaults to UTC).
    if tzstring is None:
        return 0
    m = TIMEZONE_REGEX.match(tzstring)
    prefix, hours, minutes1, minutes2 = m.groups()
    hours = int(hours)
    # Note: Minutes don't have to be specified in tzstring, so if the group is not found it means minutes is 0.
    #       Also, due to the timezone regex definition, there are two mutually exclusive groups that might hold the minutes value, so check both.
    minutes = int(minutes1) if minutes1 is not None else int(minutes2) if minutes2 is not None else 0
    if prefix == "-":
        hours = -hours
        minutes = -minutes
    return minutes + hours * 60.


cpdef _parse_date(datestring):
    """Parses ISO 8601 dates into datetime objects

    The timezone is parsed from the date string, assuming UTC
    by default.

    Note that a seconds element with a fractional component
    (e.g. 12.5) is converted into integer seconds and integer
    microseconds.

    Adapted from pyiso8601 (http://code.google.com/p/pyiso8601/)

    """
    if not isinstance(datestring, str) and not isinstance(datestring, unicode):
        raise ValueError("Expecting a string %r" % datestring)
    m = ISO8601_REGEX.match(datestring.strip())
    if not m:
        raise ValueError("Unable to parse date string %r" % datestring)
    groups = m.groupdict()
    tzoffset_mins = _parse_timezone(groups["timezone"])
    if groups["hour"] is None:
        groups["hour"] = 0
    if groups["minute"] is None:
        groups["minute"] = 0
    if groups["second"] is None:
        groups["second"] = 0
    if groups["fraction"] is None:
        groups["fraction"] = 0
    else:
        groups["fraction"] = int(float("0.%s" % groups["fraction"]) * 1e6)
    iyear = int(groups["year"])
    return iyear, int(groups["month"]), int(groups["day"]),\
        int(groups["hour"]), int(groups["minute"]), int(groups["second"]),\
        int(groups["fraction"]),\
        tzoffset_mins

cdef _check_index(indices, times, nctime, calendar, select):
    """Return True if the time indices given correspond to the given times,
    False otherwise.

    Parameters:

    indices : sequence of integers
    Positive integers indexing the time variable.

    times : sequence of times.
    Reference times.

    nctime : netCDF Variable object
    NetCDF time object.

    calendar : string
    Calendar of nctime.

    select : string
    Index selection method.
    """
    N = nctime.shape[0]
    if (indices < 0).any():
        return False

    if (indices >= N).any():
        return False

    try:
        t = nctime[indices]
        nctime = nctime
    # WORKAROUND TO CHANGES IN SLICING BEHAVIOUR in 1.1.2
    # this may be unacceptably slow...
    # if indices are unsorted, or there are duplicate
    # values in indices, read entire time variable into numpy
    # array so numpy slicing rules can be used.
    except IndexError:
        nctime = nctime[:]
        t = nctime[indices]
# if fancy indexing not available, fall back on this.
#   t=[]
#   for ind in indices:
#       t.append(nctime[ind])

    if select == 'exact':
        return np.all(t == times)

    elif select == 'before':
        ta = nctime[np.clip(indices + 1, 0, N - 1)]
        return np.all(t <= times) and np.all(ta > times)

    elif select == 'after':
        tb = nctime[np.clip(indices - 1, 0, N - 1)]
        return np.all(t >= times) and np.all(tb < times)

    elif select == 'nearest':
        ta = nctime[np.clip(indices + 1, 0, N - 1)]
        tb = nctime[np.clip(indices - 1, 0, N - 1)]
        delta_after = ta - t
        delta_before = t - tb
        delta_check = np.abs(times - t)
        return np.all(delta_check <= delta_after) and np.all(delta_check <= delta_before)


def _date2index(dates, nctime, calendar=None, select='exact'):
    """
    _date2index(dates, nctime, calendar=None, select='exact')

    Return indices of a netCDF time variable corresponding to the given dates.

    @param dates: A datetime object or a sequence of datetime objects.
    The datetime objects should not include a time-zone offset.

    @param nctime: A netCDF time variable object. The nctime object must have a
    C{units} attribute. The entries are assumed to be stored in increasing
    order.

    @param calendar: Describes the calendar used in the time calculation.
    Valid calendars C{'standard', 'gregorian', 'proleptic_gregorian'
    'noleap', '365_day', '360_day', 'julian', 'all_leap', '366_day'}.
    Default is C{'standard'}, which is a mixed Julian/Gregorian calendar
    If C{calendar} is None, its value is given by C{nctime.calendar} or
    C{standard} if no such attribute exists.

    @param select: C{'exact', 'before', 'after', 'nearest'}
    The index selection method. C{exact} will return the indices perfectly
    matching the dates given. C{before} and C{after} will return the indices
    corresponding to the dates just before or just after the given dates if
    an exact match cannot be found. C{nearest} will return the indices that
    correspond to the closest dates.
    """
    try:
        nctime.units
    except AttributeError:
        raise AttributeError("netcdf time variable is missing a 'units' attribute")
    # Setting the calendar.
    if calendar == None:
        calendar = getattr(nctime, 'calendar', 'standard')
    cdftime = utime(nctime.units,calendar=calendar)
    times = cdftime.date2num(dates)
    return time2index(times, nctime, calendar=calendar, select=select)


def time2index(times, nctime, calendar=None, select='exact'):
    """
    time2index(times, nctime, calendar=None, select='exact')

    Return indices of a netCDF time variable corresponding to the given times.

    @param times: A numeric time or a sequence of numeric times.

    @param nctime: A netCDF time variable object. The nctime object must have a
    C{units} attribute. The entries are assumed to be stored in increasing
    order.

    @param calendar: Describes the calendar used in the time calculation.
    Valid calendars C{'standard', 'gregorian', 'proleptic_gregorian'
    'noleap', '365_day', '360_day', 'julian', 'all_leap', '366_day'}.
    Default is C{'standard'}, which is a mixed Julian/Gregorian calendar
    If C{calendar} is None, its value is given by C{nctime.calendar} or
    C{standard} if no such attribute exists.

    @param select: C{'exact', 'before', 'after', 'nearest'}
    The index selection method. C{exact} will return the indices perfectly
    matching the times given. C{before} and C{after} will return the indices
    corresponding to the times just before or just after the given times if
    an exact match cannot be found. C{nearest} will return the indices that
    correspond to the closest times.
    """
    try:
        nctime.units
    except AttributeError:
        raise AttributeError("netcdf time variable is missing a 'units' attribute")
    # Setting the calendar.
    if calendar == None:
        calendar = getattr(nctime, 'calendar', 'standard')

    num = np.atleast_1d(times)
    N = len(nctime)

    # Trying to infer the correct index from the starting time and the stride.
    # This assumes that the times are increasing uniformly.
    if len(nctime) >= 2:
        t0, t1 = nctime[:2]
        dt = t1 - t0
    else:
        t0 = nctime[0]
        dt = 1.
    if select in ['exact', 'before']:
        index = np.array((num - t0) / dt, int)
    elif select == 'after':
        index = np.array(np.ceil((num - t0) / dt), int)
    else:
        index = np.array(np.around((num - t0) / dt), int)

    # Checking that the index really corresponds to the given time.
    # If the times do not correspond, then it means that the times
    # are not increasing uniformly and we try the bisection method.
    if not _check_index(index, times, nctime, calendar, select):

        # Use the bisection method. Assumes nctime is ordered.
        import bisect
        index = np.array([bisect.bisect_right(nctime, n) for n in num], int)
        before = index == 0

        index = np.array([bisect.bisect_left(nctime, n) for n in num], int)
        after = index == N

        if select in ['before', 'exact'] and np.any(before):
            raise ValueError(
                'Some of the times given are before the first time in `nctime`.')

        if select in ['after', 'exact'] and np.any(after):
            raise ValueError(
                'Some of the times given are after the last time in `nctime`.')

        # Find the times for which the match is not perfect.
        # Use list comprehension instead of the simpler `nctime[index]` since
        # not all time objects support numpy integer indexing (eg dap).
        index[after] = N - 1
        ncnum = np.squeeze([nctime[i] for i in index])
        mismatch = np.nonzero(ncnum != num)[0]

        if select == 'exact':
            if len(mismatch) > 0:
                raise ValueError(
                    'Some of the times specified were not found in the `nctime` variable.')

        elif select == 'before':
            index[after] = N
            index[mismatch] -= 1

        elif select == 'after':
            pass

        elif select == 'nearest':
            nearest_to_left = num[mismatch] < np.array(
                [float(nctime[i - 1]) + float(nctime[i]) for i in index[mismatch]]) / 2.
            index[mismatch] = index[mismatch] - 1 * nearest_to_left

        else:
            raise ValueError(
                "%s is not an option for the `select` argument." % select)

        # Correct for indices equal to -1
        index[before] = 0

    # convert numpy scalars or single element arrays to python ints.
    return _toscalar(index)


cdef _toscalar(a):
    if a.shape in [(), (1,)]:
        return a.item()
    else:
        return a

cdef to_tuple(dt):
    """Turn a datetime.datetime instance into a tuple of integers. Elements go
    in the order of decreasing significance, making it easy to compare
    datetime instances. Parts of the state that don't affect ordering
    are omitted. Compare to datetime.timetuple()."""
    return (dt.year, dt.month, dt.day, dt.hour, dt.minute,
            dt.second, dt.microsecond)

# a cache of converters (utime instances) for different calendars
cdef dict _converters
_converters = {}
for calendar in _calendars:
    _converters[calendar] = utime("seconds since 1-1-1", calendar)

@cython.embedsignature(True)
cdef class datetime(object):
    """
The base class implementing most methods of datetime classes that
mimic datetime.datetime but support calendars other than the proleptic
Gregorial calendar.
    """
    cdef readonly int year, month, day, hour, minute, dayofwk, dayofyr, daysinmonth
    cdef readonly int second, microsecond
    cdef readonly str calendar

    # Python's datetime.datetime uses the proleptic Gregorian
    # calendar. This boolean is used to decide whether a
    # cftime.datetime instance can be converted to
    # datetime.datetime.
    cdef readonly bint datetime_compatible

    def __init__(self, int year, int month, int day, int hour=0, int minute=0, int second=0,
                 int microsecond=0, int dayofwk=-1, int dayofyr=1):
        """dayofyr set to 1 by default - otherwise time.strftime will complain"""

        self.year = year
        self.month = month
        self.day = day
        self.hour = hour
        self.minute = minute
        self.dayofwk = dayofwk # 0 is Monday, 6 is Sunday
        self.dayofyr = dayofyr
        self.second = second
        self.microsecond = microsecond
        self.calendar = ""
        self.daysinmonth = -1
        self.datetime_compatible = True

    @property
    def format(self):
        return '%Y-%m-%d %H:%M:%S'

    def strftime(self, format=None):
        """
        Return a string representing the date, controlled by an explicit format
        string. For a complete list of formatting directives, see section
        'strftime() and strptime() Behavior' in the base Python documentation.
        """
        if format is None:
            format = self.format
        return _strftime(self, format)

    def replace(self, **kwargs):
        """Return datetime with new specified fields."""
        args = {"year": self.year,
                "month": self.month,
                "day": self.day,
                "hour": self.hour,
                "minute": self.minute,
                "second": self.second,
                "microsecond": self.microsecond}

        if 'dayofyr' in kwargs or 'dayofwk' in kwargs:
            raise ValueError('Replacing the dayofyr or dayofwk of a datetime is '
                             'not supported.')

        for name, value in kwargs.items():
            args[name] = value

        return self.__class__(**args)

    def timetuple(self):
        """
        Return a time.struct_time such as returned by time.localtime().
        The DST flag is -1. d.timetuple() is equivalent to
        time.struct_time((d.year, d.month, d.day, d.hour, d.minute,
        d.second, d.weekday(), yday, dst)), where yday is the
        day number within the current year starting with 1 for January 1st.
        """
        return time.struct_time((self.year, self.month, self.day, self.hour,
                self.minute, self.second, self.dayofwk, self.dayofyr, -1))

    cpdef _to_real_datetime(self):
        return real_datetime(self.year, self.month, self.day,
                             self.hour, self.minute, self.second,
                             self.microsecond)

    def __repr__(self):
        return "{0}.{1}({2})".format('cftime',
                                     self.__class__.__name__,
                                     str(self))

    def __str__(self):
        second = '{:02d}'.format(self.second)
        if self.microsecond:
            second += '.{:06d}'.format(self.microsecond)

        return "{:04d}-{:02d}-{:02d} {:02d}:{:02d}:{}".format(
            self.year, self.month, self.day, self.hour, self.minute, second)

    def __hash__(self):
        try:
            d = self._to_real_datetime()
        except ValueError:
            return hash(self.timetuple())
        return hash(d)

    cdef to_tuple(self):
        return (self.year, self.month, self.day, self.hour, self.minute,
                self.second, self.microsecond)

    def __richcmp__(self, other, int op):
        cdef datetime dt, dt_other
        dt = self
        if isinstance(other, datetime):
            dt_other = other
            # comparing two datetime instances
            if dt.calendar == dt_other.calendar:
                return PyObject_RichCompare(dt.to_tuple(), dt_other.to_tuple(), op)
            else:
                # Note: it *is* possible to compare datetime
                # instances that use difference calendars by using
                # utime.date2num(), but this implementation does
                # not attempt it.
                raise TypeError("cannot compare {0!r} and {1!r} (different calendars)".format(dt, dt_other))
        elif isinstance(other, datetime_python):
            # comparing datetime and real_datetime
            if not dt.datetime_compatible:
                raise TypeError("cannot compare {0!r} and {1!r} (different calendars)".format(self, other))
            return PyObject_RichCompare(dt.to_tuple(), to_tuple(other), op)
        else:
            # With Python3 we can simply return NotImplemented. If the other
            # object does not support rich comparison for cftime then a
            # TypeError will be automatically raised. However, Python2 is not
            # consistent with this Python3 behaviour. In Python2, we only
            # delegate the comparison operation to the other object iff it has
            # suitable rich comparison support available. This is deduced by
            # introspection of the other object. Otherwise, we explicitly raise
            # a TypeError to avoid Python2 defaulting to using either __cmp__
            # comparision on the other object, or worst still, object ID
            # comparison. Either way, at this point the comparision is deemed
            # not valid from our perspective.
            if sys.version_info.major == 2:
                rop = _rop_lookup[op]
                if (hasattr(other, '__richcmp__') or hasattr(other, rop)):
                    # The other object potentially has the smarts to handle
                    # the comparision, so allow the Python machinery to hand
                    # the operation off to the other object.
                    return NotImplemented
                # Otherwise, the comparison is not valid.
                emsg = "cannot compare {0!r} and {1!r}"
                raise TypeError(emsg.format(self, other))
            else:
                # Delegate responsibility of comparison to the other object.
                return NotImplemented

    cdef _getstate(self):
        return (self.year, self.month, self.day, self.hour,
                self.minute, self.second, self.microsecond,
                self.dayofwk, self.dayofyr)

    def __reduce__(self):
        """special method that allows instance to be pickled"""
        return (self.__class__, self._getstate())

    cdef _add_timedelta(self, other):
        return NotImplemented

    def __add__(self, other):
        cdef datetime dt
        if isinstance(self, datetime) and isinstance(other, timedelta):
            dt = self
            delta = other
        elif isinstance(self, timedelta) and isinstance(other, datetime):
            dt = other
            delta = self
        else:
            return NotImplemented
        return dt._add_timedelta(delta)

    def __sub__(self, other):
        cdef datetime dt
        if isinstance(self, datetime): # left arg is a datetime instance
            dt = self
            if isinstance(other, datetime):
                # datetime - datetime
                if dt.calendar != other.calendar:
                    raise ValueError("cannot compute the time difference between dates with different calendars")
                if dt.calendar == "":
                    raise ValueError("cannot compute the time difference between dates that are not calendar-aware")
                converter = _converters[dt.calendar]
                return timedelta(seconds=converter.date2num(dt) - converter.date2num(other))
            elif isinstance(other, datetime_python):
                # datetime - real_datetime
                if not dt.datetime_compatible:
                    msg="""
Cannot compute the time difference between dates with different calendars.
One of the datetime objects may have been converted to a native python
datetime instance.  Try using only_use_cftime_datetimes=True when creating the
datetime object."""
                    raise ValueError(msg)
                return dt._to_real_datetime() - other
            elif isinstance(other, timedelta):
                # datetime - timedelta
                return dt._add_timedelta(-other)
            else:
                return NotImplemented
        else:
            if isinstance(self, datetime_python):
                # real_datetime - datetime
                if not other.datetime_compatible:
                    msg="""
Cannot compute the time difference between dates with different calendars.
One of the datetime objects may have been converted to a native python
datetime instance.  Try using only_use_cftime_datetimes=True when creating the
datetime object."""
                    raise ValueError(msg)
                return self - other._to_real_datetime()
            else:
                return NotImplemented

@cython.embedsignature(True)
cdef class DatetimeNoLeap(datetime):
    """
Phony datetime object which mimics the python datetime object,
but uses the "noleap" ("365_day") calendar.
    """
    def __init__(self, *args, **kwargs):
        datetime.__init__(self, *args, **kwargs)
        self.calendar = "noleap"
        self.datetime_compatible = False
        assert_valid_date(self, no_leap, False, has_year_zero=True)
        # if dayofwk, dayofyr not set, calculate them.
        if self.dayofwk < 0:
            jd = JulianDayFromDate(self,calendar='365_day')
            year,month,day,hour,mn,sec,ms,dayofwk,dayofyr =\
            DateFromJulianDay(jd,return_tuple=True,calendar='365_day')
            self.dayofwk = dayofwk
            self.dayofyr = dayofyr
        self.daysinmonth = _dpm[self.month-1]

    cdef _add_timedelta(self, delta):
        return DatetimeNoLeap(*add_timedelta(self, delta, no_leap, False))

@cython.embedsignature(True)
cdef class DatetimeAllLeap(datetime):
    """
Phony datetime object which mimics the python datetime object,
but uses the "all_leap" ("366_day") calendar.
    """
    def __init__(self, *args, **kwargs):
        datetime.__init__(self, *args, **kwargs)
        self.calendar = "all_leap"
        self.datetime_compatible = False
        assert_valid_date(self, all_leap, False, has_year_zero=True)
        # if dayofwk, dayofyr not set, calculate them.
        if self.dayofwk < 0:
            jd = JulianDayFromDate(self,calendar='366_day')
            year,month,day,hour,mn,sec,ms,dayofwk,dayofyr =\
            DateFromJulianDay(jd,return_tuple=True,calendar='366_day')
            self.dayofwk = dayofwk
            self.dayofyr = dayofyr
        self.daysinmonth = _dpm_leap[self.month-1]

    cdef _add_timedelta(self, delta):
        return DatetimeAllLeap(*add_timedelta(self, delta, all_leap, False))

@cython.embedsignature(True)
cdef class Datetime360Day(datetime):
    """
Phony datetime object which mimics the python datetime object,
but uses the "360_day" calendar.
    """
    def __init__(self, *args, **kwargs):
        datetime.__init__(self, *args, **kwargs)
        self.calendar = "360_day"
        self.datetime_compatible = False
        assert_valid_date(self, no_leap, False, has_year_zero=True, is_360_day=True)
        # if dayofwk, dayofyr not set, calculate them.
        if self.dayofwk < 0:
            jd = JulianDayFromDate(self,calendar='360_day')
            year,month,day,hour,mn,sec,ms,dayofwk,dayofyr =\
            DateFromJulianDay(jd,return_tuple=True,calendar='360_day')
            self.dayofwk = dayofwk
            self.dayofyr = dayofyr
        self.daysinmonth = 30

    cdef _add_timedelta(self, delta):
        return Datetime360Day(*add_timedelta_360_day(self, delta))

@cython.embedsignature(True)
cdef class DatetimeJulian(datetime):
    """
Phony datetime object which mimics the python datetime object,
but uses the "julian" calendar.
    """
    def __init__(self, *args, **kwargs):
        datetime.__init__(self, *args, **kwargs)
        self.calendar = "julian"
        self.datetime_compatible = False
        assert_valid_date(self, is_leap_julian, False)
        # if dayofwk, dayofyr not set, calculate them.
        if self.dayofwk < 0:
            jd = JulianDayFromDate(self,calendar='julian')
            year,month,day,hour,mn,sec,ms,dayofwk,dayofyr =\
            DateFromJulianDay(jd,return_tuple=True,calendar='julian')
            self.dayofwk = dayofwk
            self.dayofyr = dayofyr
        self.daysinmonth = get_days_in_month(_is_leap(self.year, self.calendar), self.month)

    cdef _add_timedelta(self, delta):
        return DatetimeJulian(*add_timedelta(self, delta, is_leap_julian, False))

@cython.embedsignature(True)
cdef class DatetimeGregorian(datetime):
    """
Phony datetime object which mimics the python datetime object,
but uses the mixed Julian-Gregorian ("standard", "gregorian") calendar.

The last date of the Julian calendar is 1582-10-4, which is followed
by 1582-10-15, using the Gregorian calendar.

Instances using the date after 1582-10-15 can be compared to
datetime.datetime instances and used to compute time differences
(datetime.timedelta) by subtracting a DatetimeGregorian instance from
a datetime.datetime instance or vice versa.
    """
    def __init__(self, *args, **kwargs):
        datetime.__init__(self, *args, **kwargs)
        self.calendar = "gregorian"

        # dates after 1582-10-15 can be converted to and compared to
        # proleptic Gregorian dates
        if self.to_tuple() >= (1582, 10, 15, 0, 0, 0, 0):
            self.datetime_compatible = True
        else:
            self.datetime_compatible = False
        assert_valid_date(self, is_leap_gregorian, True)
        # if dayofwk, dayofyr not set, calculate them.
        if self.dayofwk < 0:
            jd = JulianDayFromDate(self,calendar='gregorian')
            year,month,day,hour,mn,sec,ms,dayofwk,dayofyr =\
            DateFromJulianDay(jd,return_tuple=True,calendar='gregorian')
            self.dayofwk = dayofwk
            self.dayofyr = dayofyr
        self.daysinmonth = get_days_in_month(_is_leap(self.year, self.calendar), self.month)

    cdef _add_timedelta(self, delta):
        return DatetimeGregorian(*add_timedelta(self, delta, is_leap_gregorian, True))

@cython.embedsignature(True)
cdef class DatetimeProlepticGregorian(datetime):
    """
Phony datetime object which mimics the python datetime object,
but allows for dates that don't exist in the proleptic gregorian calendar.

Supports timedelta operations by overloading + and -.

Has strftime, timetuple, replace, __repr__, and __str__ methods. The
format of the string produced by __str__ is controlled by self.format
(default %Y-%m-%d %H:%M:%S). Supports comparisons with other
datetime instances using the same calendar; comparison with
native python datetime instances is possible for cftime.datetime
instances using 'gregorian' and 'proleptic_gregorian' calendars.

Instance variables are year,month,day,hour,minute,second,microsecond,dayofwk,dayofyr,
format, and calendar.
    """
    def __init__(self, *args, **kwargs):
        datetime.__init__(self, *args, **kwargs)
        self.calendar = "proleptic_gregorian"
        self.datetime_compatible = True
        assert_valid_date(self, is_leap_proleptic_gregorian, False)
        # if dayofwk, dayofyr not set, calculate them.
        if self.dayofwk < 0:
            jd = JulianDayFromDate(self,calendar='proleptic_gregorian')
            year,month,day,hour,mn,sec,ms,dayofwk,dayofyr =\
            DateFromJulianDay(jd,return_tuple=True,calendar='proleptic_gregorian')
            self.dayofwk = dayofwk
            self.dayofyr = dayofyr
        self.daysinmonth = get_days_in_month(_is_leap(self.year, self.calendar), self.month)

    cdef _add_timedelta(self, delta):
        return DatetimeProlepticGregorian(*add_timedelta(self, delta,
                                                         is_leap_proleptic_gregorian, False))

_illegal_s = re.compile(r"((^|[^%])(%%)*%s)")


cdef _findall(text, substr):
    # Also finds overlaps
    sites = []
    i = 0
    while 1:
        j = text.find(substr, i)
        if j == -1:
            break
        sites.append(j)
        i = j + 1
    return sites

# Every 28 years the calendar repeats, except through century leap
# years where it's 6 years.  But only if you're using the Gregorian
# calendar.  ;)


cdef _strftime(datetime dt, fmt):
    if _illegal_s.search(fmt):
        raise TypeError("This strftime implementation does not handle %s")
    # don't use strftime method at all.
    # if dt.year > 1900:
    #    return dt.strftime(fmt)

    year = dt.year
    # For every non-leap year century, advance by
    # 6 years to get into the 28-year repeat cycle
    delta = 2000 - year
    off = 6 * (delta // 100 + delta // 400)
    year = year + off

    # Move to around the year 2000
    year = year + ((2000 - year) // 28) * 28
    timetuple = dt.timetuple()
    s1 = time.strftime(fmt, (year,) + timetuple[1:])
    sites1 = _findall(s1, str(year))

    s2 = time.strftime(fmt, (year + 28,) + timetuple[1:])
    sites2 = _findall(s2, str(year + 28))

    sites = []
    for site in sites1:
        if site in sites2:
            sites.append(site)

    s = s1
    syear = "%4d" % (dt.year,)
    for site in sites:
        s = s[:site] + syear + s[site + 4:]
    return s

cdef bint is_leap_julian(int year):
    "Return 1 if year is a leap year in the Julian calendar, 0 otherwise."
    return _is_leap(year, calendar='julian')

cdef bint is_leap_proleptic_gregorian(int year):
    "Return 1 if year is a leap year in the Proleptic Gregorian calendar, 0 otherwise."
    return _is_leap(year, calendar='proleptic_gregorian')

cdef bint is_leap_gregorian(int year):
    "Return 1 if year is a leap year in the Gregorian calendar, 0 otherwise."
    return _is_leap(year, calendar='standard')

cdef bint all_leap(int year):
    "Return True for all years."
    return True

cdef bint no_leap(int year):
    "Return False for all years."
    return False

cdef int * month_lengths(bint (*is_leap)(int), int year):
    if is_leap(year):
        return _dpm_leap
    else:
        return _dpm

cdef void assert_valid_date(datetime dt, bint (*is_leap)(int),
                            bint julian_gregorian_mixed,
                            bint has_year_zero=False,
                            bint is_360_day=False) except *:
    cdef int[12] month_length

    if not has_year_zero:
        if dt.year == 0:
            raise ValueError("invalid year provided in {0!r}".format(dt))
    if is_360_day:
        month_length = _dpm_360
    else:
        month_length = month_lengths(is_leap, dt.year)

    if dt.month < 1 or dt.month > 12:
        raise ValueError("invalid month provided in {0!r}".format(dt))

    if dt.day < 1 or dt.day > month_length[dt.month-1]:
        raise ValueError("invalid day number provided in {0!r}".format(dt))

    if julian_gregorian_mixed and dt.year == 1582 and dt.month == 10 and dt.day > 4 and dt.day < 15:
        raise ValueError("{0!r} is not present in the mixed Julian/Gregorian calendar".format(dt))

    if dt.hour < 0 or dt.hour > 23:
        raise ValueError("invalid hour provided in {0!r}".format(dt))

    if dt.minute < 0 or dt.minute > 59:
        raise ValueError("invalid minute provided in {0!r}".format(dt))

    if dt.second < 0 or dt.second > 59:
        raise ValueError("invalid second provided in {0!r}".format(dt))

    if dt.microsecond < 0 or dt.microsecond > 999999:
        raise ValueError("invalid microsecond provided in {0!r}".format(dt))

# Add a datetime.timedelta to a cftime.datetime instance. Uses
# integer arithmetic to avoid rounding errors and preserve
# microsecond accuracy.
#
# The argument is_leap is the pointer to a function returning 1 for leap years and 0 otherwise.
#
# This implementation supports 365_day (no_leap), 366_day (all_leap),
# julian, proleptic_gregorian, and the mixed Julian/Gregorian
# (standard, gregorian) calendars by using different is_leap and
# julian_gregorian_mixed arguments.
#
# The date of the transition from the Julian to Gregorian calendar and
# the number of invalid dates are hard-wired (1582-10-4 is the last day
# of the Julian calendar, after which follows 1582-10-15).
cdef tuple add_timedelta(datetime dt, delta, bint (*is_leap)(int), bint julian_gregorian_mixed):
    cdef int microsecond, second, minute, hour, day, month, year
    cdef int delta_microseconds, delta_seconds, delta_days
    cdef int* month_length
    cdef int extra_days, n_invalid_dates

    # extract these inputs here to avoid type conversion in the code below
    delta_microseconds = delta.microseconds
    delta_seconds = delta.seconds
    delta_days = delta.days

    # shift microseconds, seconds, days
    microsecond = dt.microsecond + delta_microseconds
    second = dt.second + delta_seconds
    minute = dt.minute
    hour = dt.hour
    day = dt.day
    month = dt.month
    year = dt.year

    month_length = month_lengths(is_leap, year)

    n_invalid_dates = 10 if julian_gregorian_mixed else 0

    # Normalize microseconds, seconds, minutes, hours.
    second += microsecond // 1000000
    microsecond = microsecond % 1000000
    minute += second // 60
    second = second % 60
    hour += minute // 60
    minute = minute % 60
    extra_days = hour // 24
    hour = hour % 24

    delta_days += extra_days

    while delta_days < 0:
        if year == 1582 and month == 10 and day > 14 and day + delta_days < 15:
            delta_days -= n_invalid_dates    # skip over invalid dates
        if day + delta_days < 1:
            delta_days += day
            # decrement month
            month -= 1
            if month < 1:
                month = 12
                year -= 1
                if year == 0:
                    year = -1
                month_length = month_lengths(is_leap, year)
            day = month_length[month-1]
        else:
            day += delta_days
            delta_days = 0

    while delta_days > 0:
        if year == 1582 and month == 10 and day < 5 and day + delta_days > 4:
            delta_days += n_invalid_dates    # skip over invalid dates
        if day + delta_days > month_length[month-1]:
            delta_days -= month_length[month-1] - (day - 1)
            # increment month
            month += 1
            if month > 12:
                month = 1
                year += 1
                if year == 0:
                    year = 1
                month_length = month_lengths(is_leap, year)
            day = 1
        else:
            day += delta_days
            delta_days = 0

    return (year, month, day, hour, minute, second, microsecond, -1, 1)

# Add a datetime.timedelta to a cftime.datetime instance with the 360_day calendar.
#
# Assumes that the 360_day calendar (unlike the rest of supported
# calendars) has the year 0. Also, there are no leap years and all
# months are 30 days long, so we can compute month and year by using
# "//" and "%".
cdef tuple add_timedelta_360_day(datetime dt, delta):
    cdef int microsecond, second, minute, hour, day, month, year
    cdef int delta_microseconds, delta_seconds, delta_days

    # extract these inputs here to avoid type conversion in the code below
    delta_microseconds = delta.microseconds
    delta_seconds = delta.seconds
    delta_days = delta.days

    # shift microseconds, seconds, days
    microsecond = dt.microsecond + delta_microseconds
    second = dt.second + delta_seconds
    minute = dt.minute
    hour = dt.hour
    day = dt.day + delta_days
    month = dt.month
    year = dt.year

    # Normalize microseconds, seconds, minutes, hours, days, and months.
    second += microsecond // 1000000
    microsecond = microsecond % 1000000
    minute += second // 60
    second = second % 60
    hour += minute // 60
    minute = minute % 60
    day += hour // 24
    hour = hour % 24
    # day and month are counted from 1; all months have 30 days
    month += (day - 1) // 30
    day = (day - 1) % 30 + 1
    # all years have 12 months
    year += (month - 1) // 12
    month = (month - 1) % 12 + 1

    return (year, month, day, hour, minute, second, microsecond, -1, 1)

# Calendar calculations base on calcals.c by David W. Pierce
# http://meteora.ucsd.edu/~pierce/calcalcs

cdef _is_leap(int year, calendar):
    cdef int tyear
    cdef bint leap
    calendar = _check_calendar(calendar)
    if year == 0:
        raise ValueError('year zero does not exist in the %s calendar' %\
                calendar)
    # Because there is no year 0 in the Julian calendar, years -1, -5, -9, etc
    # are leap years.
    if year < 0:
        tyear = year + 1
    else:
        tyear = year
    if calendar == 'proleptic_gregorian' or (calendar == 'standard' and year > 1581):
        if tyear % 4: # not divisible by 4
            leap = False
        elif year % 100: # not divisible by 100
            leap = True
        elif year % 400: # not divisible by 400
            leap = False
        else:
            leap = True
    elif calendar == 'julian' or (calendar == 'standard' and year < 1582):
        leap = tyear % 4 == 0
    elif calendar == '366_day':
        leap = True
    else:
        leap = False
    return leap

cdef _IntJulianDayFromDate(int year,int month,int day,calendar,skip_transition=False):
    """Compute integer Julian Day from year,month,day and calendar.

    Allowed calendars are 'standard', 'gregorian', 'julian',
    'proleptic_gregorian','360_day', '365_day', '366_day', 'noleap',
    'all_leap'.

    'noleap' is a synonym for '365_day'
    'all_leap' is a synonym for '366_day'
    'gregorian' is a synonym for 'standard'

    Negative years allowed back to -4714
    (proleptic_gregorian) or -4713 (standard or gregorian calendar).

    Negative year values are allowed in 360_day,365_day,366_day calendars.

    Integer julian day is number of days since noon UTC -4713-1-1
    in the julian or mixed julian/gregorian calendar, or noon UTC
    -4714-11-24 in the proleptic_gregorian calendar. Reference
    date is noon UTC 0-1-1 for other calendars.

    There is no year zero in standard (mixed), julian, or proleptic_gregorian
    calendars.

    Subtract 0.5 to get 00 UTC on that day.

    optional kwarg 'skip_transition':  When True, leave a 10-day
    gap in Julian day numbers between Oct 4 and Oct 15 1582 (the transition
    from Julian to Gregorian calendars).  Default False, ignored
    unless calendar = 'standard'."""
    cdef int jday, jday_jul, jday_greg
    cdef bint leap
    cdef int[12] dpm2use

    # validate inputs.
    calendar = _check_calendar(calendar)
    if month < 1 or month > 12 or day < 1 or day > 31:
        msg = "date %04d-%02d-%02d does not exist in the %s calendar" %\
        (year,month,day,calendar)
        raise ValueError(msg)

    # handle all calendars except standard, julian, proleptic_gregorian.
    if calendar == '360_day':
        return _IntJulianDayFromDate_360day(year,month,day)
    elif calendar == '365_day':
        return _IntJulianDayFromDate_365day(year,month,day)
    elif calendar == '366_day':
        return _IntJulianDayFromDate_366day(year,month,day)

    # handle standard, julian, proleptic_gregorian calendars.
    if year == 0:
        raise ValueError('year zero does not exist in the %s calendar' %\
                calendar)
    if (calendar == 'proleptic_gregorian'         and year < -4714) or\
       (calendar in ['julian','standard']  and year < -4713):
        raise ValueError('year out of range for %s calendar' % calendar)
    leap = _is_leap(year,calendar)
    if not leap and month == 2 and day == 29:
        raise ValueError('%s is not a leap year' % year)

    # add year offset
    if year < 0:
        year += 4801
    else:
        year += 4800

    if leap:
        dpm2use = _dpm_leap
    else:
        dpm2use = _dpm

    jday = day
    for m in range(month-1,0,-1):
        jday += dpm2use[m-1]

    jday_greg = jday + 365*(year-1) + (year-1)//4 - (year-1)//100 + (year-1)//400
    jday_greg -= 31739 # fix year offset
    jday_jul = jday + 365*(year-1) + (year-1)//4
    jday_jul -= 31777 # fix year offset
    if calendar == 'julian':
        return jday_jul
    elif calendar == 'proleptic_gregorian':
        return jday_greg
    elif calendar == 'standard':
        # check for invalid days in mixed calendar (there are 10 missing)
        if jday_jul >= 2299161 and jday_jul < 2299171:
            raise ValueError('invalid date in mixed calendar')
        if jday_jul < 2299161: # 1582 October 15
            return jday_jul
        else:
            if skip_transition:
                return jday_greg+10
            else:
                return jday_greg

    return jday

cdef _IntJulianDayToDate(int jday,calendar,skip_transition=False):
    """Compute the year,month,day,dow,doy given the integer Julian day.
    and calendar. (dow = day of week with 0=Mon,6=Sun and doy is day of year).

    Allowed calendars are 'standard', 'gregorian', 'julian',
    'proleptic_gregorian','360_day', '365_day', '366_day', 'noleap',
    'all_leap'.

    'noleap' is a synonym for '365_day'
    'all_leap' is a synonym for '366_day'
    'gregorian' is a synonym for 'standard'

    optional kwarg 'skip_transition':  When True, assume a 10-day
    gap in Julian day numbers between Oct 4 and Oct 15 1582 (the transition
    from Julian to Gregorian calendars).  Default False, ignored
    unless calendar = 'standard'."""
    cdef int year,month,day,dow,doy,yp1,tjday
    cdef int[12] dpm2use
    cdef int[13] spm2use

    # validate inputs.
    calendar = _check_calendar(calendar)

    # handle all calendars except standard, julian, proleptic_gregorian.
    if calendar == '360_day':
        return _IntJulianDayToDate_360day(jday)
    elif calendar == '365_day':
        return _IntJulianDayToDate_365day(jday)
    elif calendar == '366_day':
        return _IntJulianDayToDate_366day(jday)

    # handle standard, julian, proleptic_gregorian calendars.
    if jday < 0:
        raise ValueError('julian day must be a positive integer')
    # Make first estimate for year. subtract 4714 or 4713 because Julian Day number
    # 0 occurs in year 4714 BC in the Gregorian calendar and 4713 BC in the
    # Julian calendar.
    if calendar == 'proleptic_gregorian':
        year = jday//366 - 4714
    elif calendar in ['standard','julian']:
        year = jday//366 - 4713

    # compute day of week.
    dow = _get_dow(jday)

    if not skip_transition and calendar == 'standard' and jday > 2299160: jday += 10

    # Advance years until we find the right one
    yp1 = year + 1
    if yp1 == 0:
       yp1 = 1 # no year 0
    tjday = _IntJulianDayFromDate(yp1,1,1,calendar,skip_transition=True)
    while jday >= tjday:
        year += 1
        if year == 0:
            year = 1
        yp1 = year + 1
        if yp1 == 0:
            yp1 = 1
        tjday = _IntJulianDayFromDate(yp1,1,1,calendar,skip_transition=True)
    if _is_leap(year, calendar):
        dpm2use = _dpm_leap
        spm2use = _spm_366day
    else:
        dpm2use = _dpm
        spm2use = _spm_365day
    month = 1
    tjday =\
    _IntJulianDayFromDate(year,month,dpm2use[month-1],calendar,skip_transition=True)
    while jday > tjday:
        month += 1
        tjday =\
        _IntJulianDayFromDate(year,month,dpm2use[month-1],calendar,skip_transition=True)
    tjday = _IntJulianDayFromDate(year,month,1,calendar,skip_transition=True)
    day = jday - tjday + 1
    if month == 1:
        doy = day
    else:
        doy = spm2use[month-1]+day
    return year,month,day,dow,doy

cdef _get_dow(int jday):
    """compute day of week.
    0 = Sunday, 6 = Sat, valid after noon UTC"""
    cdef int dow
    dow = (jday + 1) % 7
    # convert to ISO 8601 (0 = Monday, 6 = Sunday), like python datetime
    dow -= 1
    if dow == -1: dow = 6
    return dow

cdef _check_calendar(calendar):
    """validate calendars, convert to subset of names to get rid of synonyms"""
    if calendar not in _calendars:
        raise ValueError('unsupported calendar')
    calout = calendar
    # remove 'gregorian','noleap','all_leap'
    if calendar in ['gregorian','standard']:
        calout = 'standard'
    if calendar == 'noleap':
        calout = '365_day'
    if calendar == 'all_leap':
        calout = '366_day'
    return calout

cdef _IntJulianDayFromDate_360day(int year,int month,int day):
    """Compute integer Julian Day from year,month,day in
    360_day calendar"""
    return year*360 + (month-1)*30 + day - 1

cdef _IntJulianDayFromDate_365day(int year,int month,int day):
    """Compute integer Julian Day from year,month,day in
    365_day calendar"""
    if month == 2 and day == 29:
        raise ValueError('no leap days in 365_day calendar')
    return year*365 + _spm_365day[month-1] + day - 1

cdef _IntJulianDayFromDate_366day(int year,int month,int day):
    """Compute integer Julian Day from year,month,day in
    366_day calendar"""
    return year*366 + _spm_366day[month-1] + day - 1

cdef _IntJulianDayToDate_365day(int jday):
    """Compute the year,month,day given the integer Julian day
    for 365_day calendar."""
    cdef int year,month,day,nextra,dow

    year = jday//365
    nextra = jday - year*365
    doy    = nextra + 1 # Julday numbering starts at 0, doy starts at 1
    month = 1
    while doy > _spm_365day[month]:
        month += 1
    day = doy - _spm_365day[month-1]

    # compute day of week.
    dow = _get_dow(jday)

    return year,month,day,dow,doy

cdef _IntJulianDayToDate_366day(int jday):
    """Compute the year,month,day given the integer Julian day
    for 366_day calendar."""
    cdef int year,month,day,nextra,dow

    year = jday//366
    nextra = jday - year*366
    doy    = nextra + 1 # Julday numbering starts at 0, doy starts at 1
    month = 1
    while doy > _spm_366day[month]:
        month += 1
    day = doy - _spm_366day[month-1]

    # compute day of week.
    dow = _get_dow(jday)

    return year,month,day,dow,doy

cdef _IntJulianDayToDate_360day(int jday):
    """Compute the year,month,day given the integer Julian day
    for 360_day calendar."""
    cdef int year,month,day,nextra,dow

    year = jday//360
    nextra = jday - year*360
    doy    = nextra + 1 # Julday numbering starts at 0, doy starts at 1
    month = nextra//30 + 1
    day   = doy - (month-1)*30

    # compute day of week.
    dow = _get_dow(jday)

    return year,month,day,dow,doy
