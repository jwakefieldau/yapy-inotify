from unittest import TestCase
from multiprocessing import Process

import os
import uuid
import sys

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

class InotifyTestCase(TestCase):
	
	# In testing, events should take no more than this many seconds to be generated,
	# if they do, the join of the worker process should time out and the parent
	# should terminate it
	worker_timeout = 3

	def setUp(self):
		self.test_root_path = os.path.join('/tmp', "python-inotify_test_pid-%d_%s" % (os.getpid(), uuid.uuid4())) 	
		os.mkdir(self.test_root_path)
		self.event_dispatcher = EventDispatcher()

	def tearDown(self):
		# remove test file root dir and anything in it
		for (cur_dir_name, subdirs, files) in os.walk(self.test_root_path, topdown=False):
			for cur_subdir_name in subdirs:
				os.rmdir(os.path.join(cur_dir_name, cur_subdir_name))
			for cur_file_name in files:
				os.unlink(os.path.join(cur_dir_name, cur_file_name))
		os.rmdir(self.test_root_path)

	def _event_worker(self, test_watch):
		# test for generation of event that matches
		# test_watch, within the context of a worker process.
		# exit with success if one is generated, if one is
		# not, rely on the parent to kill us 
		g = self.event_dispatcher.gen_events() 
		for event in g:
			if event.watch_obj == test_watch:
				g.close()
		sys.exit(0)		

	def test_event_with_worker(self, test_watch, trigger_event_callable, trigger_args=(), trigger_kwargs={}):
		# use a worker process to add watch to event_dispatcher
		# and iterate over the event generator until an event
		# matching the watch is generated, then exit with success.
		# parent process joins the worker with a timeout, after
		# the join, if the worker exited with success, then the
		# event must have been generated within the timeout and we return True, if
		# the exitcode is None, the join must have timed out, so
		# the parent terminates the worker and returns False	

		worker_p = Process(group=None, target=self._event_worker, name=None, args=(test_watch,))
		worker_p.start()
		trigger_event_callable(*trigger_args, **trigger_kwargs)
		worker_p.join(timeout=self.worker_timeout)
		if worker_p.exitcode is None:
			worker_p.terminate()
		return (worker_p.exitcode == 0)	


class CreateTestCase(InotifyTestCase):

	def _create_for_test(self, path):
		with open(path, 'wt') as f:
			f.write("trololololololol\n")

	def test_create(self):
		test_path = os.path.join(self.test_root_path, 'create_test')
		test_watch = Watch(mask=IN_CREATE, path=test_path)
		assertTrue(self.test_event_with_worker(test_watch, self._create_for_test, trigger_args=(test_path,)))
