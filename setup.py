import os
import sys
import numpy

from setuptools import Command, Extension, setup


BASEDIR = os.path.abspath(os.path.dirname(__file__))
SRCDIR = os.path.join(BASEDIR,'src')
CMDS_NOCYTHONIZE = ['clean','clean_cython','sdist']
COMPILER_DIRECTIVES = {
    # Cython 3.0.0 changes the default of the c_api_binop_methods directive to
    # False, resulting in errors in datetime and timedelta arithmetic:
    # https://github.com/Unidata/cftime/issues/271.  We explicitly set it to
    # True to retain Cython 0.x behavior for future Cython versions.  This
    # directive was added in Cython version 0.29.20.
    "c_api_binop_methods": True
}
COVERAGE_COMPILER_DIRECTIVES = {
    "linetrace": True,
    "warn.maybe_uninitialized": False,
    "warn.unreachable": False,
    "warn.unused": False,
}
DEFINE_MACROS = [("NPY_NO_DEPRECATED_API", "NPY_1_7_API_VERSION")] 
FLAG_COVERAGE = '--cython-coverage'  # custom flag enabling Cython line tracing
NAME = 'cftime'
CFTIME_DIR = os.path.join(SRCDIR, NAME)
CYTHON_FNAME = os.path.join(CFTIME_DIR, '_{}.pyx'.format(NAME))
CYTHON_CNAME = os.path.join(CFTIME_DIR, '_{}.c'.format(NAME))


class CleanCython(Command):
    description = 'Purge artifacts built by Cython'
    user_options = []

    def initialize_options(self):
        pass

    def finalize_options(self):
        pass

    def run(self):
        for rpath, _, fnames in os.walk(CFTIME_DIR):
            for fname in fnames:
                _, ext = os.path.splitext(fname)
                if ext in ('.pyc', '.pyo', '.c', '.so'):
                    artifact = os.path.join(rpath, fname)
                    if os.path.exists(artifact):
                        print('clean: removing file {!r}'.format(artifact))
                        os.remove(artifact)
                    else:
                        print('clean: skipping file {!r}'.format(artifact))


if FLAG_COVERAGE in sys.argv or os.environ.get('CYTHON_COVERAGE', None):
    COMPILER_DIRECTIVES = {
        **COMPILER_DIRECTIVES, **COVERAGE_COMPILER_DIRECTIVES
    }
    DEFINE_MACROS += [('CYTHON_TRACE', '1'),
                     ('CYTHON_TRACE_NOGIL', '1')]
    if FLAG_COVERAGE in sys.argv:
        sys.argv.remove(FLAG_COVERAGE)
    print('enable: "linetrace" Cython compiler directive')

# See https://github.com/Unidata/cftime/issues/91
if any([arg in CMDS_NOCYTHONIZE for arg in sys.argv]):
    ext_modules = []
else:
    ext_modules = [Extension('{}._{}'.format(NAME, NAME),
                  sources=[os.path.relpath(CYTHON_FNAME, BASEDIR)],
                  define_macros=DEFINE_MACROS,
                  include_dirs=[numpy.get_include(),])]
    for e in ext_modules:
        e.cython_directives = {'language_level': "3"} 
        e.compiler_directives = COMPILER_DIRECTIVES

if 'sdist' not in sys.argv[1:] and 'clean' not in sys.argv[1:] and '--version' not in sys.argv[1:]:
    # remove _cftime.c file if it exists, so cython will recompile _cftime.pyx.
    # run for build *and* install (issue #263). Otherwise 'pip install' will
    # not regenerate _cftime.c, even if the C lib supports the new features.
    if len(sys.argv) >= 2:
        if os.path.exists(CYTHON_CNAME):
            os.remove(CYTHON_CNAME)

setup(
    cmdclass={'clean_cython': CleanCython},
    ext_modules=ext_modules,
)
