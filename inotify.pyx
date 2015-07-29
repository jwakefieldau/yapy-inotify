cimport inotify
cimport posix.unistd
cimport libc.errno
cimport libc.string

import os
import stat

#TODO - control access to '_' private members properly with getters and setters?

IN_ACCESS 	=	0x00000001      #File was accessed 
IN_MODIFY	=	0x00000002      # File was modified 
IN_ATTRIB       =       0x00000004      # Metadata changed 
IN_CLOSE_WRITE  =       0x00000008      # Writtable file was closed 
IN_CLOSE_NOWRITE  =     0x00000010      # Unwrittable file closed 
IN_OPEN         =       0x00000020      # File was opened 
IN_MOVED_FROM   =       0x00000040      # File was moved from X 
IN_MOVED_TO     =       0x00000080      # File was moved to Y 
IN_CREATE       =       0x00000100      # Subfile was created 
IN_DELETE       =       0x00000200      # Subfile was deleted 
IN_DELETE_SELF  =       0x00000400      # Self was deleted 
IN_MOVE_SELF    =       0x00000800      # Self was moved 

# the following are legal events.  they are sent as needed to any watch 
IN_UNMOUNT      =       0x00002000      # Backing fs was unmounted 
IN_Q_OVERFLOW   =       0x00004000      # Event queued overflowed 
IN_IGNORED      =       0x00008000      # File was ignored 

# helper events 
IN_CLOSE        =        (IN_CLOSE_WRITE | IN_CLOSE_NOWRITE) # close 
IN_MOVE         =        (IN_MOVED_FROM | IN_MOVED_TO) # moves 

# special flags 
IN_ONLYDIR      =       0x01000000      # only watch the path if it is a directory 
IN_DONT_FOLLOW  =       0x02000000      # don't follow a sym link 
IN_EXCL_UNLINK  =        0x04000000      # exclude events on unlinked objects 
IN_MASK_ADD     =       0x20000000      # add to the mask of an already existing watch 
IN_ISDIR        =        0x40000000      # event occurred against dir 
IN_ONESHOT      =       0x80000000      # only send event once 


mask_name_by_val = {

	IN_ACCESS: 'IN_ACCESS',
	IN_MODIFY: 'IN_MODIFY',
	IN_ATTRIB: 'IN_ATTRIB',
	IN_CLOSE_WRITE: 'IN_CLOSE_WRITE',
	IN_CLOSE_NOWRITE: 'IN_CLOSE_NOWRITE', 
	IN_OPEN : 'IN_OPEN',       
	IN_MOVED_FROM: 'IN_MOVED_FROM', 
	IN_MOVED_TO: 'IN_MOED_TO',
	IN_CREATE: 'IN_CREATE',    
	IN_DELETE: 'IN_DELETE',     
	IN_DELETE_SELF: 'IN_DELETE_SELF', 
	IN_MOVE_SELF: 'IN_MOVE_SELF',  
	IN_UNMOUNT: 'IN_UNMOUNT', 
	IN_Q_OVERFLOW: 'IN_Q_OVERFLOW', 
	IN_IGNORED: 'IN_IGNORED',   
	IN_CLOSE: 'IN_CLOSE',   
	IN_MOVE: 'IN_MOVE',   
	IN_ONLYDIR: 'IN_ONLYDIR',    
	IN_DONT_FOLLOW: 'IN_DONT_FOLLOW', 
	IN_EXCL_UNLINK: 'IN_EXCL_UNLINK', 
	IN_MASK_ADD: 'IN_MASK_ADD',    
	IN_ISDIR: 'IN_ISDIR',       
	IN_ONESHOT: 'IN_ONESHOT'     

}



def set_attrs_from_kwargs(obj, **kwargs):
	for (k, v) in kwargs.items():
		if hasattr(obj, k):
			setattr(obj, k, v)

def render_mask_str(input_mask):
	return '|'.join([v for (k, v) in mask_name_by_val.iteritems() if (input_mask & k) > 0])


class Event(object):
	"""
	Represents an inotify event that has occurred on an active Watch
	"""

	_wd = None
	mask = None
	cookie = None
	name = None
	watch_obj = None
	full_event_path = None

	def __init__(self, **kwargs):
		set_attrs_from_kwargs(self, **kwargs)

	def _render_str_rep(self):
		return ':'.join([self.full_event_path, render_mask_str(self.mask)])

	def __str__(self):
		return str(self._render_str_rep())

	def __unicode__(self):
		return unicode(self._render_str_rep())


class Watch(object):
	"""
	Represents an inotify watch.  

	If _is_tree_root is True, then this watch will by applied via inotify to 
	any pre-existing and newly created objects under path.  The mask will be ORed
	with IN_CREATE to facilitate this.  These new watches have _is_tree = True and
	_is_tree_root set to the watch object that set the initial watch. 
	"""

	mask = None
	_effective_mask = None
	child_mask = None
	_effective_child_mask = None
	path = None
	_wd = None
	_is_tree = False
	_is_tree_root = False
	_tree_root_watch = None
	_child_watch_set = set()

	def __init__(self, **kwargs):
		set_attrs_from_kwargs(self, **kwargs)
		if self._effective_mask is None:
			self._effective_mask = self.mask

	# render string representing watch, eg:
	# [+(for tree):path:mask0|mask1...|maskn
	def _render_str_rep(self):
		mask_name_str = render_mask_str(self.mask)
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
	"""
	EventDispatcher provides the interface to add or remove Watches from the system
	(via inotify), and generate Events from them.

	If ioerror_on_unmount or ioerror_on_q_overflow are True, then IOError will
	be raised if those events (IN_UNMOUNT or IN_Q_OVERFLOW) should be read from 
	inotify, rather than simply yielding Event objects for the consumer. 

	"""
	
	_wd_list = []
	_inotify_fd = None
	_closed = False
	ioerror_on_unmount = True 
	ioerror_on_q_overflow = True

	def __init__(self, **kwargs):

		set_attrs_from_kwargs(self, **kwargs)

		# determine how big _wd_list needs to be
		with open('/proc/sys/fs/inotify/max_user_watches') as f_obj:
			max_user_watches = int(f_obj.readline().strip())

		self._wd_list = [None] * max_user_watches
		self._inotify_fd = inotify_init()

		if self._inotify_fd == -1:
			raise OSError("Unable to initialise inotify, %s" % libc.string.strerror(libc.errno.errno))
		
	def add_watch(self, watch_obj):
		"""
		Add the Watch watch_obj and apply via inotify
		"""
	
		wd = inotify_add_watch(self._inotify_fd, watch_obj.path, watch_obj._effective_mask)

		if wd == -1:
			raise OSError("Unable to add watch %s, error: %s" % (watch_obj, libc.string.strerror(libc.errno.errno)))

		# adding wd to the Watch object allows easy lookup in the list to remove it later
		watch_obj._wd = wd
		self._wd_list[wd] = watch_obj

		# if a child tree watch, update the root's set of child wds
		if watch_obj._is_tree and not watch_obj._is_tree_root:
			watch_obj._tree_root_watch._child_watch_set.add(watch_obj)	
			
	def _gen_subdir_child_watches(self, parent_watch_obj, gen_events=False, gen_event_mask=None):
		"""
		Add the Watch objects for any already-existing subdirectories of
		parent_watch_obj.path.  If gen_events is true, yield an Event
		object for any such subdir.  This is for cases where we call this
		method to catch up any missed IN_CREATE | IN_ISDIR events.
		"""

		for (root, dirnames, filenames) in os.walk(parent_watch_obj.path):
			for dirname in dirnames:
				dir_path = os.path.join(root, dirname)
				new_watch_obj = Watch(
					mask=parent_watch_obj.child_mask if parent_watch_obj._is_tree_root else parent_watch_obj.mask,
					_effective_mask=parent_watch_obj._effective_child_mask if parent_watch_obj._is_tree_root else parent_watch_obj._effective_mask,
					path=dir_path,
					_is_tree=True,
					_tree_root_watch=parent_watch_obj if parent_watch_obj._is_tree_root else parent_watch_obj._tree_root_watch,
				)
				self.add_watch(new_watch_obj)

				if gen_events:
					yield (new_watch_obj,
						Event(
							_wd=new_watch_obj._wd,
							watch_obj=new_watch_obj,
							full_event_path=dir_path,
							mask=gen_event_mask,
							cookie=None
						)
					)
				else:
					yield (new_watch_obj, None)

			


	def add_tree_watch(self, root_watch_obj):
		"""
		Add the Watch root_watch_obj, being specified to watch a directory, 
		and apply via inotify; any sub-directories existing in the directory (recursively)
		will have Watches added for them and any new directories created subsequently
		during Event generation will have Watches added for them.  

		Only directories are watched in this scenario as it has the same effect 
		as watching all files in the directory.  If root_watch_obj does not 
		specify a directory, ValueError will be raised.

		"""

		# * raise ValueError if root is not a dir
		# * OR input mask with IN_CREATE
		# * descend through dir tree and add watch with mask to any *directories*
		# * 

		#NOTE - does adding a file watch to a dir have the same essential
		# behaviour as adding the watch to all files in the dir?
		# YES - for all masks except IN_DELETE_SELF, which should not be a problem

		#NOTE - does this result in potentially two events on deletion?

		root_watch_obj._is_tree = True
		root_watch_obj._is_tree_root = True
		root_watch_obj._effective_mask |= IN_CREATE

		# watching deletion on subdirs means no need to watch self-deletion on anything except
		# the root
		if root_watch_obj.mask & IN_DELETE_SELF:
			root_watch_obj._effective_mask |= IN_DELETE
			root_watch_obj._effective_child_mask = root_watch_obj._effective_mask ^ IN_DELETE_SELF
		else:
			root_watch_obj._effective_child_mask = root_watch_obj._effective_mask

		root_watch_obj.child_mask = root_watch_obj.mask
		
		if not stat.S_ISDIR(os.stat(root_watch_obj.path).st_mode):
			raise ValueError("Can't root a tree watch at %s as it is not a directory" % (root_watch_obj.path))
		
		self.add_watch(root_watch_obj)

		for (cur_subdir_watch, _cur_event) in self._gen_subdir_child_watches(root_watch_obj):
			self.add_watch(cur_subdir_watch)
		
		

	def rm_watch(self, watch_obj, discard=True):
		"""
		Remove a Watch, and optionally, discard it from its tree root watch's set 
		of child watches (default).  The case for not discarding is when removing
		a tree watch, where we remove child watches iteratively and must avoid
		modifying the set of child watches until afterward (as in .rm_tree_watch()).

		If watch_obj is a tree root, and its set of child watches is not empty,
		ValueError will be raised; use .rm_tree_watch() to remove these.

		If the call via inotify to remove the watch fails, OSError will be raised.
		"""

		if (watch_obj._is_tree_root) and watch_obj._child_watch_set and (len(watch_obj._child_watch_set) > 0): 
			raise ValueError("Cannot remove tree roots with live children individually")

		#NOTE - is there a better way to deal with already-removed files than to
		# stat them here and avoid calling inotify if they're removed?
		# Should we catch the exception and then stat?  Otherwise, potential
		# race between stat and inotify
		ret = inotify_rm_watch(self._inotify_fd, watch_obj._wd)
		if ret == -1:
			# invalid argument - most likely file deleted, keep on trucking
			if libc.errno.errno == libc.errno.EINVAL:
				pass
			else:	
				raise OSError("Unable to remove watch %s:%s" % (watch_obj, libc.string.strerror(libc.errno.errno)))

		# discarding from _child_watch_set is optional, so that when
		# we remove tree watches, we don't modify the set during iteration
		# the whole set will disappear anyway, so this is no problem.
		if discard and watch_obj._is_tree and not watch_obj._is_tree_root:
			watch_obj._tree_root_watch._child_watch_set.discard(watch_obj)
		
		self._wd_list[watch_obj._wd] = None

	def rm_tree_watch(self, root_watch_obj):
		"""
		Remove a tree root watch and all its children.  .rm_watch() is called with
		discard=False for each child so that the child watch set is not modified
		during iteration.
		"""

		for child_watch in root_watch_obj._child_watch_set:
			self.rm_watch(child_watch, discard=False)

		root_watch_obj._child_watch_set = None
		self.rm_watch(root_watch_obj)	

	def gen_events(self):
		"""
		Read from inotify and generate (yield) Events until .close() has been called.
		If the matching Watch is a tree watch and the Event is for directory creation,
		add a new tree Watch with the same root.

		.... ioerror on unmount, q overflow ....
		"""

		
		cdef char read_buf[4096]
		cdef inotify_event *event_ptr
		cdef ssize_t read_len = 0
		cdef ssize_t processed_len = 0


		while not self._closed:

			# zero read_buf to avoid re-reading what will be nonsense on second read
			libc.string.memset(read_buf, 0, 4096)

			# this read() will return immediately if there are any events to consume,
			# it won't block waiting to fill the buffer completely

			#TODO - support non-blocking read so that we yield straight away when there are no
			# events
			read_len = posix.unistd.read(self._inotify_fd, read_buf, 4096)

			if read_len == -1:
				raise IOError("error reading inotify data: %s" % (libc.string.strerror(libc.errno.errno)))

			processed_len = 0
			event_ptr = <inotify_event *>&read_buf[0]

			# check on each iteration that we haven't been closed, since we (potentially) yield on each iteration
			while (processed_len < read_len) and not self._closed: 

				#TODO -  How can self._wd_list be None here if it is
				# set None in self.close() and we check self._closed?

				# This is highly intermittent

				#DEBUG
				try:
					matched_watch_obj = self._wd_list[event_ptr.wd]

				except TypeError:
					print "self._closed: %s" % self._closed
					print "type(self._wd_list) %s" % (type(self._wd_list))
					raise

				# * if event_name is None, we know the event occurred on the watched
				# directory itself, rather than a file within it
				# * only add new watches for created directories; we will get events
				# back for files in watched directories anyway

				# Cython docs say the fastest way to copy C strings to Python 
				# is by slicing the length so it doesn't need to call strlen()

				# NOTE - cython's sizeof() only evaluates the static size of the type
				# of its argument.  Since .name is a char[] in libc, it is considered
				# by sizeof() to occupy no space

				# now that we have an Event object, use that rather than event_ptr where
				# possible, to avoid bugs arising from confusion about where it points to
				e = Event(
					_wd=event_ptr.wd,
					watch_obj=matched_watch_obj,
					mask=event_ptr.mask,
					cookie=event_ptr.cookie,
				)

				if event_ptr.len > 0:

					# event_ptr.name is padded with 0s that will confuse later string comparisons
					# in Python if not stripped
					event_name = event_ptr.name[:event_ptr.len]
					nul_chr_i = event_name.find(chr(0))
					event_name = event_name[:nul_chr_i]
					e.name = event_name
					full_event_path = os.path.join(matched_watch_obj.path, event_name)
					e.full_event_path = full_event_path
				else:
					event_name = None
					full_event_path = matched_watch_obj.path
					e.full_event_path = full_event_path

				#NOTE - there is an unavoidable race condition here - we can't
				# guarantee that we watch the newly created dir before
				# the events we want to watch occur on it.
				if matched_watch_obj._is_tree and (e.mask & (IN_CREATE | IN_ISDIR) >= (IN_CREATE | IN_ISDIR)): 
					new_watch_obj = Watch(
						path=full_event_path,
						mask=matched_watch_obj.child_mask if matched_watch_obj._is_tree_root else matched_watch_obj.mask,
						_effective_mask=matched_watch_obj._effective_child_mask if matched_watch_obj._is_tree_root else matched_watch_obj._effective_mask,
						_is_tree=True,
						_tree_root_watch=matched_watch_obj if matched_watch_obj._is_tree_root else matched_watch_obj._tree_root_watch,
					)
					self.add_watch(new_watch_obj)

					#NOTE - some user actions (eg: mkdir -p) are known to win the race against IN_CREATE sometimes,
					# so walk through the new dir and add watches to any subdirs that already exist
					# at this point, yielding events for them too
					for (catchup_dir_w, catchup_dir_e) in self._gen_subdir_child_watches(new_watch_obj, gen_events=True, gen_event_mask=e.mask):

						# we could be closed inside this loop since we yield in it
						if self._closed:
							break

						self.add_watch(catchup_dir_w)
						yield catchup_dir_e
						
				
				if (e.mask & IN_UNMOUNT) > 0 and self.ioerror_on_unmount:
					raise IOError("Backing filesystem for %s unmounted" % (full_event_path))

				elif (e.mask & IN_Q_OVERFLOW) > 0 and self.ioerror_on_q_overflow:
					raise IOError('Inotify event queue overflowed')
				
				else:
					# yield the event only if its mask matches the user mask; eg: don't yield
					# IN_CREATEs that are only watched to make a watch recursive, or
					# IN_IGNORE, etc		
					if (e.mask & matched_watch_obj.mask) > 0:
						yield e

				# move event_ptr to the start of the next event - this should be the
				# last thing we do in each iteration
				processed_len += (sizeof(inotify_event) + event_ptr.len)
				event_ptr = <inotify_event *>&read_buf[processed_len]


	def close(self):
		self._closed = True

		for cur_watch in self._wd_list:
			if cur_watch is not None:
				if cur_watch._is_tree_root:
					self.rm_tree_watch(cur_watch)
		
				# if the current watch won't be removed as part of 
				# removing a tree watch, it can be safely removed
				# now
				if not cur_watch._is_tree:
					self.rm_watch(cur_watch)

		self._wd_list = None
		posix.unistd.close(self._inotify_fd)	

	def is_closed(self):
		return self._closed
			
		
