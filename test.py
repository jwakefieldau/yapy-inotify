import inotify

fd = inotify.init()
#wd = inotify.add_watch(fd, "/tmp/foo", inotify.IN_CREATE)

#print "watching IN_CREATE on /tmp/foo"

print "watching IN_ACCESS for all files under /tmp/foo, and IN_CREATE for all dirs under /tmp/foo, so that when support is added, IN_ACCESS can be watched for all new files under new dirs"
 
inotify.add_tree_watch(fd, "/tmp/foo", inotify.IN_ACCESS)

for event in inotify.gen_read_events(fd):
	print "%s,%d,%d,%d" % (event.name, event.wd, event.mask, event.cookie)
