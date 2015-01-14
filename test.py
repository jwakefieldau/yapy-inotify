#!/usr/bin/python

from inotify import EventDispatcher, Event, Watch, IN_ACCESS, IN_DELETE

ed = EventDispatcher()

print "watching IN_DELETE for all files under /tmp/foo, recursively"
 
w = Watch(
	mask=IN_DELETE,
	path="/tmp/foo",
)

print "adding tree watch %s" % w
	
ed.add_tree_watch(w)

for event in ed.gen_events():
	print "%s,%x,%s,%x" % (event.name, event.mask, event.watch_obj.path, event.watch_obj.mask)
