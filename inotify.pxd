cdef extern from "sys/inotify.h":

	cdef struct inotify_event:
		int wd
		unsigned int mask
		unsigned int cookie
		unsigned int len
		#NOTE - this is char [] in in the C declaration, but 
		#Cython doesn't distinguish, nor support that syntax.
		# **This means that sizeof() considers 'name' to be of size 0**
		char *name


	cdef int inotify_init()
	cdef int inotify_add_watch(int fd, char *path, unsigned int mask)
	cdef int inotify_rm_watch(int fd, int wd)	

