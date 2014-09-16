cimport inotify
cimport posix.unistd

import os

# masks
dir_masks_by_name = {
	'IN_CREATE': 0x00000100,
}

file_masks_by_name = {
	'IN_ACCESS': 0x00000001,
}

dir_masks_by_val = invert_dict(dir_masks_by_name)
file_masks_by_val = invert_dict(file_masks_by_name)

all_masks_by_name = dir_masks_by_name + file_masks_by_name
all_masks_by_val = invert_dict(all_masks_by_name)

def invert_dict(d):
	return {v: k for (k, v) in d.iteritems()}

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
	if not all_masks_by_val.has_key(mask):
		raise ValueError("%d is not a valid mask" % (mask))
	return inotify_add_watch(fd, path, mask)

def add_tree_watch(fd, path, mask):
	# walk the tree rooted at path and add watches
	# if the masks are for directories, only add them to directories
	# if the masks are for files, add them to files
	# if for both, etc.

	#TODO - need to watch (IN_CREATE | any_other_dir_masks) on all subdirs so that we can apply
	# the mask to new subdirs or files as they are created.
	#NOTE - maybe this is a good case for the EventDispatcher class - to maintain the necessary
	# state to enable this?
	
	is_file_mask = file_masks_by_val.has_key(mask)
	if is_file_mask:
		is_dir_mask = False
	else:	
		is_dir_mask = dir_masks_by_val.has_key(mask)

	if (not is_file_mask) and (not is_dir_mask):
		raise ValueError("%d is not a valid mask" % (mask))

	for (root, dirnames, filenames) in os.walk(path):
		if is_file_mask:
			for filename in filenames:
				#TODO do something with wd
				wd = add_watch(fd, os.path.join(root, filename), mask)
			dir_mask = dir_masks_by_name['IN_CREATE']
		elif is_dir_mask:
			dir_mask = mask | dir_masks_by_name['IN_CREATE']
		else:
			# this is accounted for above, by raising ValueError
			pass
		for dirname in dirnames:
			#TODO - do something with wd
			wd = add_watch(fd, os.path.join(root, dirname), dir_mask)
					

def rm_watch(wd, mask_name):
	if not all_masks_by_val.has_key(mask):
		raise ValueError("%d is not a valid mask" % (mask))
	return inotify_rm_watch(wd, all_masks_by_name[mask_name])

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
				mask_name=all_masks_by_val[event_buf[i].mask],
				cookie=event_buf[i].cookie,
				name=event_buf[i].name[:event_buf[i].len]
			)
			yield e	
			
			processed_len += (sizeof(event_buf[i]) + event_buf[i].len)
			i += 1

