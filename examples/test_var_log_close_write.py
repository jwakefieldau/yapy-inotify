#!/usr/bin/python

from inotify import EventDispatcher, Event, Watch, IN_MODIFY

ed = EventDispatcher()

print "watching IN_MODIFY for all files under /var/log"
 
w = Watch(
	mask=IN_MODIFY,
	path="/var/log",
)

print "adding tree watch %s" % w
	
ed.add_tree_watch(w)

match_path = '/var/log/apache2/access.log'

for event in ed.gen_events():
	print "%s,%x,%s,%x" % (event.name, event.mask, event.full_event_path, event.watch_obj.mask)
	if event.full_event_path == match_path:
		print "Apache access log modified, closing"
		ed.close()

print "Closed event dispatcher"
