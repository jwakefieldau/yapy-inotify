cimport inotify
cimport posix.unistd

import os

# masks
IN_CREATE = 0x00000100
IN_ACCESS = 0x00000001

file_mask_list = [
	IN_ACCESS,
]

dir_mask_list = [
	IN_CREATE,
]

all_file_masks = 0
for mask in file_mask_list:
	all_file_masks |= mask

all_dir_masks = 0
for mask in dir_mask_list:
	all_dir_masks |= mask


#TODO - do we need an EventDispatcher class or is that pointless abstraction?
#might it help with matching up MOVED_FROM/MOVED_TO ?  Is that even necessary? 

#TODO - make syscall wrappers raise exceptions on invalid arguments etc,
# and general -1 return conditions

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
	# extract the file and dir mask from the mask passed, OR IN_CREATE with the dir mask
	# so that new dirs can be picked up and masks added to files and subdirs
	# walk the tree rooted at path and add watches

	#NOTE - maybe this is a good case for the EventDispatcher class - to maintain the necessary
	# state to enable this? ie: to match events read against a tree watch
	
	file_mask = mask & all_file_masks
	dir_mask = mask & all_dir_masks

	for (root, dirnames, filenames) in os.walk(path):
		if file_mask > 0:
			for filename in filenames:
				#TODO do something with wd
				wd = add_watch(fd, os.path.join(root, filename), file_mask)
			dir_mask |= IN_CREATE
		for dirname in dirnames:
			#TODO - do something with wd
			wd = add_watch(fd, os.path.join(root, dirname), dir_mask)
					

def rm_watch(wd, mask):
	return inotify_rm_watch(wd, mask)

def gen_read_events(fd):
	#TODO should read buffer size be configurable?
	# should I go back to reading into a char * buf?
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

			#TODO - associate this event with any tree watches via wd?
			# if it's an IN_CREATE for a new dir under tree, add the tree watch's dir mask
			# if it's an IN_CREATE for a new file under tree and the tree watch has a file mask,
			# add that to the new file

			e = Event(
				wd=event_buf[i].wd,
				mask=event_buf[i].mask,
				cookie=event_buf[i].cookie,
				name=event_buf[i].name[:event_buf[i].len]
			)
			yield e	
			
			processed_len += (sizeof(event_buf[i]) + event_buf[i].len)
			i += 1

