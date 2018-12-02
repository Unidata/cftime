from cftime import num2date, date2num
try:
    from time import perf_counter
except ImportError:
    from time import clock as perf_counter
import numpy as np
units = 'hours since 01-01-01'
calendar = 'standard'
timevals = np.arange(0,10000,1)
print('processing %s values...' % len(timevals))
t1 = perf_counter()
dates =\
num2date(timevals,units=units,calendar=calendar,only_use_cftime_datetimes=True)
t2 = perf_counter()
t = t2-t1
print('num2date took %s seconds' % t)
timevals2 = date2num(dates,units=units,calendar=calendar)
t1 = perf_counter()
t = t1-t2
print('date2num took %s seconds' % t)
