# Based on calcalcs http://meteora.ucsd.edu/~pierce/calcalcs by David W.
# Pierce.

import numpy as np

# Following are number of Days Per Month (_dpm).
_dpm      = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
_dpm_leap = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
# Same as above, but SUM of previous months (no leap years).
_spm_365day = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334, 365]
_spm_366day = [0, 31, 60, 91, 121, 152, 182, 213, 244, 274, 305, 335, 366]
# supported calendars. Includes synonyms ('standard'=='gregorian',
# '366_day'=='all_leap','365_day'=='noleap')
_calendars = ['standard', 'gregorian', 'proleptic_gregorian','mixed',
              'noleap', 'julian', 'all_leap', '365_day', '366_day', '360_day']

# public functions.

def is_leap(year, calendar):
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

def IntJulianDayFromDate(year,month,day,calendar,skip_transition=False):
    """Compute integer Julian Day from year,month,day and calendar.

    Allowed calendars are 'standard','julian','proleptic_gregorian','360_day',
    '365_day' and '366_day'.

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
    leap = is_leap(year,calendar)
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

    jday_greg = jday + 365*(year-1) + (year-1)/4 - (year-1)/100 + (year-1)/400
    jday_greg -= 31739 # fix year offset
    jday_jul = jday + 365*(year-1) + (year-1)/4
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

def IntJulianDayToDate(jday,calendar,skip_transition=False):
    """Compute the year,month,day,dow,doy given the integer Julian day.
    and calendar. (dow = day of week with 0=Mon,6=Sun and doy is day of year).

    Allowed calendars are 'standard','julian','proleptic_gregorian','360_day',
    '365_day' and '366_day'.

    optional kwarg 'skip_transition':  When True, assume a 10-day
    gap in Julian day numbers between Oct 4 and Oct 15 1582 (the transition
    from Julian to Gregorian calendars).  Default False, ignored
    unless calendar = 'standard'."""

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
        year = jday/366 - 4714
    elif calendar in ['standard','julian']:
        year = jday/366 - 4713;

    # compute day of week.
    # 0 = Sunday, 6 = Sat, valid after noon UTC
    dow = np.fmod(jday + 1, 7)
    # convert to ISO 8601 (0 = Monday, 6 = Sunday), like python datetime
    dow -= 1
    if dow == -1: dow = 6

    if not skip_transition and calendar == 'standard' and jday > 2299160: jday += 10

    # Advance years until we find the right one
    yp1 = year + 1
    if yp1 == 0:
       yp1 = 1 # no year 0
    tjday = IntJulianDayFromDate(yp1,1,1,calendar,skip_transition=True)
    while jday >= tjday:
        year += 1
        if year == 0:
            year = 1
        yp1 = year + 1
        if yp1 == 0:
            yp1 = 1
        tjday = IntJulianDayFromDate(yp1,1,1,calendar,skip_transition=True)
    if is_leap(year, calendar):
        dpm2use = _dpm_leap
        spm2use = _spm_366day
    else:
        dpm2use = _dpm
        spm2use = _spm_365day
    month = 1
    tjday =\
    IntJulianDayFromDate(year,month,dpm2use[month-1],calendar,skip_transition=True)
    while jday > tjday:
        month += 1
        tjday =\
        IntJulianDayFromDate(year,month,dpm2use[month-1],calendar,skip_transition=True)
    tjday = IntJulianDayFromDate(year,month,1,calendar,skip_transition=True)
    day = jday - tjday + 1
    if month == 1:
        doy = day
    else:
        doy = spm2use[month-1]+day
    return year,month,day,dow,doy

# private functions

def _check_calendar(calendar):
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

def _IntJulianDayFromDate_360day(year,month,day):
    """Compute integer Julian Day from year,month,day in
    360_day calendar"""
    return year*360 + (month-1)*30 + day - 1

def _IntJulianDayFromDate_365day(year,month,day):
    """Compute integer Julian Day from year,month,day in
    365_day calendar"""
    if month == 2 and day == 29:
        raise ValueError('no leap days in 365_day calendar')
    return year*365 + _spm_365day[month-1] + day - 1

def _IntJulianDayFromDate_366day(year,month,day):
    """Compute integer Julian Day from year,month,day in
    366_day calendar"""
    return year*366 + _spm_366day[month-1] + day - 1

def _IntJulianDayToDate_365day(jday):
    """Compute the year,month,day given the integer Julian day
    for 365_day calendar."""

    yr_offset = 0;
    if jday < 0:
        yr_offset = -jday/365+1
        jday += 365*yr_offset
    year = jday/365
    nextra = jday - year*365
    doy    = nextra + 1 # Julday numbering starts at 0, doy starts at 1
    month = 1
    while doy > _spm_365day[month]:
        month += 1
    day = doy - _spm_365day[month-1]
    year -= yr_offset

    # compute day of week.
    # 0 = Sunday, 6 = Sat, valid after noon UTC
    dow = np.fmod(jday + 1, 7)
    # convert to ISO 8601 (0 = Monday, 6 = Sunday), like python datetime
    dow -= 1
    if dow == -1: dow = 6

    return year,month,day,dow,doy

def _IntJulianDayToDate_366day(jday):
    """Compute the year,month,day given the integer Julian day
    for 366_day calendar."""

    yr_offset = 0;
    if jday < 0:
        yr_offset = -jday/366+1
        jday += 366*yr_offset
    year = jday/366
    nextra = jday - year*366
    doy    = nextra + 1 # Julday numbering starts at 0, doy starts at 1
    month = 1
    while doy > _spm_366day[month]:
        month += 1
    day = doy - _spm_366day[month-1]
    year -= yr_offset

    # compute day of week.
    # 0 = Sunday, 6 = Sat, valid after noon UTC
    dow = np.fmod(jday + 1, 7)
    # convert to ISO 8601 (0 = Monday, 6 = Sunday), like python datetime
    dow -= 1
    if dow == -1: dow = 6

    return year,month,day,dow,doy

def _IntJulianDayToDate_360day(jday):
    """Compute the year,month,day given the integer Julian day
    for 360_day calendar."""

    yr_offset = 0;
    if jday < 0:
        yr_offset = -jday/360+1
        jday += 360*yr_offset
    year = jday/360
    nextra = jday - year*360
    doy    = nextra + 1 # Julday numbering starts at 0, doy starts at 1
    month = nextra/30 + 1
    day   = doy - (month-1)*30
    year -= yr_offset

    # compute day of week.
    # 0 = Sunday, 6 = Sat, valid after noon UTC
    dow = np.fmod(jday + 1, 7)
    # convert to ISO 8601 (0 = Monday, 6 = Sunday), like python datetime
    dow -= 1
    if dow == -1: dow = 6

    return year,month,day,dow,doy

if __name__ == "__main__":
    import sys
    year = int(sys.argv[1])
    month = int(sys.argv[2])
    day = int(sys.argv[3])
    calendar = sys.argv[4]
    jday = IntJulianDayFromDate(year,month,day,calendar)
    print 'Julian Day %s-%s-%s in %s calendar = %s' %\
    (year,month,day,calendar,jday)
    yr,mon,dy,dow,doy = IntJulianDayToDate(jday,calendar)
    print 'round trip date = %s-%s-%s' %\
    (yr,mon,dy)
    print('day of week = %s, day of year %s' % (dow,doy))
