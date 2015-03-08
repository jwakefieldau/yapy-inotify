# python-inotify

python-inotify is yet another python wrapper for inotify, written with much the same
motivation as the others - I didn't like them.

Cython is required to build this, as it handles the Python <-> libc interface.

Recursive directory watching is supported, with the usual caveat that due to
the design of inotify in the kernel, there are unavoidable race conditions.


## example
from inotify import EventDispatcher

ed = EventDispatcher()
ed.add_watch( -- TAKE FROM EXAMPLES ON LAPTOP
