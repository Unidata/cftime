"""stripped-down version of _strptime.py from C python"""
from re import compile as re_compile
from re import IGNORECASE
from re import escape as re_escape
from _thread import allocate_lock as _thread_allocate_lock

__all__ = []

class TimeRE(dict):
    """Handle conversion from format directives to regexes."""

    def __init__(self):
        """Create keys/values.

        Order of execution is important for dependency reasons.

        """
        base = super()
        base.__init__({
            # The " [1-9]" part of the regex is to make %c from ANSI C work
            'd': r"(?P<d>3[0-1]|[1-2]\d|0[1-9]|[1-9]| [1-9])",
            'f': r"(?P<f>[0-9]{1,6})",
            'H': r"(?P<H>2[0-3]|[0-1]\d|\d)",
            'I': r"(?P<I>1[0-2]|0[1-9]|[1-9])",
            'm': r"(?P<m>1[0-2]|0[1-9]|[1-9])",
            'M': r"(?P<M>[0-5]\d|\d)",
            'S': r"(?P<S>6[0-1]|[0-5]\d|\d)",
            'y': r"(?P<y>\d\d)",
#           'Y': r"(?P<Y>\d\d\d\d)",
            'Y': r"(?P<Y>[+-]?[0-9]+)", # handle neg and > 4 digits
            '%': '%'})

    def pattern(self, format):
        """Return regex pattern for the format string.
        Need to make sure that any characters that might be interpreted as
        regex syntax are escaped.
        """
        processed_format = ''
        # The sub() call escapes all characters that might be misconstrued
        # as regex syntax.  Cannot use re.escape since we have to deal with
        # format directives (%m, etc.).
        regex_chars = re_compile(r"([\\.^$*+?\(\){}\[\]|])")
        format = regex_chars.sub(r"\\\1", format)
        whitespace_replacement = re_compile(r'\s+')
        format = whitespace_replacement.sub(r'\\s+', format)
        while '%' in format:
            directive_index = format.index('%')+1
            processed_format = "%s%s%s" % (processed_format,
                                           format[:directive_index-1],
                                           self[format[directive_index]])
            format = format[directive_index+1:]
        return "%s%s" % (processed_format, format)

    def compile(self, format):
        """Return a compiled re object for the format string."""
        return re_compile(self.pattern(format), IGNORECASE)

_cache_lock = _thread_allocate_lock()
# DO NOT modify _TimeRE_cache or _regex_cache without acquiring the cache lock
# first!
_TimeRE_cache = TimeRE()
_CACHE_MAX_SIZE = 5 # Max number of regexes stored in _regex_cache
_regex_cache = {}

def _strptime(data_string, format="%a %b %d %H:%M:%S %Y"):
    """Return a 2-tuple consisting of a time struct and an int containing
    the number of microseconds based on the input string and the
    format string."""

    for index, arg in enumerate([data_string, format]):
        if not isinstance(arg, str):
            msg = "strptime() argument {} must be str, not {}"
            raise TypeError(msg.format(index, type(arg)))

    global _TimeRE_cache, _regex_cache
    with _cache_lock:
        if len(_regex_cache) > _CACHE_MAX_SIZE:
            _regex_cache.clear()
        format_regex = _regex_cache.get(format)
        if not format_regex:
            try:
                format_regex = _TimeRE_cache.compile(format)
            # KeyError raised when a bad format is found; can be specified as
            # \\, in which case it was a stray % but with a space after it
            except KeyError as err:
                bad_directive = err.args[0]
                if bad_directive == "\\":
                    bad_directive = "%"
                del err
                raise ValueError("'%s' is a bad directive in format '%s'" %
                                    (bad_directive, format)) from None
            # IndexError only occurs when the format string is "%"
            except IndexError:
                raise ValueError("stray %% in format '%s'" % format) from None
            _regex_cache[format] = format_regex
    found = format_regex.match(data_string)
    if not found:
        raise ValueError("time data %r does not match format %r" %
                         (data_string, format))
    if len(data_string) != found.end():
        raise ValueError("unconverted data remains: %s" %
                          data_string[found.end():])

    month = day = 1
    hour = minute = second = fraction = 0
    found_dict = found.groupdict()
    for group_key in found_dict.keys():
        if group_key == 'y':
            year = int(found_dict['y'])
            if year <= 68:
                year += 2000
            else:
                year += 1900
        elif group_key == 'Y':
            year = int(found_dict['Y'])
        elif group_key == 'm':
            month = int(found_dict['m'])
        elif group_key == 'd':
            day = int(found_dict['d'])
        elif group_key == 'H':
            hour = int(found_dict['H'])
        elif group_key == 'I':
            hour = int(found_dict['I'])
            ampm = found_dict.get('p', '').lower()
        elif group_key == 'M':
            minute = int(found_dict['M'])
        elif group_key == 'S':
            second = int(found_dict['S'])
        elif group_key == 'f':
            s = found_dict['f']
            # Pad to always return microseconds.
            s += "0" * (6 - len(s))
            fraction = int(s)

    return year,month,day,hour,minute,second,fraction
