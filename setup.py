from __future__ import print_function

import os
import sys
import numpy

from setuptools import setup

BASEDIR = os.path.abspath(os.path.dirname(__file__))
NAME = 'cftime'
CFTIME_DIR = os.path.join(BASEDIR, NAME)
FNAME = os.path.join(CFTIME_DIR, '_{}.py'.format(NAME))

def extract_version():
    version = None
    with open(FNAME) as fi:
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

setup(
    name=NAME,
    author='Jeff Whitaker',
    author_email='jeffrey.s.whitaker@noaa.gov',
    description='Time-handling functionality from netcdf4-python',
    long_description=description(),
    long_description_content_type='text/markdown',
    packages=[NAME],
    version=extract_version(),
    install_requires=load('requirements.txt'),
    tests_require=load('requirements-dev.txt'),
    classifiers=[
        'Development Status :: 5 - Production/Stable',
        'Operating System :: MacOS :: MacOS X',
        'Operating System :: Microsoft :: Windows',
        'Operating System :: POSIX :: Linux',
        'Programming Language :: Python',
        'Programming Language :: Python :: 2.7',
        'Programming Language :: Python :: 3',
        'Programming Language :: Python :: 3.6',
        'Programming Language :: Python :: 3.7',
        'Programming Language :: Python :: 3.8',
        'Topic :: Scientific/Engineering',
        'License :: OSI Approved :: GNU General Public License v3 (GPLv3)']
    )
