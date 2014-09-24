cimport inotify
cimport posix.unistd

import os
import stat

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
	_wd = None
	mask = None
	cookie = None
	name = None
	watch_obj = None

	def __init__(self, **kwargs):
		set_attrs_from_kwargs(self, **kwargs)

class Watch(object):
	mask = None
	path = None
	_wd = None
	_is_tree = False
	_is_tree_root = False
	_tree_root_watch = None

	_child_watch_set = set()

	def __init__(self, **kwargs):
		set_attrs_from_kwargs(self, **kwargs)


class EventDispatcher(object):
	_wd_list = []
	_inotify_fd = None
	blocking_read = True

	def __init__(self, blocking_read=True):

		# determine how big _wd_list needs to be
		with open('/proc/sys/fs/inotify/max_user_watches') as f_obj:
			max_user_watches = int(f_obj.readline().strip())

		self._wd_list = [None] * max_user_watches
		self._inotify_fd = inotify_init()
		self.blocking_read = blocking_read
		
	def add_watch(self, watch_obj):
		wd = inotify_add_watch(self._inotify_fd, watch_obj.path, watch_obj.mask)

		# adding wd to the Watch object allows easy lookup in the list to remove it later
		watch_obj._wd = wd
		self._wd_list[wd] = watch_obj

		#DEBUG
		print "added watch with wd: %d, path: %s, mask: %x" % (wd, watch_obj.path, watch_obj.mask)

		# if a child tree watch, update the root's set of child wds
		if watch_obj._is_tree and not watch_obj._is_tree_root:
			watch_obj._tree_root_watch._child_watch_set.add(watch_obj)	
			

	def add_tree_watch(self, input_watch_obj):
		# extract the file and dir mask from the mask passed, OR IN_CREATE with the dir mask
		# so that new dirs can be picked up and masks added to files and subdirs
		# walk the tree rooted at path and add watches

		file_mask = input_watch_obj.mask & all_file_masks

		#DEBUG
		print "file_mask: %x" % (file_mask)

		dir_mask = (input_watch_obj.mask & all_dir_masks) | IN_CREATE

		#DEBUG
		print "dir_mask: %x" % (dir_mask)
		
		# create a new Watch derived from the input watch to be the root - it needs to have the dir
		# mask
		root_watch_obj = Watch(
			_is_tree = True,
			_is_tree_root = True,
			path=input_watch_obj.path,
			mask=dir_mask
		)

		self.add_watch(root_watch_obj)

		for (root, dirnames, filenames) in os.walk(root_watch_obj.path):
			if file_mask > 0:
				for filename in filenames:
					file_path = os.path.join(root, filename)
					#DEBUG
					print "About to add watch with mask %x to file with path %s" % (file_mask, file_path)

					new_watch_obj = Watch(mask=file_mask, path=file_path, _is_tree=True, _tree_root_watch=root_watch_obj)
					self.add_watch(new_watch_obj)

			for dirname in dirnames:
				dir_path = os.path.join(root, dirname)

				#DEBUG
				print "About to add watch with mask %x to dir with path %s" % (dir_mask, dir_path)

				new_watch_obj = Watch(mask=dir_mask, path=dir_path, _is_tree=True, _tree_root_watch=root_watch_obj)
				self.add_watch(new_watch_obj)

					

	def rm_watch(self, watch_obj):
		if (watch_obj._is_tree_root) and (len(watch_obj._child_watch_list) > 0): 
			raise ValueError("Cannot remove tree roots with live children individually")

		inotify_rm_watch(self._inotify_fd, watch_obj._wd)

		if watch_obj._is_tree and not watch_obj._is_tree_root:
			watch_obj._tree_root_watch._child_watch_set.discard(watch_obj)
		
		self._wd_list[watch_obj._wd] = None

	def rm_tree_watch(self, root_watch_obj):
		for child_watch in root_watch_obj._child_watch_set:
			self.rm_watch(child_watch)
			root_watch_obj._child_watch_set.discard(child_watch)

		self.rm_watch(root_watch_obj)	

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
			read_len = posix.unistd.read(self._inotify_fd, read_buf, 4096)
			if read_len < 0:

				#TODO not sure this is the right way to raise exceptions
				raise IOError("read() returned %d" % (read_len))

			i = 0
			while (processed_len < read_len): 

				# NOTE - cython's sizeof() only evaluates the static size of the type
				# of its argument.  Since .name is a char[] in libc, it is considered
				# by sizeof() to occupy no space


				#TODO - associate this event with any tree watches via wd?
				# if it's an IN_CREATE for a new dir under tree, add the tree watch's dir mask
				# if it's an IN_CREATE for a new file under tree and the tree watch has a file mask,
				# add that to the new file

				#DEBUG
				print "Read event with wd: %d" % event_ptr[i].wd

				matched_watch_obj = self._wd_list[event_ptr[i].wd]
				
				#NOTE - there is an unavoidable race condition here - we can't
				# guarantee that we watch the newly created file/dir before
				# the events we want to watch occur on it.

				# It may be possible to "catch up" missed creations by comparing
				# ctimes and listdir(), but there is no guarantee that such files
				# have not already been removed!
				if matched_watch_obj._is_tree and (event_ptr[i].mask & IN_CREATE) > 0:
					new_path = os.path.join(matched_watch_obj.path, event_ptr[i].name) 
					create_stat_mode = os.stat(new_path).st_mode

					new_watch_obj = Watch(
						path=new_path,
						_is_tree=True,
						_tree_root_watch=matched_watch_obj._tree_root_watch
					)

					# is this S_ISDIR necessary?
					if stat.S_ISDIR(create_stat_mode):
						# new dir, apply the dir mask bits of the mask, OR IN_CREATE
						dir_mask=((matched_watch_obj.mask & all_dir_masks)  | IN_CREATE),
						new_watch_obj.mask = dir_mask
						
					else:
						# new regular file, apply the file mask bits of the mask
						file_mask = matched_watch_obj.mask & all_file_masks
						new_watch_obj.mask = file_mask

					#DEBUG
					print "new watch obj - adding due to matched tree watch:"
					print "================================================="
					print "path=%s,mask=%x"
						
					self.add_watch(new_watch_obj)

				# Cython docs say the fastest way to copy C strings to Python 
				# is by slicing the length so it doesn't need to call strlen()
				e = Event(
					_wd=event_ptr[i].wd,
					watch_obj=matched_watch_obj,
					mask=event_ptr[i].mask,
					cookie=event_ptr[i].cookie,
				)
				if event_ptr[i].len > 0:
					e.name = event_ptr[i].name[:event_ptr[i].len]
				
				processed_len += (sizeof(inotify_event) + event_ptr[i].len)
				i += 1
				
				yield e	

