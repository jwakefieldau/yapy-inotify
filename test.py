import inotify

fd = inotify.init()
wd = inotify.add_watch(fd, "/tmp/foo", inotify.IN_CREATE)

print "watching IN_CREATE on /tmp/foo"

for event in inotify.gen_read_events(fd):
	print "%s,%d,%d,%d" % (event.name, event.wd, event.mask, event.cookie)
