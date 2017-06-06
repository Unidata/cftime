import os
from distutils.core import setup
from Cython.Build import cythonize


rootpath = os.path.abspath(os.path.dirname(__file__))


def extract_version(module='netcdftime'):
    version = None
    fname = os.path.join(rootpath, module, '_netcdftime.pyx')
    with open(fname) as f:
        for line in f:
            if (line.startswith('__version__')):
                _, version = line.split('=')
                version = version.strip()[1:-1]  # Remove quotation characters.
                break
    return version


with open('requirements.txt') as f:
    tests_require = f.readlines()
install_requires = [t.strip() for t in tests_require]

setup(
    name='netcdftime',
    author='Jeff Whit',
    author_email='lapok@atmos.washington.edu',
    description='Time-handling functionality from netcdf4-python',
    packages=['netcdftime'],
    version=extract_version(),
    ext_modules=cythonize('netcdftime/*.pyx'),
    install_requires=install_requires,
    tests_require=['pytest'])
