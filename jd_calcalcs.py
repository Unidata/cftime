# Based on calcalcs http://meteora.ucsd.edu/~pierce/calcalcs

# Following are number of Days Per Month (dpm).
dpm = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
dpm_leap = [ 31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
# Same as above, but SUM of previous months (no leap years).
spm = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334, 365]

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
         if tyear % 4:
             leap = False
         elif year % 100:
             leap = True
         elif year % 400:
             leap = False
         else:
             leap = True
    elif calendar == 'julian' or (calendar == 'mixed' and year < 1582):
         leap = tyear % 4 == 0
    return leap

def IntJulianDayFromDate(year,month,day,calendar):
    """Compute integer Julian Day from year,month,day in proleptic julian,
    gregorian or mixed calendars. Negative years allowed back to -4714 (gregorian) or -4713
    (mixed or julian calendar)."""
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

    # add year offset
    if year < 0:
        year += 4801
    else:
        year += 4800

    if is_leap(year,calendar):
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

if __name__ == "__main__":
    import sys
    year = int(sys.argv[1])
    month = int(sys.argv[2])
    day = int(sys.argv[3])
    calendar = sys.argv[4]
    print 'Julian Day %s-%s-%s in %s calendar = %s' %\
    (year,month,day,calendar,IntJulianDayFromDate(year,month,day,calendar))
