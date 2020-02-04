Installation
============

Required dependencies
---------------------

- Python 2.7, 3.4, 3.5, or 3.6
- `numpy <http://www.numpy.org/>`__ (1.7 or later)


Instructions
------------

The easiest way to get everything installed is to use conda_ command line tool::

    $ conda install cftime

.. _conda: http://conda.io/

We recommend using the community maintained `conda-forge <https://conda-forge.github.io/>`__ channel if you need difficult\-to\-build dependencies such as cartopy or pynio::

    $ conda install -c conda-forge cftime

New releases may also appear in conda-forge before being updated in the default
channel.

If you don't use conda, be sure you have the required dependencies (numpy and
cython) installed first. Then, install cftime with pip::

    $ pip install cftime


Developing
----------


When developing we recommend cloning the GitHub repository,
building the extension in-place with `cython <http://cython.org/>`__ 0.19 or later
``python setup.py build_ext --inplace``

and running the test suite to check if the changes are passing the tests
``pytest --pyargs test``
