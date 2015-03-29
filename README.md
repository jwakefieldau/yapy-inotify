# python-inotify

python-inotify is yet another python wrapper for inotify, written with much the same
motivation as the others - I didn't like them.

Cython is required to build this, as it handles the Python <-> libc interface.

Recursive directory watching is supported, with the usual caveat that due to
the design of inotify in the kernel, there are unavoidable race conditions.  It is
possible for a file to be created and removed so quickly that we are unable to 
add any watches to it before it is removed.

## example

See the examples/ directory

## tests

Test suite in test.py
