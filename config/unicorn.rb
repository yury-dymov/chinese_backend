root = "/srv/http/learnzh/current"
working_directory root
pid "#{root}/tmp/pids/unicorn.pid"
stderr_path "#{root}/log/unicorn.log"
stdout_path "#{root}/log/unicorn.log"

worker_processes 2
listen '4000'
timeout 60

GC.respond_to?(:copy_on_write_friendly=) and GC.copy_on_write_friendly = true

after_fork do |server, worker|
	addr = "#{4000 + worker.nr + 1}"
	server.listen(addr, :tries => -1, :delay => -1, :backlog => 128)
	worker.user('nobody', 'nobody') if Process.euid == 0
	child_pid = server.config[:pid].sub(".pid", ".#{worker.nr}.pid")
	system("echo #{Process.pid} > #{child_pid}")	
end
