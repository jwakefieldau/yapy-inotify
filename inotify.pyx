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


#TODO - make syscall wrappers raise exceptions on invalid arguments etc,
# and general -1 return conditions

def set_attrs_from_kwargs(obj, **kwargs):
	for (k, v) in kwargs.items():
		if hasattr(obj, k):
			setattr(obj, k, v)

class Event(object):
	wd = None
	mask = None
	cookie = None
	name = None
	watch_obj = None

	def __init__(self, **kwargs):
		set_attrs_from_kwargs(self, **kwargs)

class Watch(object):
	mask = None
	path = None
	wd = None

	def __init__(self, **kwargs):
		set_attrs_from_kwargs(self, **kwargs)


class EventDispatcher(object):
	wd_list = []
	inotify_fd = None
	blocking_read = True

	def __init__(self, blocking_read=True):

		# determine how big wd_list needs to be
		with open('/proc/sys/fs/inotify/max_user_watches') as f_obj:
			max_user_watches = int(f_obj.readline().strip())

		self.wd_list = [None] * max_user_watches
		self.inotify_fd = inotify_init()
		self.blocking_read = blocking_read
		
	def add_watch(self, watch_obj):

		#TODO - test that watch_obj.callback is actually callable

		#NOTE - there is an obvious pseudo-"race" condition in that there is 
		# time between adding a watch and reading events for it.  The generator
		# should always catch up, however.
		wd = inotify_add_watch(self.inotify_fd, watch_obj.path, watch_obj.mask)

		# adding wd to the Watch object allows easy lookup in the list to remove it later
		watch_obj.wd = wd
		self.wd_list[wd] = watch_obj
		

	def add_tree_watch(self, watch_obj):
		# extract the file and dir mask from the mask passed, OR IN_CREATE with the dir mask
		# so that new dirs can be picked up and masks added to files and subdirs
		# walk the tree rooted at path and add watches

		file_mask = watch_obj.mask & all_file_masks

		#DEBUG
		print "file_mask: %x" % (file_mask)

		dir_mask = (watch_obj.mask & all_dir_masks) | IN_CREATE

		#DEBUG
		print "dir_mask: %x" % (dir_mask)


		for (root, dirnames, filenames) in os.walk(watch_obj.path):
			if file_mask > 0:
				for filename in filenames:
					file_path = os.path.join(root, filename)
					#DEBUG
					print "About to add watch with mask %x to file with path %s" % (file_mask, file_path)

					watch_obj = Watch(mask=file_mask, path=file_path)
					self.add_watch(watch_obj)

			for dirname in dirnames:
				dir_path = os.path.join(root, dirname)

				#DEBUG
				print "About to add watch with mask %x to dir with path %s" % (dir_mask, dir_path)

				watch_obj = Watch(mask=dir_mask, path=dir_path)
				self.add_watch(watch_obj)
					

	def rm_watch(self, watch_obj):
		inotify_rm_watch(self.inotify_fd, watch_obj.wd)
		self.wd_list[watch_obj.wd] = None

	def gen_events(self):
		#TODO should read buffer size be configurable?
		cdef char read_buf[4096]
		cdef inotify_event *event_ptr = <inotify_event *>&read_buf[0]
		cdef ssize_t read_len = 0
		cdef ssize_t processed_len = 0
		cdef unsigned int i = 0


		while True:
			# this read() will return immediately if there are any events to consume,
			# it won't block waiting to fill the buffer completely

			#TODO - support non-blocking read so that we yield straight away when there are no
			# events
			read_len = posix.unistd.read(self.inotify_fd, read_buf, 4096)
			if read_len < 0:

				#TODO not sure this is the right way to raise exceptions
				raise IOError("read() returned %d" % (read_len))

			i = 0
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
					wd=event_ptr[i].wd,
					watch_obj=self.wd_list[event_ptr[i].wd],
					mask=event_ptr[i].mask,
					cookie=event_ptr[i].cookie,
				)
				if event_ptr[i].len > 0:
					e.name = event_ptr[i].name[:event_ptr[i].len]
				yield e	
				
				processed_len += (sizeof(inotify_event) + event_ptr[i].len)
				i += 1

