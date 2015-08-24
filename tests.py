#!/usr/bin/python

from multiprocessing import Process
from multiprocessing import Event as PEvent

import os
import shutil
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

# ** Test exceptional behaviour - eg: flood of events, 
# attempting to remove watch for file already removed, etc - 
# look at exceptional cases in inotify code ** 


#TODO - docstrings for test case classes and methods

class MakeTree(object):
	"""
	Iterable class to produce paths from a directory tree having a particular
	root and subdirectories n deep and n wide, named 1..n eg: for n = 4,
	root/1/2/3/4 and root/4/2/1/3 will be included in paths produced.
	"""
	
	
	def __init__(self, total_size, root_dir):
		self.total_size = total_size
		self.root_dir = root_dir
		self.cur_subdir_list = []
		self.stop = False

	def _render_output_dir_list(self):
		output_dir_list = [self.root_dir]
		for cur_subdir_digit in self.cur_subdir_list:
			output_dir_list.append(str(cur_subdir_digit))

		return os.path.join(*output_dir_list)


	def __iter__(self):
		return self

	def __next__(self):

		if self.stop:
			raise StopIteration
	
		# return later what we have now, then modify in preparation for next next()
		ret = self._render_output_dir_list()

		# only bother iterating over the list if it's not empty
		if len(self.cur_subdir_list) > 0:

			# start with the assumption that the increment will wrap the current
			# digit back to 0 and we will need to move to the previous (left)
			increment_prev = True
			i = len(self.cur_subdir_list) - 1

			# keep incrementing while the need to keep going left still exists
			# and we stay within the limit of the list
			while increment_prev and i >= 0:

				new_digit = self.cur_subdir_list[i] + 1

				# wrap current digit around to 0
				if new_digit == self.total_size:
					new_digit = 0
					self.cur_subdir_list[i] = new_digit

					# if we haven't spread the list out (right) to its size limit yet,
					# append a 0 digit on the end (right) and flag that we are to
					# stop incrementing; we will pick up from the new digit
					# next iteration
					if len(self.cur_subdir_list) < self.total_size:
						self.cur_subdir_list.append(0)
						increment_prev = False
					# if we're continuing on to the previous digit (left), decrement
					# the index
					else:
						i -= 1

				# if the increment of the current digit didn't wrap, set the new value
				# and flag that we're done for this iteration
				else:
					self.cur_subdir_list[i] = new_digit
					increment_prev = False


			# if we exited the loop because we ran out of digits to increment,
			# raise StopIteration next time
			if i < 0 and increment_prev:
				self.stop = True

		# if the list is empty, start it
		else:
			self.cur_subdir_list.append(0)

		# return whatever was rendered before we started incrementing
		return ret


	def next(self):
		return self.__next__()
		

class InotifyTestCase(unittest.TestCase):
	"""
	Parent class for our test case classes; includes common setup/teardown code,
	common test tasks (writing files, etc), methods for running tests in worker
	processes that use multiprocessing Events to notify of test status, and can
	be terminated by the parent on timeout.
	"""
	
	# In testing, events should take no more than this many seconds to be generated,
	# if they do, the join of the worker process should time out and the parent
	# should terminate it
	worker_timeout = 10

	def setUp(self):
		"""
		Create a subdirectory under /tmp for test files; for collision avoidance and 
		easy identification later in the event that tearDown() failes to remove it, 
		the name is /tmp/python-inotify_test_pid-$PID_$UUID4.  EventDispatcher is 
		also instantiated here.
		"""
		
		self.test_root_path = os.path.join('/tmp', "python-inotify_test_pid-%d_%s" % (os.getpid(), uuid.uuid4())) 	
		os.mkdir(self.test_root_path)
		self.event_dispatcher = EventDispatcher()

	def tearDown(self):
		"""
		Close the EventDispatcher instance and remove test file dir (tree)
		"""

		self.event_dispatcher.close()
		# remove test file root dir and anything in it
		shutil.rmtree(self.test_root_path)

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

	def _event_worker(self, test_watch, num_event_threshold, added_watch_event, got_event, is_tree_watch):
		# test for generation of event that matches
		# test_watch, within the context of a worker process.
		# exit with success if one is generated, if one is
		# not, rely on the parent to kill us 
	
		if is_tree_watch:
			self.event_dispatcher.add_tree_watch(test_watch)
		else:
			self.event_dispatcher.add_watch(test_watch)
		added_watch_event.set()
		num_seen_events = 0
		for event in self.event_dispatcher.gen_events():

			if (event.watch_obj._is_tree and event.watch_obj._tree_root_watch == test_watch) or event.watch_obj == test_watch:	 
				num_seen_events += 1	

			if num_seen_events >= num_event_threshold:
				got_event.set()
				self.event_dispatcher.close()

		sys.exit(0)

	def _tree_write_for_test(self, create_dir_list, write_file_list):
		for create_dir in create_dir_list:
			os.makedirs(create_dir)
		for write_file in write_file_list:
			self._write_for_test(write_file)		
				

	def watchdog_event_worker(self, test_watch, trigger_event_callable, is_tree_watch=False, num_event_threshold=1, trigger_args=(), trigger_kwargs={}):
		"""
		Use a worker process to add watch to event_dispatcher
		and iterate over the event generator until an event
		matching the watch is generated, then exit with success.
		parent process joins the worker with a timeout, after
		the join, if the worker exited with success, then the
		event must have been generated within the timeout and we return True, if
		the exitcode is None, the join must have timed out, so
		the parent terminates the worker and returns False.

		If num_event_threshold is specified, the worker will only 
		succeed if that many events are generated; this supports
		testing of recursive tree watches and load testing generally.

		trigger_event_callable will be called (with trigger_args and
		trigger kwargs) in the parent context after the worker has 
		added the watch, to perform whatever action triggers the kernel
		to generate the event(s).
		"""

		ret = False
		added_watch_event = PEvent()
		got_event = PEvent()
		worker_p = Process(group=None, target=self._event_worker, name=None, args=(test_watch, num_event_threshold, added_watch_event, got_event, is_tree_watch,))
		worker_p.start()

		#don't call this until after worker process has added watch 
		if added_watch_event.wait(self.worker_timeout):
			trigger_event_callable(*trigger_args, **trigger_kwargs)

			if got_event.wait(self.worker_timeout):
				ret = True

		worker_p.terminate()			

		return ret


class CreateTestCase(InotifyTestCase):

	def test_create(self):
		"""
		Catch IN_CREATE for a single file
		"""
	
		test_file_path = os.path.join(self.test_root_path, 'create_test')
		test_watch = Watch(mask=IN_CREATE, path=self.test_root_path)
		worker_test_ret = self.watchdog_event_worker(
				test_watch,
				self._write_for_test,
				trigger_args=(test_file_path,)
		)
		self.assertTrue(worker_test_ret)

	def test_create_tree(self):
		"""
		Catch IN_CREATE for each file and directory in a tree to be created, using
		a recursive tree watch
		"""

		test_file_root_path = os.path.join(self.test_root_path, 'create_tree_test')
		write_file_names = ['foo', 'bar', 'baz']
		write_file_paths = []
		create_dir_paths = []

		for dir_name in MakeTree(3, test_file_root_path):
			create_dir_paths.append(dir_name)
			for file_name in write_file_names:
				write_file_paths.append(os.path.join(dir_name, file_name))

		test_tree_watch = Watch(mask=IN_CREATE, path=self.test_root_path)

		#NOTE - we should see an IN_CREATE event for each dir creation and each file creation
		num_event_threshold = len(write_file_paths) + len(create_dir_paths) + 1

		worker_test_ret = self.watchdog_event_worker(
				test_tree_watch,
				self._tree_write_for_test,
				is_tree_watch=True,
				num_event_threshold=num_event_threshold,
				trigger_args=(create_dir_paths, write_file_paths,),
		)

		self.assertTrue(worker_test_ret)
		

class DeleteTestCase(InotifyTestCase):

	def test_delete(self):
		"""
		Catch IN_DELETE for a single file
		"""

		test_file_path = os.path.join(self.test_root_path, 'delete_test')
		self._write_for_test(test_file_path)
		test_watch = Watch(mask=IN_DELETE, path=self.test_root_path)
		worker_test_ret = self.watchdog_event_worker(
			test_watch,
			os.unlink,
			trigger_args=(test_file_path,)
		)
		self.assertTrue(worker_test_ret)

	def test_delete_tree(self):
		"""
		Catch IN_DELETE for each file and directory in a tree to be created
		and then deleted, using a recursive tree watch 
		"""

		test_file_root_path = os.path.join(self.test_root_path, 'delete_tree_test')
		write_file_names = ['foo', 'bar', 'baz']
		write_file_paths = []
		create_dir_paths = []

		for dir_name in MakeTree(3, test_file_root_path):
			create_dir_paths.append(dir_name)
			for file_name in write_file_names:
				write_file_paths.append(os.path.join(dir_name, file_name))

		self._tree_write_for_test(create_dir_paths, write_file_paths)

		test_tree_watch = Watch(mask=IN_DELETE, path=self.test_root_path)

		# we should get an IN_DELETE event for the root, each dir, and each file
		num_event_threshold = len(create_dir_paths) + len(write_file_paths) + 1
		
		#shutil.rmtree removes everything in a directory tree - files and all
		worker_test_ret = self.watchdog_event_worker(
			test_tree_watch,
			shutil.rmtree,
			is_tree_watch=True,
			num_event_threshold=num_event_threshold,
			trigger_args=(test_file_root_path,)			
		)
		self.assertTrue(worker_test_ret)
			

class AccessTestCase(InotifyTestCase):

	def test_access(self):
		"""
		Catch IN_ACCESS for a single file when it is opened for creation
		"""

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
		"""
		Catch IN_MODIFY for a single file when it is re-written after initial
		creation
		"""

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
		"""
		Catch IN_CLOSE for a single file when it is closed after creation
		"""

		test_file_path = os.path.join(self.test_root_path, 'close_test')
		test_watch = Watch(mask=IN_CLOSE, path=self.test_root_path)
		worker_test_ret = self.watchdog_event_worker(
			test_watch,
			self._write_for_test,
			trigger_args=(test_file_path,)
		)
		self.assertTrue(worker_test_ret)

class ErrorTestCase(InotifyTestCase):
	"""
	Test that errors occur and are handled correctly under applicable
	error conditions
	"""

	def test_watch_nonexistent(self):
		"""
		Test that OSError is raised if a watch is added for a nonexistent file.
		Note that this test is done entirely in the context of a single process
		since we can't forseeably be kept waiting forever.
		"""

		test_file_path = os.path.join(self.test_root_path, 'nonexistent_test')
		test_watch = Watch(mask=IN_ACCESS, path=test_file_path)

		#NOTE - this test is entirely done in the same process rather than
		#a watchdog worker since the exception should be raised immediately;
		#we can't be kept waiting forever
		test_event_dispatcher = EventDispatcher()

		with self.assertRaises(OSError):
			test_event_dispatcher.add_watch(test_watch)

	def test_watch_remove_file_removed(self):
		"""
		Test that the removal of a watch on a file that has been removed after
		it was watched is handled gracefully (ie: silently - no exception raised).
		Note that this test is done entirely in the context of a single process
		since we can't forseeably be kept waiting forever.
		"""

		test_file_path = os.path.join(self.test_root_path, 'watch_remove_file_removed_test')
		self._write_for_test(test_file_path)

		# this test is done in-process, we can't forseeably be kept waiting forever
		test_event_dispatcher = EventDispatcher()
		test_watch = Watch(mask=IN_ACCESS, path=test_file_path)
		test_event_dispatcher.add_watch(test_watch)
		os.unlink(test_file_path)

		try:
			test_event_dispatcher.rm_watch(test_watch)
			no_exc = True
		except:
			no_exc = False
			raise
		finally:
			self.assertTrue(no_exc)



if __name__ == '__main__':
	unittest.main()
