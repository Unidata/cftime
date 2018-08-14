import os

from setuptools import Extension, setup

rootpath = os.path.abspath(os.path.dirname(__file__))


def extract_version(module='cftime'):
    version = None
    fname = os.path.join(rootpath, module, '_cftime.pyx')
    with open(fname) as f:
        for line in f:
            if (line.startswith('__version__')):
                _, version = line.split('=')
                version = version.strip()[1:-1]  # Remove quotation characters.
                break
    return version


with open('requirements.txt') as f:
    reqs = f.readlines()
install_requires = [req.strip() for req in reqs]

with open('requirements-dev.txt') as f:
    reqs = f.readlines()
tests_require = [req.strip() for req in reqs]

setup(
    name='cftime',
    author='Jeff Whitaker',
    author_email='jeffrey.s.whitaker@noaa.gov',
    description='Time-handling functionality from netcdf4-python',
    packages=['cftime'],
    version=extract_version(),
    ext_modules=[Extension('cftime._cftime', sources=['cftime/_cftime.pyx'])],
    setup_requires=['setuptools>=18.0', 'cython>=0.19'],
    install_requires=install_requires,
    tests_require=tests_require)
