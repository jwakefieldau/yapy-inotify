from distutils.core import setup
from distutils.extension import Extension
from Cython.Build import cythonize

setup(
	# how does name= affect things?
	name='inotify',
	install_requires='Cython>=0.20.2'
	ext_modules=cythonize([Extension('inotify', ['inotify.pyx'])]),
)
