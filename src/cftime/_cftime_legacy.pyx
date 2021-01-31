# stuff below no longer used by cftime.datetime, kept here for backwards compatibility.

@cython.embedsignature(True)
cdef class DatetimeNoLeap(datetime):
    """
Phony datetime object which mimics the python datetime object,
but uses the "noleap" ("365_day") calendar.
    """
    def __init__(self, *args, **kwargs):
        kwargs['calendar']='noleap'
        super().__init__(*args, **kwargs)
    def __repr__(self):
        return "{0}.{1}({2}, {3}, {4}, {5}, {6}, {7}, {8})".format('cftime',
                                     self.__class__.__name__,
                                     self.year,self.month,self.day,self.hour,self.minute,self.second,self.microsecond)

@cython.embedsignature(True)
cdef class DatetimeAllLeap(datetime):
    """
Phony datetime object which mimics the python datetime object,
but uses the "all_leap" ("366_day") calendar.
    """
    def __init__(self, *args, **kwargs):
        kwargs['calendar']='all_leap'
        super().__init__(*args, **kwargs)
    def __repr__(self):
        return "{0}.{1}({2}, {3}, {4}, {5}, {6}, {7}, {8})".format('cftime',
                                     self.__class__.__name__,
                                     self.year,self.month,self.day,self.hour,self.minute,self.second,self.microsecond)

@cython.embedsignature(True)
cdef class Datetime360Day(datetime):
    """
Phony datetime object which mimics the python datetime object,
but uses the "360_day" calendar.
    """
    def __init__(self, *args, **kwargs):
        kwargs['calendar']='360_day'
        super().__init__(*args, **kwargs)
    def __repr__(self):
        return "{0}.{1}({2}, {3}, {4}, {5}, {6}, {7}, {8})".format('cftime',
                                     self.__class__.__name__,
                                     self.year,self.month,self.day,self.hour,self.minute,self.second,self.microsecond)

@cython.embedsignature(True)
cdef class DatetimeJulian(datetime):
    """
Phony datetime object which mimics the python datetime object,
but uses the "julian" calendar.
    """
    def __init__(self, *args, **kwargs):
        kwargs['calendar']='julian'
        super().__init__(*args, **kwargs)
    def __repr__(self):
        return "{0}.{1}({2}, {3}, {4}, {5}, {6}, {7}, {8})".format('cftime',
                                     self.__class__.__name__,
                                     self.year,self.month,self.day,self.hour,self.minute,self.second,self.microsecond)

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
        kwargs['calendar']='gregorian'
        super().__init__(*args, **kwargs)
    def __repr__(self):
        return "{0}.{1}({2}, {3}, {4}, {5}, {6}, {7}, {8})".format('cftime',
                                     self.__class__.__name__,
                                     self.year,self.month,self.day,self.hour,self.minute,self.second,self.microsecond)

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
        kwargs['calendar']='proleptic_gregorian'
        super().__init__( *args, **kwargs)
    def __repr__(self):
        return "{0}.{1}({2}, {3}, {4}, {5}, {6}, {7}, {8})".format('cftime',
                                     self.__class__.__name__,
                                     self.year,self.month,self.day,self.hour,self.minute,self.second,self.microsecond)


# The following function (_IntJulianDayToDate) is based on
# algorithms described in the book
# "Calendrical Calculations" by Dershowitz and Rheingold, 3rd edition, Cambridge University Press, 2007
# and the C implementation provided at https://reingold.co/calendar.C
# with modifications to handle non-real-world calendars and negative years.

cdef _IntJulianDayToDate(int jday,calendar,skip_transition=False,has_year_zero=False):
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
    cdef int year,month,day,dow,doy,yp1,jday_count,nextra
    cdef int[12] dayspermonth
    cdef int[13] cumdayspermonth

    # validate inputs.
    calendar = _check_calendar(calendar)

    # compute day of week.
    dow = (jday + 1) % 7
    # convert to ISO 8601 (0 = Monday, 6 = Sunday), like python datetime
    dow -= 1
    if dow == -1: dow = 6

    # handle all calendars except standard, julian, proleptic_gregorian.
    if calendar == '360_day':
        year   = jday//360
        nextra = jday - year*360
        doy    = nextra + 1 # Julday numbering starts at 0, doy starts at 1
        month  = nextra//30 + 1
        day    = doy - (month-1)*30
        return year,month,day,dow,doy
    elif calendar == '365_day':
        year   = jday//365
        nextra = jday - year*365
        doy    = nextra + 1 # Julday numbering starts at 0, doy starts at 1
        month  = 1
        while doy > _cumdayspermonth[month]:
            month += 1
        day = doy - _cumdayspermonth[month-1]
        return year,month,day,dow,doy
    elif calendar == '366_day':
        year   = jday//366
        nextra = jday - year*366
        doy    = nextra + 1 # Julday numbering starts at 0, doy starts at 1
        month  = 1
        while doy > _cumdayspermonth_leap[month]:
            month += 1
        day = doy - _cumdayspermonth_leap[month-1]
        return year,month,day,dow,doy

    # handle standard, julian, proleptic_gregorian calendars.
    if jday < 0:
        raise ValueError('julian day must be a positive integer')

    # start with initial guess of year that is before jday=1 in both
    # Julian and Gregorian calendars.
    year = jday//366 - 4714

    # account for 10 days in Julian/Gregorian transition.
    if not skip_transition and calendar == 'standard' and jday > 2299160:
        jday += 10

    yp1 = year + 1
    if yp1 == 0 and not has_year_zero:
       yp1 = 1 # no year 0
    # initialize jday_count to Jan 1 of next year
    jday_count = _IntJulianDayFromDate(yp1,1,1,calendar,skip_transition=True,has_year_zero=has_year_zero)
    # Advance years until we find the right one
    # (stop iteration when jday_count jday >= specified jday)
    while jday >= jday_count:
        year += 1
        if year == 0 and not has_year_zero:
            year = 1
        yp1 = year + 1
        if yp1 == 0 and not has_year_zero:
            yp1 = 1
        jday_count = _IntJulianDayFromDate(yp1,1,1,calendar,skip_transition=True,has_year_zero=has_year_zero)
    # now we know year.
    # set days in specified month, cumulative days in computed year.
    if _is_leap(year, calendar,has_year_zero=has_year_zero):
        dayspermonth = _dayspermonth_leap
        cumdayspermonth = _cumdayspermonth_leap
    else:
        dayspermonth = _dayspermonth
        cumdayspermonth = _cumdayspermonth
    # initialized month to Jan, initialize jday_count to end of Jan of
    # calculated year.
    month = 1
    jday_count =\
    _IntJulianDayFromDate(year,month,dayspermonth[month-1],calendar,skip_transition=True,has_year_zero=has_year_zero)
    # now iterate by month until jday_count >= specified jday
    while jday > jday_count:
        month += 1
        jday_count =\
        _IntJulianDayFromDate(year,month,dayspermonth[month-1],calendar,skip_transition=True,has_year_zero=has_year_zero)
    # back up jday_count to 1st day of computed month
    jday_count = _IntJulianDayFromDate(year,month,1,calendar,skip_transition=True,has_year_zero=has_year_zero)
    # now jday_count represents day 1 of computed month in computed year
    # so computed day is just difference between jday_count and specified jday.
    day = jday - jday_count + 1
    # compute day in specified year.
    doy = cumdayspermonth[month-1]+day
    return year,month,day,dow,doy

def _round_half_up(x):
    # 'round half up' so 0.5 rounded to 1 (instead of 0 as in numpy.round)
    return np.ceil(np.floor(2.*x)/2.)

@cython.embedsignature(True)
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

@cython.embedsignature(True)
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

    if calendar == 'proleptic_gregorian':
        # datetime.datetime does not support years < 1
        #if year < 0:
        if only_use_cftime_datetimes:
            datetime_type = DatetimeProlepticGregorian
        else:
            if (year < 0).any(): # netcdftime issue #28
               datetime_type = DatetimeProlepticGregorian
            else:
               datetime_type = real_datetime
    elif calendar in ('standard', 'gregorian'):
        # return a 'real' datetime instance if calendar is proleptic
        # Gregorian or Gregorian and all dates are after the
        # Julian/Gregorian transition
        if ind_before and not only_use_cftime_datetimes:
            datetime_type = real_datetime
        else:
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
            return np.array([datetime_type(*args)
                             for args in
                             zip(year, month, day, hour, minute, second,
                                 microsecond)])

    else:
        if return_tuple:
            return (year[0], month[0], day[0], hour[0],
                    minute[0], second[0], microsecond[0],
                    dayofwk[0], dayofyr[0])
        else:
            return datetime_type(year[0], month[0], day[0], hour[0],
                                 minute[0], second[0], microsecond[0])

class utime:

    """
Performs conversions of netCDF time coordinate
data to/from datetime objects.

To initialize: `t = utime(unit_string,calendar='standard'`

where

`unit_string` is a string of the form
`time-units since <time-origin>` defining the time units.

Valid time-units are days, hours, minutes and seconds (the singular forms
are also accepted). An example unit_string would be `hours
since 0001-01-01 00:00:00`. months is allowed as a time unit
*only* for the 360_day calendar.

The calendar keyword describes the calendar used in the time calculations.
All the values currently defined in the U{CF metadata convention
<http://cf-pcmdi.llnl.gov/documents/cf-conventions/1.1/cf-conventions.html#time-coordinate>}
are accepted. The default is 'standard', which corresponds to the mixed
Gregorian/Julian calendar used by the udunits library. Valid calendars
are:

'gregorian' or 'standard' (default):

Mixed Gregorian/Julian calendar as defined by udunits.

'proleptic_gregorian':

A Gregorian calendar extended to dates before 1582-10-15. That is, a year
is a leap year if either (i) it is divisible by 4 but not by 100 or (ii)
it is divisible by 400.

'noleap' or '365_day':

Gregorian calendar without leap years, i.e., all years are 365 days long.
all_leap or 366_day Gregorian calendar with every year being a leap year,
i.e., all years are 366 days long.

'360_day':

All years are 360 days divided into 30 day months.

'julian':

Proleptic Julian calendar, extended to dates after 1582-10-5. A year is a
leap year if it is divisible by 4.

The num2date and date2num class methods can used to convert datetime
instances to/from the specified time units using the specified calendar.

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

The resolution of the transformation operation is approximately a microsecond.

Warning:  Dates between 1582-10-5 and 1582-10-15 do not exist in the
'standard' or 'gregorian' calendars.  An exception will be raised if you pass
a 'datetime-like' object in that range to the date2num class method.

Words of Wisdom from the British MetOffice concerning reference dates:

"udunits implements the mixed Gregorian/Julian calendar system, as
followed in England, in which dates prior to 1582-10-15 are assumed to use
the Julian calendar. Other software cannot be relied upon to handle the
change of calendar in the same way, so for robustness it is recommended
that the reference date be later than 1582. If earlier dates must be used,
it should be noted that udunits treats 0 AD as identical to 1 AD."

@ivar origin: datetime instance defining the origin of the netCDF time variable.
@ivar calendar:  the calendar used (as specified by the `calendar` keyword).
@ivar unit_string:  a string defining the the netCDF time variable.
@ivar units:  the units part of `unit_string` (i.e. 'days', 'hours', 'seconds').
    """

    def __init__(self, unit_string, calendar='standard',
                 only_use_cftime_datetimes=True,only_use_python_datetimes=False):
        """
@param unit_string: a string of the form
`time-units since <time-origin>` defining the time units.

Valid time-units are days, hours, minutes and seconds (the singular forms
are also accepted). An example unit_string would be `hours
since 0001-01-01 00:00:00`. months is allowed as a time unit
*only* for the 360_day calendar.

@keyword calendar: describes the calendar used in the time calculations.
All the values currently defined in the U{CF metadata convention
<http://cf-pcmdi.llnl.gov/documents/cf-conventions/1.1/cf-conventions.html#time-coordinate>}
are accepted. The default is `standard`, which corresponds to the mixed
Gregorian/Julian calendar used by the udunits library. Valid calendars
are:
 - `gregorian` or `standard` (default):
 Mixed Gregorian/Julian calendar as defined by udunits.
 - `proleptic_gregorian`:
 A Gregorian calendar extended to dates before 1582-10-15. That is, a year
 is a leap year if either (i) it is divisible by 4 but not by 100 or (ii)
 it is divisible by 400.
 - `noleap` or `365_day`:
 Gregorian calendar without leap years, i.e., all years are 365 days long.
 - `all_leap` or `366_day`:
 Gregorian calendar with every year being a leap year, i.e.,
 all years are 366 days long.
 -`360_day`:
 All years are 360 days divided into 30 day months.
 -`julian`:
 Proleptic Julian calendar, extended to dates after 1582-10-5. A year is a
 leap year if it is divisible by 4.

@keyword only_use_cftime_datetimes: if False, datetime.datetime
objects are returned from num2date where possible; if True dates which subclass
cftime.datetime are returned for all calendars. Default True.

@keyword only_use_python_datetimes: always return python datetime.datetime
objects and raise an error if this is not possible. Ignored unless
**only_use_cftime_datetimes=False**. Default **False**.

@returns: A class instance which may be used for converting times from netCDF
units to datetime objects.
        """
        calendar = calendar.lower()
        if calendar in _calendars:
            self.calendar = calendar
        else:
            raise ValueError(
                "calendar must be one of %s, got '%s'" % (str(_calendars), calendar))
        self.origin = _dateparse(unit_string,calendar=calendar)
        units, isostring = _datesplit(unit_string)
        self.units = units
        self.unit_string = unit_string
        self.only_use_cftime_datetimes = only_use_cftime_datetimes
        self.only_use_python_datetimes = only_use_python_datetimes

    def date2num(self, date):
        """
        Returns `time_value` in units described by `unit_string`, using
        the specified `calendar`, given a 'datetime-like' object.

        The datetime object must represent UTC with no time-zone offset.
        If there is a time-zone offset implied by L{unit_string}, it will
        be applied to the returned numeric values.

        Resolution is approximately a microsecond.

        If calendar = 'standard' or 'gregorian' (indicating
        that the mixed Julian/Gregorian calendar is to be used), an
        exception will be raised if the 'datetime-like' object describes
        a date between 1582-10-5 and 1582-10-15.

        Works for scalars, sequences and numpy arrays.
        Returns a scalar if input is a scalar, else returns a numpy array.
        """
        return date2num(date,self.unit_string,calendar=self.calendar)

    def num2date(self, time_value):
        """
        Return a 'datetime-like' object given a `time_value` in units
        described by `unit_string`, using `calendar`.

        dates are in UTC with no offset, even if L{unit_string} contains
        a time zone offset from UTC.

        Resolution is approximately a microsecond.

        Works for scalars, sequences and numpy arrays.
        Returns a scalar if input is a scalar, else returns a numpy array.
        """
        return num2date(time_value,self.unit_string,calendar=self.calendar,only_use_cftime_datetimes=self.only_use_cftime_datetimes,only_use_python_datetimes=self.only_use_python_datetimes)
