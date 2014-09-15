from distutils.core import setup
from distutils.extension import Extension
from Cython.Build import cythonize

setup(
	name='inotify',
	ext_modules=cythonize([Extension('inotify', ['inotify.pyx'])]),
)
