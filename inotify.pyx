cimport inotify
cimport posix.unistd

import os

# masks
IN_CREATE = 0x00000100

dir_masks = [
	IN_CREATE,
]

#TODO - do we need an EventDispatcher class or is that pointless abstraction?
#might it help with matching up MOVED_FROM/MOVED_TO ?  Is that even necessary? 

class Event(object):
	wd = None
	mask = None
	cookie = None
	name = None

	def __init__(self, **kwargs):
		for (k, v) in kwargs.items():
			setattr(self, k, v)


def init():
	return inotify_init()

# does path need to be made persistent?
def add_watch(fd, path, mask):
	return inotify_add_watch(fd, path, mask)

def add_tree_watch(fd, path, mask):
	# walk the tree rooted at path and add watches
	# if the masks are for directories, only add them to directories
	# if the masks are for files, add them to files
	# if for both, etc.

	#TODO - need to watch (IN_CREATE | mask) on all subdirs so that we can apply
	# the mask to new subdirs as they are created.
	#NOTE - maybe this is a good case for the EventDispatcher class - to maintain the necessary
	# state to enable this?

	for (root, dirnames, filenames) in os.walk(path):
		#MARK
		pass

def rm_watch(wd, mask):
	return inotify_rm_watch(wd, mask)

def gen_read_events(fd):
	# should nunber of events to read at once be configurable?
	cdef inotify_event event_buf[16]
	cdef ssize_t read_len = 0
	cdef ssize_t processed_len = 0
	cdef unsigned int i = 0


	while True:
		# this read() will return immediately if there are any events to consume,
		# it won't block waiting to fill the buffer completely
		read_len = posix.unistd.read(fd, event_buf, 16 * sizeof(inotify_event))
		if read_len < 0:

			#TODO not sure this is the right way to raise exceptions
			raise IOError("read() returned %d" % (read_len))

		while (processed_len < read_len): 

			# NOTE - cython's sizeof() only evaluates the static size of the type
			# of its argument.  Since .name is a char[] in libc, it is considered
			# by sizeof() to occupy no space

			# make sure the name string is copied properly - test by consuming all
			# 16 events in buffer and reading again

			# Cython docs say the fastest way to copy C strings to Python 
			# is by slicing the length so it doesn't need to call strlen()
			e = Event(
				wd=event_buf[i].wd,
				mask=event_buf[i].mask,
				cookie=event_buf[i].cookie,
				name=event_buf[i].name[:event_buf[i].len]
			)
			yield e	
			
			processed_len += (sizeof(event_buf[i]) + event_buf[i].len)
			i += 1

