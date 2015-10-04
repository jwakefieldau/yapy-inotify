from distutils.core import setup
from distutils.extension import Extension
from Cython.Build import cythonize

setup(
	name='yapy-inotify',
	version='0.01',
	requires=[
		'Cython',
	],
	ext_modules=cythonize([Extension('inotify', ['inotify.pyx'])]),
)
