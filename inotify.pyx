cimport inotify
cimport posix.unistd
cimport libc.errno
cimport libc.string

import os
import stat

# masks

# from inotify(7)
"""
        IN_ACCESS         File was accessed (read) (*).
           IN_ATTRIB         Metadata changed, e.g., permissions, timestamps, extended attributes, link count (since Linux 2.6.25), UID, GID, etc. (*).
           IN_CLOSE_WRITE    File opened for writing was closed (*).
           IN_CLOSE_NOWRITE  File not opened for writing was closed (*).
           IN_CREATE         File/directory created in watched directory (*).
           IN_DELETE         File/directory deleted from watched directory (*).
           IN_DELETE_SELF    Watched file/directory was itself deleted.
           IN_MODIFY         File was modified (*).
           IN_MOVE_SELF      Watched file/directory was itself moved.
           IN_MOVED_FROM     File moved out of watched directory (*).
           IN_MOVED_TO       File moved into watched directory (*).
           IN_OPEN           File was opened (*).

       When monitoring a directory, the events marked with an asterisk (*) above can occur for files in the directory, in which case the name field in the returned
       inotify_event structure identifies the name of the file within the directory.

       The IN_ALL_EVENTS macro is defined as a bit mask of all of the above events.  This macro can be used as the mask argument when calling inotify_add_watch(2).

       Two additional convenience macros are IN_MOVE, which equates to IN_MOVED_FROM|IN_MOVED_TO, and IN_CLOSE, which equates to IN_CLOSE_WRITE|IN_CLOSE_NOWRITE.

       The following further bits can be specified in mask when calling inotify_add_watch(2):

           IN_DONT_FOLLOW (since Linux 2.6.15)
                             Don't dereference pathname if it is a symbolic link.
           IN_EXCL_UNLINK (since Linux 2.6.36)
                             By  default, when watching events on the children of a directory, events are generated for children even after they have been unlinked
                             from the directory.  This can result in large numbers of uninteresting events for some applications (e.g., if watching /tmp, in  which
                             many  applications create temporary files whose names are immediately unlinked).  Specifying IN_EXCL_UNLINK changes the default behav‐
                             ior, so that events are not generated for children after they have been unlinked from the watched directory.
           IN_MASK_ADD       Add (OR) events to watch mask for this pathname if it already exists (instead of replacing mask).
           IN_ONESHOT        Monitor pathname for one event, then remove from watch list.
           IN_ONLYDIR (since Linux 2.6.15)
                             Only watch pathname if it is a directory.


       The following bits may be set in the mask field returned by read(2):

           IN_IGNORED        Watch was removed explicitly (inotify_rm_watch(2)) or automatically (file was deleted, or file system was unmounted).
           IN_ISDIR          Subject of this event is a directory.
           IN_Q_OVERFLOW     Event queue overflowed (wd is -1 for this event).
           IN_UNMOUNT        File system containing watched object was unmounted.



"""


IN_CREATE = 0x00000100
IN_ACCESS = 0x00000001

file_mask_list = [
	IN_ACCESS,
]

dir_mask_list = [
	IN_CREATE,
]

ALL_FILE_MASKS = 0
for mask in file_mask_list:
	ALL_FILE_MASKS |= mask


ALL_DIR_MASKS = 0
for mask in dir_mask_list:
	ALL_DIR_MASKS |= mask

ALL_MASKS = ALL_FILE_MASKS | ALL_DIR_MASKS

mask_name_by_val = {
	IN_CREATE: 'IN_CREATE',
	IN_ACCESS: 'IN_ACCESS',
}



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
	full_event_path = None

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

	# render string representing watch, eg:
	# [+(for tree):path:mask0|mask1...|maskn
	def _render_str_rep(self):
		mask_name_str = '|'.join([v for (k, v) in mask_name_by_val.iteritems() if (self.mask & k) > 0])
		if self._is_tree:
			if self._is_tree_root:
				tree_str = '_+_'
			else:
				tree_str = '+'
		else:
			tree_str = ''
		ret_str = ':'.join([tree_str, self.path, mask_name_str])

		return ret_str

	def __str__(self):
		return str(self._render_str_rep())

		
	def __unicode__(self):
		return unicode(self._render_str_rep())


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

		if self._inotify_fd == -1:
			raise OSError("Unable to initialise inotify, %s" % libc.string.strerror(libc.errno.errno))
		
		self.blocking_read = blocking_read
		
	def add_watch(self, watch_obj):
		wd = inotify_add_watch(self._inotify_fd, watch_obj.path, watch_obj.mask)

		if wd == -1:
			raise OSError("Unable to add watch %s, error: %s" % (watch_obj, libc.string.strerror(libc.errno.errno)))

		# adding wd to the Watch object allows easy lookup in the list to remove it later
		watch_obj._wd = wd
		self._wd_list[wd] = watch_obj

		#DEBUG
		print "added watch with wd: %d, path: %s, mask: %x" % (wd, watch_obj.path, watch_obj.mask)

		# if a child tree watch, update the root's set of child wds
		if watch_obj._is_tree and not watch_obj._is_tree_root:
			watch_obj._tree_root_watch._child_watch_set.add(watch_obj)	
			

	def add_tree_watch(self, root_watch_obj):
		# extract the file and dir mask from the mask passed, OR IN_CREATE with the dir mask
		# so that new dirs can be picked up and masks added to files and subdirs
		# walk the tree rooted at path and add watches

		#TODO - instead of adding watches for all files, take advantage of behaviour where
		# the event will be generated by the kernel either for the directory itself 
		# (in which case, the name is omitted) or a file in the directory (basename is specified
		# as name)


		#NOTE - NEW BEHAVIOUR
		# * raise ValueError if root is not a dir
		# * OR input mask with IN_CREATE
		# * descend through dir tree and add watch with mask to any *directories*
		# * 

		root_watch_obj._is_tree = True
		root_watch_obj._is_tree_root = True
		root_watch_obj.mask |= IN_CREATE

		
		#file_mask = root_watch_obj.mask & ALL_FILE_MASKS

		#DEBUG
		#print "file_mask: %x" % (file_mask)

		#dir_mask = root_watch_obj.mask & ALL_DIR_MASKS

		#DEBUG
		#print "dir_mask: %x" % (dir_mask)
		
		self.add_watch(root_watch_obj)

		for (root, dirnames, filenames) in os.walk(root_watch_obj.path):
			#if file_mask > 0:
				#for filename in filenames:
					#file_path = os.path.join(root, filename)
					#DEBUG
					#print "About to add watch with mask %x to file with path %s" % (file_mask, file_path)

					#new_watch_obj = Watch(mask=file_mask, path=file_path, _is_tree=True, _tree_root_watch=root_watch_obj)
					#self.add_watch(new_watch_obj)

			for dirname in dirnames:
				dir_path = os.path.join(root, dirname)

				#DEBUG
				print "About to add watch with mask %x to dir with path %s" % (dir_mask, dir_path)

				new_watch_obj = Watch(mask=dir_mask, path=dir_path, _is_tree=True, _tree_root_watch=root_watch_obj)
				self.add_watch(new_watch_obj)

					

	def rm_watch(self, watch_obj):
		if (watch_obj._is_tree_root) and (len(watch_obj._child_watch_list) > 0): 
			raise ValueError("Cannot remove tree roots with live children individually")

		ret = inotify_rm_watch(self._inotify_fd, watch_obj._wd)
		if ret == -1:
			raise OSError("Unable to remove watch %s:%s" % (watch_obj, libc.string.strerror(libc.errno.errno)))

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
			if read_len == -1:
				raise IOError("error reading inotify data: %s" % (libc.string.strerror(libc.errno.errno)))

			i = 0
			while (processed_len < read_len): 


				matched_watch_obj = self._wd_list[event_ptr[i].wd]

				#NOTE - NEW BEHAVIOUR
				# * if event_name is None, we know the event occurred on the watched
				# directory itself, rather than a file within it
				# * only add new watches for created directories; we will get events
				# back for files in watched directories anyway

				# Cython docs say the fastest way to copy C strings to Python 
				# is by slicing the length so it doesn't need to call strlen()

				# NOTE - cython's sizeof() only evaluates the static size of the type
				# of its argument.  Since .name is a char[] in libc, it is considered
				# by sizeof() to occupy no space
				if event_ptr[i].len > 0:
					event_name = event_ptr[i].name[:event_ptr[i].len]
					full_event_path = os.path.join(matched_watch_obj.path, event_name)
				else:
					event_name = None
					full_event_path = matched_watch_obj.path

				#NOTE - there is an unavoidable race condition here - we can't
				# guarantee that we watch the newly created file/dir before
				# the events we want to watch occur on it.

				# It may be possible to "catch up" missed creations by comparing
				# ctimes and listdir(), but there is no guarantee that such files
				# have not already been removed!
				if matched_watch_obj._is_tree and (event_ptr[i].mask & IN_CREATE) > 0:
					create_stat_mode = os.stat(full_event_path).st_mode

					new_watch_obj = Watch(
						path=full_event_path,
						_is_tree=True,
						_tree_root_watch=matched_watch_obj if matched_watch_obj._is_tree_root else matched_watch_obj._tree_root_watch
					)

					#TODO - can we actually just use the root watch's mask on all files and dirs?
					# are there masks that have significantly different behaviour for files and dirs?
					# are there masks that inotify won't let us apply to files and dirs?

		
					#TODO take advantage of behaviour where events are generated for either
					# files in dir (basename specified as name) or dir itself (no name)
					if stat.S_ISDIR(create_stat_mode):

						#DEBUG
						print "stat indicates %s is a dir" % new_path

						# new dir, apply the dir mask bits of the mask, OR IN_CREATE
						dir_mask=((matched_watch_obj.mask & ALL_DIR_MASKS)  | IN_CREATE),
						new_watch_obj.mask = dir_mask
						
					#DEBUG
					print "new watch obj - adding due to matched tree watch:"
					print "================================================="
					print "path=%s,mask=%x"
						
					self.add_watch(new_watch_obj)

				e = Event(
					_wd=event_ptr[i].wd,
					watch_obj=matched_watch_obj,
					mask=event_ptr[i].mask,
					cookie=event_ptr[i].cookie,
				)
				if event_ptr[i].len > 0:
					e.name = event_ptr[i].name[:event_ptr[i].len]
					e.full_event_path = os.path.join(matched_watch_obj.path, e.name)

				else:
					e.full_event_path = matched_watch_obj.path
				
				processed_len += (sizeof(inotify_event) + event_ptr[i].len)
				i += 1
				
				yield e	

