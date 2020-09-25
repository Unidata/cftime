import numpy as np
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

def is_leap_julian(year):
    "Return 1 if year is a leap year in the Julian calendar, 0 otherwise."
    return _is_leap(year, calendar='julian')

def is_leap_proleptic_gregorian(year):
    "Return 1 if year is a leap year in the Proleptic Gregorian calendar, 0 otherwise."
    return _is_leap(year, calendar='proleptic_gregorian')

def is_leap_gregorian( year):
    "Return 1 if year is a leap year in the Gregorian calendar, 0 otherwise."
    return _is_leap(year, calendar='standard')

def all_leap(year):
    "Return True for all years."
    return True

def no_leap(year):
    "Return False for all years."
    return False

cdef month_lengths(is_leap, year):
    if is_leap(year):
        return _dpm_leap
    else:
        return _dpm

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
def add_timedelta(dt, delta, is_leap, julian_gregorian_mixed, has_year_zero):
    cdef int microsecond, second, minute, hour, day, month, year
    cdef int delta_microseconds, delta_seconds, delta_days
    cdef int[12] month_length
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
                if year == 0 and not has_year_zero:
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

    return (year, month, day, hour, minute, second, microsecond, -1, -1)

# Add a datetime.timedelta to a cftime.datetime instance with the 360_day calendar.
#
# Assumes that the 360_day,365_day and 366_day calendars (unlike the rest of supported
# calendars) have the year 0. Also, there are no leap years and all
# months are 30 days long, so we can compute month and year by using
# "//" and "%".
def add_timedelta_360_day(dt, delta):
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

    return (year, month, day, hour, minute, second, microsecond, -1, -1)

# Calendar calculations base on calcals.c by David W. Pierce
# http://meteora.ucsd.edu/~pierce/calcalcs

def _is_leap(int year, calendar):
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
        elif tyear % 100: # not divisible by 100
            leap = True
        elif tyear % 400: # not divisible by 400
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

def _IntJulianDayFromDate(int year,int month,int day,calendar,skip_transition=False):
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

def _IntJulianDayToDate(int jday,calendar,skip_transition=False):
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
