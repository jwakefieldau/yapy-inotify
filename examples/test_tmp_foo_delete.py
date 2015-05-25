#!/usr/bin/python

from inotify import EventDispatcher, Event, Watch, IN_ACCESS, IN_DELETE

ed = EventDispatcher()

print "watching IN_DELETE for all files under /tmp/foo, recursively"
 
w = Watch(
	mask=IN_DELETE,
	path="/tmp/foo",
)

ed.add_tree_watch(w)

print "added tree watch %s" % w

for event in ed.gen_events():
	print "%s,%x,%s,%x" % (event.name, event.mask, event.full_event_path, event.watch_obj.mask)
	if event.full_event_path == '/tmp/foo/bar/baz':
		ed.rm_watch(event.watch_obj)
