# Based on calcalcs http://meteora.ucsd.edu/~pierce/calcalcs

# Following are number of Days Per Month (dpm).
dpm      = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
dpm_leap = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
# Same as above, but SUM of previous months (no leap years).
spm_365day = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334, 365]
spm_366day = [0, 31, 60, 91, 121, 152, 182, 213, 244, 274, 305, 335, 366]

def is_leap(year, calendar):
    if calendar not in ['julian','gregorian','mixed']:
        raise ValueError('unsupported calendar')
    if year == 0:
        raise ValueError('year zero does not exist in the %s calendar' %\
                calendar)
    # Because there is no year 0 in the Julian calendar, years -1, -5, -9, etc
    # are leap years.
    if year < 0:
        tyear = year + 1
    else:
        tyear = year
    if calendar == 'gregorian' or (calendar == 'mixed' and year > 1581):
         if tyear % 4: # not divisible by 4
             leap = False
         elif year % 100: # not divisible by 100
             leap = True
         elif year % 400: # not divisible by 400
             leap = False
         else:
             leap = True
    elif calendar == 'julian' or (calendar == 'mixed' and year < 1582):
         leap = tyear % 4 == 0
    return leap

def IntJulianDayFromDate(year,month,day,calendar):
    """Compute integer Julian Day from year,month,day in (proleptic) julian,
    gregorian or mixed calendars. Negative years allowed back to -4714
    (gregorian) or -4713 (mixed or julian calendar).
    integer julian day is number of days since noon UTC -4713-1-1
    in the julian or mixed julian/gregorian calendar, or noon UTC
    -4714-11-24 in the (proleptic) gregorian calendar.
    Subtract 0.5 to get 00 UTC on that day."""

    # validate inputs.
    if calendar not in ['julian','gregorian','mixed']:
        raise ValueError('unsupported calendar')
    if month < 1 or month > 12 or day < 1 or day > 31:
        msg = "date %04d-%02d-%02d does not exist in the %s calendar" %\
        (year,month,day,calendar)
        raise ValueError(msg)
    if year == 0:
        raise ValueError('year zero does not exist in the %s calendar' %\
                calendar)
    if (calendar == 'gregorian'         and year < -4714) or\
       (calendar in ['julian','mixed']  and year < -4713):
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
        dpm2use = dpm_leap
    else:
        dpm2use = dpm

    jday = day
    for m in range(month-1,0,-1):
        jday += dpm2use[m-1]

    jday_greg = jday + 365*(year-1) + (year-1)/4 - (year-1)/100 + (year-1)/400
    jday_greg -= 31739 # fix year offset
    jday_jul = jday + 365*(year-1) + (year-1)/4
    jday_jul -= 31777 # fix year offset
    if calendar == 'julian':
        return jday_jul
    elif calendar == 'gregorian':
        return jday_greg
    elif calendar == 'mixed':
        # check for invalid days in mixed calendar (there are 10 missing)
        if jday_jul >= 2299161 and jday_jul < 2299171:
            raise ValueError('invalid date in mixed calendar')
        if jday_jul <= 2299171: # 1582 October 15
            return jday_jul
        else:
            return jday_greg

    return jday

def IntJulianDayFromDate_360day(year,month,day):
    """Compute integer Julian Day from year,month,day in 
    360_day calendar"""
    return year*360 + (month-1)*30 + day - 1

def IntJulianDayFromDate_365day(year,month,day):
    """Compute integer Julian Day from year,month,day in 
    365_day calendar"""
    if month == 2 and day == 29:
        raise ValueError('no leap days in 365_day calendar')
    return year*365 + spm_365day[month-1] + day - 1

def IntJulianDayFromDate_366day(year,month,day):
    """Compute integer Julian Day from year,month,day in 
    366_day calendar"""
    return year*366 + spm_366day[month-1] + day - 1

def IntJulianDayToDate(jday):

    # Make first estimate for year. subtract 4714 or 4713 because Julian Day number
    # 0 occurs in year 4714 BC in the Gregorian calendar and 4713 BC in the
    # Julian calendar.
    if calendar == 'gregorian':
        year = jday/366 - 4714
    elif calendar in ['mixed','julian']:
        year = jday/366 - 4713;

    # Advance years until we find the right one
    yp1 = year + 1
    if yp1 == 0:
       yp1 = 1 # no year 0
    jday = IntJulianDayFromDate(yp1,1,1,calendar)
    while jday >= tjday:
        year += 1
        if year == 0:
            year = 1
        yp1 = year + 1
        if yp1 == 0:
            yp1 = 1
        tjday = IntJulianDayFromDate(yp1,1,1,calendar)
    if is_leap(year, calendar):
        dpm2use = dpm_leap
    else:
        dpm2use = dpm
    month = 1
    tjday = IntJulianDayFromDate(year,month,dpm2use[month-1],calendar)
    while jday > tjday:
        month += 1
        tjday = IntJulianDayFromDate(year,month,dpm2use[month-1],calendar)
    tjday = IntJulianDayFromDate(year,month,1,tjday,calendar)
    day = jday - tjday + 1
    return year,month,day

if __name__ == "__main__":
    import sys
    year = int(sys.argv[1])
    month = int(sys.argv[2])
    day = int(sys.argv[3])
    calendar = sys.argv[4]
    print 'Julian Day %s-%s-%s in %s calendar = %s' %\
    (year,month,day,calendar,IntJulianDayFromDate(year,month,day,calendar))
