#!/usr/bin/python

from multiprocessing import Process
from multiprocessing import Event as PEvent

import os
import uuid
import sys
import unittest

from inotify import *

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
