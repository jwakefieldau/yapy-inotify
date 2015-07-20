#!/usr/bin/python

from multiprocessing import Process
from multiprocessing import Event as PEvent

import os
import uuid
import sys
import unittest

from inotify import *

#TODO - figure out why not all IN_CREATE events are read in the create tree 
# test - some kind of buffer filling issue or similar?

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


# create paths for a tree of dirs n levels deep and wide

class MakeTree(object):
	
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
		

# *** WHICH TESTS TO RUN FOR RECURSIVE DIR WATCH VS SINGLE FILE/DIR ? ***
# if some tests have been done for single case, do they need to be re-done for recursive?

class InotifyTestCase(unittest.TestCase):
	
	# In testing, events should take no more than this many seconds to be generated,
	# if they do, the join of the worker process should time out and the parent
	# should terminate it
	worker_timeout = 10

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

		#DEBUG
		print "Added watch %s" % test_watch

		num_seen_events = 0
		for event in self.event_dispatcher.gen_events():

			#DEBUG
			print "Got event %s" % event

			if (event.watch_obj._is_tree and event.watch_obj._tree_root_watch == test_watch) or event.watch_obj == test_watch:	 
				num_seen_events += 1	

				#DEBUG
				print "number of events seen for this worker: %d" % num_seen_events

			if num_seen_events >= num_event_threshold:
				got_event.set()
				self.event_dispatcher.close()

		sys.exit(0)

	def _tree_write_for_test(self, create_dir_list, write_file_list):
		for create_dir in create_dir_list:
			os.makedirs(create_dir)
		for write_file in write_file_list:
			self._write_for_test(write_file)		
				

	#TODO - this needs to support testing of recursive/tree watches 
	# one way could be to pass a number of events that should be yielded,
	# and pass that on to the worker, which counts how many events it 
	# iterates over which is either related directly to the test_watch
	# or whose watch is a child of the test_watch.

	# eg:
	# * we add tree watch to foo_dir
	# * added_watch_event is set by worker
	# * trigger_event_callable in parent runs os.makedirs() and writes foo_dir/bar/1, foo_dir/bar/baz/2, and foo_dir/quux/yes/no/up/down/3
	# ** trigger_event_callable in this case might be eg: _tree_write_for_test()
	# ** the trigger_args might be the list of dirs to create and the list of files to write
	# * if worker iterates over the IN_CREATE events for these three files, it sets got_event and stops iterating, and exits
	# * parent returns from waiting for got_event and passes the test

	#NOTE ** is this part done now? **

			

	def watchdog_event_worker(self, test_watch, trigger_event_callable, is_tree_watch=False, num_event_threshold=1, trigger_args=(), trigger_kwargs={}):
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
		worker_p = Process(group=None, target=self._event_worker, name=None, args=(test_watch, num_event_threshold, added_watch_event, got_event, is_tree_watch,))
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

	def test_create_tree(self):
		test_file_root_path = os.path.join(self.test_root_path, 'create_tree_test')
		write_file_names = ['foo', 'bar', 'baz']
		write_file_paths = []
		create_dir_paths = []

		for dir_name in MakeTree(3, test_file_root_path):

			#DEBUG
			print "dir_name from MakeTree(): %s" % dir_name

			create_dir_paths.append(dir_name)
			for file_name in write_file_names:
				write_file_paths.append(os.path.join(dir_name, file_name))

		test_tree_watch = Watch(mask=IN_CREATE, path=self.test_root_path)

		#NOTE - we should see an IN_CREATE event for each dir creation and each file creation
		# * dirs: 3^3 + 3^2 + 3^1 + 3^0 for dir tree (3 dirs at each of 3 levels plus root dir = 40
		# * files: 3 * dirs = 120
		# * total = 160
		#NOTE - why does this come out wrong/inconsistent?

		num_event_threshold = len(write_file_paths) + len(create_dir_paths) + 1

		#DEBUG
		print "num_event_threshold = len(write_file_paths): %d + len(create_dir_paths): %d" % (len(write_file_paths), len(create_dir_paths))

		worker_test_ret = self.watchdog_event_worker(
				test_tree_watch,
				self._tree_write_for_test,
				is_tree_watch=True,
				num_event_threshold=num_event_threshold,
				trigger_args=(create_dir_paths, write_file_paths,),
		)

		#DEBUG
		print "Expected to get %d events" % num_event_threshold

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
