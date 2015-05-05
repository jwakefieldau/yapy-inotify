from unittest import TestCase

import os
import uuid

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


class CreateTestCase(InotifyTestCase):

	def test_create(self):
		test_watch = Watch(mask=IN_CREATE, path=os.path.join(self.test_root_path, 'create_test'))
		self.event_dispatcher.add_watch(test_watch)
		##NOTE - we need to have a way for the test to fail if no event is yielded within time t
		## * multithreading?  use non-blocking IO?
		## ** even if we did use non-blocking IO we would still need to test that
		##    that aspect of the code worked

		#TODO - * start worker process, worker proccess iterates on event generator
		# until it gets the appropriate IN_CREATE Event
		# * parent process joins with an appropriate timeout, then checks
		# the worker process exit code
		# * if the worker process exit code is None, then join() timed out,
		# and we should fail the test.  Otherwise, check for error/non-error
		# exit code
