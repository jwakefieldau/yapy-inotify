#!/usr/bin/python

from multiprocessing import Process
from multiprocessing import Event as PEvent

import os
import uuid
import sys
import unittest

from inotify import *

#BUG
"""
james@james-laptop[Linux 3.2.0-43-generic on 2 x i686]-[06:46:56]
~/Code/python_inotify
(3) $ ./tests.py 
Added watch :/tmp/python-inotify_test_pid-2294_7fa36704-0a44-48ad-8318-ca3b35d54651:IN_ACCESS
Got event <inotify.Event object at 0xb76a230c>
.Process Process-1:
Traceback (most recent call last):
  File "/usr/lib/python2.7/multiprocessing/process.py", line 258, in _bootstrap
Added watch :/tmp/python-inotify_test_pid-2294_c5213b7a-dddd-4cc7-93da-decc8d13d5da:IN_CLOSE_WRITE|IN_CLOSE_NOWRITE|IN_CLOSE
Got event <inotify.Event object at 0xb74266cc>
    self.run()
  File "/usr/lib/python2.7/multiprocessing/process.py", line 114, in run
    self._target(*self._args, **self._kwargs)
  File "./tests.py", line 89, in _event_worker
    self.event_dispatcher.close()
  File "inotify.pyx", line 422, in inotify.EventDispatcher.close (inotify.c:5307)
    self.rm_watch(cur_watch)
  File "inotify.pyx", line 275, in inotify.EventDispatcher.rm_watch (inotify.c:3975)
    raise OSError("Unable to remove watch %s:%s" % (watch_obj, libc.string.strerror(libc.errno.errno)))
OSError: Unable to remove watch :/tmp/python-inotify_test_pid-2294_7fa36704-0a44-48ad-8318-ca3b35d54651:IN_ACCESS:Invalid argument
.Added watch :/tmp/python-inotify_test_pid-2294_9eddf1c7-027c-40e0-8f33-f4a1adda7c61:IN_CREATE
Got event <inotify.Event object at 0xb74266cc>
.Process Process-3:
Traceback (most recent call last):
  File "/usr/lib/python2.7/multiprocessing/process.py", line 258, in _bootstrap
    self.run()
  File "/usr/lib/python2.7/multiprocessing/process.py", line 114, in run
    self._target(*self._args, **self._kwargs)
  File "./tests.py", line 89, in _event_worker
    self.event_dispatcher.close()
  File "inotify.pyx", line 422, in inotify.EventDispatcher.close (inotify.c:5307)
    self.rm_watch(cur_watch)
  File "inotify.pyx", line 275, in inotify.EventDispatcher.rm_watch (inotify.c:3975)
    raise OSError("Unable to remove watch %s:%s" % (watch_obj, libc.string.strerror(libc.errno.errno)))
OSError: Unable to remove watch :/tmp/python-inotify_test_pid-2294_9eddf1c7-027c-40e0-8f33-f4a1adda7c61:IN_CREATE:Invalid argument
Added watch :/tmp/python-inotify_test_pid-2294_c00f6795-1b5b-4312-9684-26ab3e301f8b:IN_DELETE
Got event <inotify.Event object at 0xb74266cc>
.Process Process-4:
Traceback (most recent call last):
  File "/usr/lib/python2.7/multiprocessing/process.py", line 258, in _bootstrap
    self.run()
  File "/usr/lib/python2.7/multiprocessing/process.py", line 114, in run
    self._target(*self._args, **self._kwargs)
  File "./tests.py", line 89, in _event_worker
    self.event_dispatcher.close()
  File "inotify.pyx", line 422, in inotify.EventDispatcher.close (inotify.c:5307)
    self.rm_watch(cur_watch)
  File "inotify.pyx", line 275, in inotify.EventDispatcher.rm_watch (inotify.c:3975)
    raise OSError("Unable to remove watch %s:%s" % (watch_obj, libc.string.strerror(libc.errno.errno)))
OSError: Unable to remove watch :/tmp/python-inotify_test_pid-2294_c00f6795-1b5b-4312-9684-26ab3e301f8b:IN_DELETE:Invalid argument
Added watch :/tmp/python-inotify_test_pid-2294_5c1d3639-9b20-4806-a501-0e5fb30104bd:IN_MODIFY
Got event <inotify.Event object at 0xb76a230c>
.
"""

# Test cases:

# creation of file in directory
# reading of file
# modification of file
# closing of file
# deletion of file

# recursive dir watch
# creation of files in multiple directories in tree
# 

# opening of existing file
#

# ** Test exceptional behaviour - eg: flood of events, 
# attempting to remove watch for file already removed, etc - 
# look at exceptional cases in inotify code ** 

# *** WHICH TESTS TO RUN FOR RECURSIVE DIR WATCH VS SINGLE FILE/DIR ? ***
# if some tests have been done for single case, do they need to be re-done for recursive?

class InotifyTestCase(unittest.TestCase):
	
	# In testing, events should take no more than this many seconds to be generated,
	# if they do, the join of the worker process should time out and the parent
	# should terminate it
	worker_timeout = 3

	def setUp(self):
		self.test_root_path = os.path.join('/tmp', "python-inotify_test_pid-%d_%s" % (os.getpid(), uuid.uuid4())) 	
		os.mkdir(self.test_root_path)
		self.event_dispatcher = EventDispatcher()

	def tearDown(self):
		self.event_dispatcher.close()
		# remove test file root dir and anything in it
		for (cur_dir_name, subdirs, files) in os.walk(self.test_root_path, topdown=False):
			for cur_subdir_name in subdirs:
				os.rmdir(os.path.join(cur_dir_name, cur_subdir_name))
			for cur_file_name in files:
				os.unlink(os.path.join(cur_dir_name, cur_file_name))
		os.rmdir(self.test_root_path)

	def _write_for_test(self, path, create=True):
		if create:
			with open(path, 'wt') as f:
				f.write("trololololololol\n")
		else:
			with open(path, 'wt') as f:
				f.write("nangnangnangnangnangnang\n")
			


	def _read_for_test(self, path):
		with open(path, 'rt') as f:
			s = f.read()

	def _event_worker(self, test_watch, added_watch_event, got_event):
		# test for generation of event that matches
		# test_watch, within the context of a worker process.
		# exit with success if one is generated, if one is
		# not, rely on the parent to kill us 

		self.event_dispatcher.add_watch(test_watch)
		added_watch_event.set()

		#DEBUG
		print "Added watch %s" % test_watch

		g = self.event_dispatcher.gen_events() 
		for event in g:

			#DEBUG
			print "Got event %s" % event

			if event.watch_obj == test_watch:
				got_event.set()
				g.close()

		self.event_dispatcher.close()
		sys.exit(0)		

	#TODO - this needs to support testing of recursive/tree watches 
	# one way could be to pass a number of events that should be yielded,
	# and pass that on to the worker, which counts how many events it 
	# iterates over which is either related directly to the test_watch
	# or whose watch is a child of the test_watch.

	def watchdog_event_worker(self, test_watch, trigger_event_callable, trigger_args=(), trigger_kwargs={}):
		# use a worker process to add watch to event_dispatcher
		# and iterate over the event generator until an event
		# matching the watch is generated, then exit with success.
		# parent process joins the worker with a timeout, after
		# the join, if the worker exited with success, then the
		# event must have been generated within the timeout and we return True, if
		# the exitcode is None, the join must have timed out, so
		# the parent terminates the worker and returns False	

		ret = False
		added_watch_event = PEvent()
		got_event = PEvent()
		worker_p = Process(group=None, target=self._event_worker, name=None, args=(test_watch, added_watch_event, got_event,))
		worker_p.start()

		#don't call this until after worker process has added watch 
		if added_watch_event.wait(self.worker_timeout):
			trigger_event_callable(*trigger_args, **trigger_kwargs)

			if got_event.wait(self.worker_timeout):
				ret = True

			else:
				worker_p.terminate()

		else:
			worker_p.terminate()			

		return ret

#TODO - add test_*_tree() methods to each test case class
# move test_*() bodies out to other methods to wrap common
# tree/non-tree code

class CreateTestCase(InotifyTestCase):

	def test_create(self):
		test_file_path = os.path.join(self.test_root_path, 'create_test')
		test_watch = Watch(mask=IN_CREATE, path=self.test_root_path)
		worker_test_ret = self.watchdog_event_worker(
				test_watch,
				self._write_for_test,
				trigger_args=(test_file_path,)
		)
		self.assertTrue(worker_test_ret)

class DeleteTestCase(InotifyTestCase):

	def test_delete(self):
		test_file_path = os.path.join(self.test_root_path, 'delete_test')
		self._write_for_test(test_file_path)
		test_watch = Watch(mask=IN_DELETE, path=self.test_root_path)
		worker_test_ret = self.watchdog_event_worker(
			test_watch,
			os.unlink,
			trigger_args=(test_file_path,)
		)
		self.assertTrue(worker_test_ret)

class AccessTestCase(InotifyTestCase):

	def test_access(self):
		test_file_path = os.path.join(self.test_root_path, 'access_test')
		self._write_for_test(test_file_path)
		test_watch = Watch(mask=IN_ACCESS, path=self.test_root_path)
		worker_test_ret = self.watchdog_event_worker(
			test_watch,
			self._read_for_test,
			trigger_args=(test_file_path,)
		)
		self.assertTrue(worker_test_ret)

class ModifyTestCase(InotifyTestCase):

	def test_modify(self):
		test_file_path = os.path.join(self.test_root_path, 'modify_test')
		self._write_for_test(test_file_path)
		test_watch = Watch(mask=IN_MODIFY, path=self.test_root_path)
		worker_test_ret = self.watchdog_event_worker(
			test_watch,
			self._write_for_test,
			trigger_args=(test_file_path, False,)
		)
		self.assertTrue(worker_test_ret)

class CloseTestCase(InotifyTestCase):
	
	def test_close(self):
		test_file_path = os.path.join(self.test_root_path, 'close_test')
		test_watch = Watch(mask=IN_CLOSE, path=self.test_root_path)
		worker_test_ret = self.watchdog_event_worker(
			test_watch,
			self._write_for_test,
			trigger_args=(test_file_path,)
		)
		self.assertTrue(worker_test_ret)





if __name__ == '__main__':
	unittest.main()
