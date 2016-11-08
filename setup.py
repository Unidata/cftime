from distutils.core import setup
from Cython.Build import cythonize

setup()

setup(
    name='netcdftime',
    author='Jeff Whit',
    author_email='lapok@atmos.washington.edu',
    description='Time-handling functionality from netcdf4-python',
    packages=['netcdftime'],
    version='0.0',
    ext_modules=cythonize("netcdftime/*.pyx"),
    install_requires=['numpy', 'Cython'],
    tests_require=['pytest'])
