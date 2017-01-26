# Load DSL and set up stages
require 'capistrano/setup'

# Include default deployment tasks
require 'capistrano/deploy'

# Include tasks from other gems included in your Gemfile
#
# For documentation on these, see for example:
#
#   https://github.com/capistrano/rvm
#   https://github.com/capistrano/rbenv
#   https://github.com/capistrano/chruby
#   https://github.com/capistrano/bundler
#   https://github.com/capistrano/rails
#   https://github.com/capistrano/passenger
#
# require 'capistrano/rvm'
# require 'capistrano/rbenv'
# require 'capistrano/chruby'
# require 'capistrano/bundler'
# require 'capistrano/rails/assets'
# require 'capistrano/rails/migrations'
# require 'capistrano/passenger'

require 'capistrano/setup'
require 'capistrano/deploy'
require 'capistrano/bundler'
require 'capistrano/postgresql'
require 'capistrano/rails/migrations'

def template(from, to, bindings)
  erb = File.read(File.expand_path("../lib/capistrano/tasks/config/#{from}", __FILE__))
  upload! StringIO.new(ERB.new(erb).result(OpenStruct.new(bindings).instance_eval { binding })), to
end

def upload_config(from, to)
  name = from.split("/").last
  upload! StringIO.new(File.read(from)), "/tmp/#{name}"
  execute "sudo mv /tmp/#{name} #{to}"
end

def config(name, destination = nil, bindings = {}, user = 'root', group = 'root')
  destination ||= "/etc/monit.d/#{name}.conf"
  tmp_name = name.split("/").last
  template "#{name}.erb", "/tmp/#{tmp_name}", bindings
  execute "sudo mv /tmp/#{tmp_name} #{destination}"
  execute "sudo chown #{user}:#{group} #{destination}"
  execute "sudo chmod 600 #{destination}"
  execute "sudo chmod +x #{destination}" if name.split(".").last == 'sh'
end


# Load custom tasks from `lib/capistrano/tasks` if you have any defined
Dir.glob('lib/capistrano/tasks/*.rake').each { |r| import r }
