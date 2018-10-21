from cftime import num2date, date2num
import time
import numpy as np
units = 'hours since 01-01-01'
calendar = 'standard'
timevals = np.arange(0,10000,1)
print('processing %s values...' % len(timevals))
t1 = time.clock()
dates =\
num2date(timevals,units=units,calendar=calendar,only_use_cftime_datetimes=True)
t2 = time.clock()
t = t2-t1
print('num2date took %s seconds' % t)
timevals2 = date2num(dates,units=units,calendar=calendar)
t1 = time.clock()
t = t1-t2
print('date2num took %s seconds' % t)
