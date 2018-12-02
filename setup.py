from __future__ import print_function

import os
import sys

from Cython.Build import cythonize
from setuptools import Command, Extension, setup


COMPILER_DIRECTIVES = {}
DEFINE_MACROS = None
FLAG_COVERAGE = '--cython-coverage'  # custom flag enabling Cython line tracing
BASEDIR = os.path.abspath(os.path.dirname(__file__))
NAME = 'cftime'
CFTIME_DIR = os.path.join(BASEDIR, NAME)
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


if FLAG_COVERAGE in sys.argv or os.environ.get('CYTHON_COVERAGE', None):
    COMPILER_DIRECTIVES = {'linetrace': True,
                           'warn.maybe_uninitialized': False,
                           'warn.unreachable': False,
                           'warn.unused': False}
    DEFINE_MACROS = [('CYTHON_TRACE', '1'),
                     ('CYTHON_TRACE_NOGIL', '1')]
    if FLAG_COVERAGE in sys.argv:
        sys.argv.remove(FLAG_COVERAGE)
    print('enable: "linetrace" Cython compiler directive')

extension = Extension('{}._{}'.format(NAME, NAME),
                      sources=[CYTHON_FNAME],
                      define_macros=DEFINE_MACROS)

setup(
    name=NAME,
    author='Jeff Whitaker',
    author_email='jeffrey.s.whitaker@noaa.gov',
    description='Time-handling functionality from netcdf4-python',
    long_description=description(),
    long_description_content_type='text/markdown',
    cmdclass={'clean_cython': CleanCython},
    packages=[NAME],
    version=extract_version(),
    ext_modules=cythonize(extension,
                          compiler_directives=COMPILER_DIRECTIVES,
                          language_level=2),
    setup_requires=load('setup.txt'),
    install_requires=load('requirements.txt'),
    tests_require=load('requirements-dev.txt'),
    test_suite='tests')
