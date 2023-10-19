import os
import sys
import numpy

from setuptools import Command, Extension, setup

# https://github.com/Unidata/cftime/issues/34
try:
    from Cython.Build import cythonize
except ImportError:
    cythonize = False


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


def extract_version():
    version = None
    with open(CYTHON_FNAME) as fi:
        for line in fi:
            if (line.startswith('__version__')):
                _, version = line.split('=')
                version = version.strip()[1:-1]  # Remove quotation characters.
                break
    return version


def load(fname):
    result = []
    with open(fname, 'r') as fi:
        result = [package.strip() for package in fi.readlines()]
    return result


def description():
    fname = os.path.join(BASEDIR, 'README.md')
    with open(fname, 'r') as fi:
        result = ''.join(fi.readlines())
    return result


if ((FLAG_COVERAGE in sys.argv or os.environ.get('CYTHON_COVERAGE', None))
    and cythonize):
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
    extension = Extension('{}._{}'.format(NAME, NAME),
                          sources=[CYTHON_FNAME],
                          define_macros=DEFINE_MACROS,
                          include_dirs=[numpy.get_include(),])
    ext_modules = [extension]
    if cythonize:
        ext_modules = cythonize(extension,
                                compiler_directives=COMPILER_DIRECTIVES,
                                language_level=3)

setup(
    name=NAME,
    author='Jeff Whitaker',
    author_email='jeffrey.s.whitaker@noaa.gov',
    description='Time-handling functionality from netcdf4-python',
    long_description=description(),
    long_description_content_type='text/markdown',
    cmdclass={'clean_cython': CleanCython},
    packages=[NAME],
    package_dir={'':'src'},
    version=extract_version(),
    ext_modules=ext_modules,
    install_requires=load('requirements.txt'),
    tests_require=load('requirements-dev.txt'),
    license='License :: OSI Approved :: MIT License',
    python_requires=">=3.8",
    classifiers=[
        'Development Status :: 5 - Production/Stable',
        'Operating System :: MacOS :: MacOS X',
        'Operating System :: Microsoft :: Windows',
        'Operating System :: POSIX :: Linux',
        'Programming Language :: Python',
        'Programming Language :: Python :: 3',
        'Programming Language :: Python :: 3.8',
        'Programming Language :: Python :: 3.9',
        'Programming Language :: Python :: 3.10',
        'Programming Language :: Python :: 3.11',
        'Programming Language :: Python :: 3.12',
        'Topic :: Scientific/Engineering',
        'License :: OSI Approved :: MIT License'],
    )
