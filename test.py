from inotify import EventDispatcher, Event, Watch, IN_ACCESS

ed = EventDispatcher()

print "watching IN_ACCESS for all files under /tmp/foo, recursively"
 
w = Watch(
	mask=IN_ACCESS,
	path="/tmp/foo",
)
	
ed.add_tree_watch(w)

for event in ed.gen_events():
	print "%s,%x,%s,%x" % (event.name, event.mask, event.watch_obj.path, event.watch_obj.mask)
