# yapy-inotify

yapy-inotify is yet another python wrapper for inotify, written with much the same
motivation as the others - I didn't like them.

Cython is required to build this, as it handles the Python <-> libc interface.

Recursive directory watching is supported, with the usual caveat that due to
the design of inotify in the kernel, there are unavoidable race conditions.  It is
possible for a file to be created and removed so quickly that we are unable to 
add any watches to it before it is removed, or before other events may have occurred
on it.  When new sub-directories are created in recursively-watched directories,
watches are attempted to be added recursively in any sub(^n)-directories that may already
exist in the new sub-directory, in case they were created before the new watch could
be added.

An EventDispatcher object represents a single inotify instance, to which Watch
objects can be added or removed.  Event objects are yielded by the gen_events()
generator when read from inotify, until EventDispatcher.close() is called.

This is not thread-safe, but probably could be made so if an application
requiring thread-safety is imagined.

## example

See the examples/ directory

## install

python ./setup.py install

## tests

Test suite in test.py
