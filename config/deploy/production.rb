lock '3.4'

set :application, "learnzh"
set :deploy_user, "unicorn"
set :domain_name, "learnzh2.cloudapp.net"

set :scm, "git"
#set :repository, "#{fetch(:deploy_user)}@#{DEPLOY_CONFIG[:roles]["app1"]["name"]}:/home/#{fetch(:deploy_user)}/git/#{fetch(:application)}"
set :repository, "#{fetch(:deploy_user)}@#{fetch(:domain_name)}:/home/#{fetch(:deploy_user)}/git/#{fetch(:application)}"
server "#{fetch(:deploy_user)}@#{fetch(:domain_name)}", roles: [:app, :web, :db]
set :branch, "master"

set :deploy_to, "/srv/http/#{fetch(:application)}"
set :deploy_via, :remote_cache
set :use_sudo, false

set :ruby_version, "2.2"

set :pg_version, "9.4"
#set :pg_host, DEPLOY_CONFIG[:roles]["db1"]["name"]
set :pg_host, fetch(:domain_name)

set :unicorn_port, '4000'
set :unicorn_workers, '2'

set :pty, true

set :bundle_roles, :app

set :ssh_key_path, "/home/unicorn/.ssh/id_rsa.pub"
set :initial_user, "azureuser"
set :initial_password, "C@tx7637"

namespace :azure2 do
  task :add_deploy_user do
    user = fetch(:deploy_user)
    run_locally do
      host = fetch(:domain_name)
      sshpass = "sshpass  -p#{fetch(:initial_password)} ssh -o StrictHostKeyChecking=no #{fetch(:initial_user)}@#{host}"
      execute "(cat #{fetch(:ssh_key_path)} | #{sshpass} 'cat >> /tmp/authorized_keys') && #{sshpass} sudo useradd #{user} -d /home/#{user} -g root  -s /bin/bash && #{sshpass} sudo mkdir -pv /home/#{user}/.ssh && (echo \"#{user} ALL=(ALL) NOPASSWD:ALL\" | #{sshpass} sudo tee --append /etc/sudoers > /dev/null) && #{sshpass} sudo mv /tmp/authorized_keys /home/#{user}/.ssh/authorized_keys && #{sshpass} sudo chown -R #{user} /home/#{user} && #{sshpass} sudo -u #{user} chmod 700 /home/#{user}/.ssh/authorized_keys"
    end
  end

  task :create_swap do
    on roles(:app) do
      execute ("[ -f /swapfile ] || (VAL=`cat /proc/meminfo | awk 'match($1,\"MemTotal\") == 1 {print $2}'` && sudo dd if=/dev/zero of=/swapfile bs=512K count=`expr $VAL / 1024` && sudo chmod 600 /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile && (echo '/swapfile   none    swap    sw    0   0' | sudo tee --append /etc/fstab > /dev/null))")
    end
  end

  task :install_ruby do
    on roles(:app) do
      execute "sudo apt-get -y install ruby-dev"
      execute "sudo apt-get -y install ruby"
      execute "sudo apt-get -y install make"
      execute "sudo apt-get -y install zlib1g-dev"
      execute "sudo apt-get -y install build-essential"
      execute "sudo apt-get install -y ImageMagick"
      execute "sudo apt-get install -y libmagickwand-dev"
      execute "sudo apt-get install -y libpq-dev"
      execute "sudo apt-get install -y libsqlite3-dev"
    end
  end

  task :configure_ruby do
    on roles(:app) do
      execute "[ ! -f /etc/gemrc ] || sudo rm /etc/gemrc"
      execute "echo 'gem: --no-user-install --no-document' | sudo tee --append /etc/gemrc > /dev/null"
    end
  end

  task :install_db do
    on roles(:db) do
      execute "sudo apt-get install -y postgresql"
      execute "sudo apt-get -y install postgresql-contrib"
    end
  end

  task :configure_db do
    on roles(:all) do
      execute "sudo mkdir -pv /srv/http/#{fetch(:application)}/current && sudo mkdir -pv /srv/http/#{fetch(:application)}/db && sudo chown -R #{fetch(:deploy_user)} /srv/http/#{fetch(:application)}"
    end
    run_locally do
      execute "bundle exec cap production setup"
    end
  end

  task :install_app do
    on roles(:app) do
      execute "sudo apt-get install -y git && mkdir -p ~/git/#{fetch(:application)} && cd ~/git/#{fetch(:application)} && git --bare init && sudo mkdir -p /srv/http/#{fetch(:application)}/current && sudo chown -R #{fetch(:deploy_user)}  /srv/http/#{fetch(:application)} && cd /srv/http/#{fetch(:application)}/current && git init && git remote add origin /home/#{fetch(:deploy_user)}/git/#{fetch(:application)}"
    end
    run_locally do
      execute "git remote add origin #{fetch(:repository)}"
      execute "git push origin master"
    end
    on roles(:app) do
      execute("cd #{fetch(:deploy_to)}/current && git pull origin master")
      execute("sudo gem install bundler")
    end
  end

  task :configure_app do
    on roles(:app) do
      execute ("sudo -u postgres psql #{fetch(:application)}_production -c \"CREATE EXTENSION IF NOT EXISTS hstore;\"")
      execute("ln -fs #{fetch(:deploy_to)}/shared/config/database.yml #{fetch(:deploy_to)}/current/config/database.yml")
    end
    invoke "azure2:upload_application_configuration"
    invoke "bundler:install"
  end


  task :upload_application_configuration do
    on roles(:app) do
      config "application.yml", "/srv/http/#{fetch(:application)}/current/config/application.yml", {redis_hosts:[]}, "unicorn", "root"
    end
  end

  task :configure_unicorn do
    on roles(:app) do |role|
      app = "unicorn_#{fetch(:application)}"
      config 'unicorn.rb', "#{fetch(:deploy_to)}/current/config/unicorn.rb", {app_root:fetch(:deploy_to) + "/current", port:fetch(:unicorn_port), workers:fetch(:unicorn_workers), host:role}, fetch(:deploy_user)
      config 'unicorn.service.sh', "/etc/systemd/system/#{app}.service", {app_path:fetch(:deploy_to) + "/current", app_user:fetch(:deploy_user)}, 'root'
      execute ("cd #{fetch(:deploy_to)}/current && ([ -d tmp/pids ] || mkdir -p tmp/pids )")
      execute ("sudo systemctl enable #{app}")
      execute ("sudo systemctl start #{app}")
    end
  end


  task :install_web do
    on roles(:web, :app) do
      execute "sudo apt-get install -y nginx"
      execute "sudo systemctl enable nginx"
    end
  end

  task :configure_web do
    on roles(:app) do |role|
      config 'nginx.conf', '/etc/nginx/nginx.conf', {app_path:fetch(:deploy_to) + "/current", children:fetch(:unicorn_workers).to_i, port:fetch(:unicorn_port).to_i, host:role, domain_name:fetch(:domain_name)}, 'root'
      execute "sudo nginx -s reload"
    end
  end


  task :all do
    invoke "azure2:add_deploy_user"
    invoke "azure2:create_swap"
    invoke "azure2:install_ruby"
    invoke "azure2:configure_ruby"
    invoke "azure2:install_db"
    invoke "azure2:configure_db"
    invoke "azure2:install_app"
    invoke "azure2:configure_app"
    invoke "azure2:configure_unicorn"
  end

end


namespace :azure do
  def _get_all_hosts
    hosts = []
    DEPLOY_CONFIG[:roles].each {|key, value| hosts << {host:value["name"], ip:value["ip"]} }
    hosts
  end

  task :clean_local_hosts do
    run_locally do
      _get_all_hosts.each do |server|
        execute "sudo sed -i '/\s#{server[:host]}$/d' /etc/hosts"
        execute "sudo sed -i '/\s#{server[:host]}$/d' ~/.ssh/known_hosts"
      end
    end
  end

  task :update_local_hosts do
    invoke "azure:clean_local_hosts"
    run_locally do
      _get_all_hosts.each do |server|
        execute "echo \"#{server[:ip]} #{server[:host]}\" | sudo tee --append /etc/hosts > /dev/null"
      end
    end
  end

  task :add_deploy_user do
    user = fetch(:deploy_user)
    run_locally do
      _get_all_hosts.each do |server|
        ip = server[:ip]
        host = server[:host]
        sshpass = "sshpass  -p#{fetch(:initial_password)} ssh -o StrictHostKeyChecking=no #{fetch(:initial_user)}@#{host}"
        execute "(cat #{fetch(:ssh_key_path)} | #{sshpass} 'cat >> /tmp/authorized_keys') && #{sshpass} sudo useradd #{user} -d /home/#{user} -g root  -s /bin/bash && #{sshpass} sudo mkdir -pv /home/#{user}/.ssh && (echo \"#{user} ALL=(ALL) NOPASSWD:ALL\" | #{sshpass} sudo tee --append /etc/sudoers > /dev/null) && #{sshpass} sudo mv /tmp/authorized_keys /home/#{user}/.ssh/authorized_keys && #{sshpass} sudo chown -R #{user} /home/#{user} && #{sshpass} sudo -u #{user} chmod 700 /home/#{user}/.ssh/authorized_keys"
      end
    end
  end

  task :update_remote_hosts do
    on roles(:app, :web, :db, :files) do
      _get_all_hosts.each do |server|
        execute "sudo sed -i '/\s#{server[:host]}$/d' /etc/hosts"
        execute "echo \"#{server[:ip]} #{server[:host]}\" | sudo tee --append /etc/hosts > /dev/null"
      end
    end
  end

  task :init do
    invoke "azure:update_local_hosts"
    invoke "azure:add_deploy_user"
    invoke "azure:update_remote_hosts"
  end

  task :create_swap do
    on roles(:web, :app, :db, :files) do
      execute ("[ -f /swapfile ] || (VAL=`cat /proc/meminfo | awk 'match($1,\"MemTotal\") == 1 {print $2}'` && sudo dd if=/dev/zero of=/swapfile bs=512K count=`expr $VAL / 1024` && sudo chmod 600 /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile && (echo '/swapfile   none    swap    sw    0   0' | sudo tee --append /etc/fstab > /dev/null))")
    end
  end

  task :temp do
#    invoke "azure:clean_local_hosts"
    invoke "azure:install_fs"
    invoke "azure:configure_fs"
  end

  task :install_ruby do
    on roles(:app) do
      execute "sudo apt-get update"
      execute "sudo apt-add-repository ppa:brightbox/ruby-ng"
      execute "sudo apt-get update"
      execute "sudo apt-get -y install ruby#{fetch(:ruby_version)}-dev"
      execute "sudo apt-get -y install ruby#{fetch(:ruby_version)}"
      execute "sudo apt-get -y install make"
      execute "sudo apt-get -y install zlib1g-dev"
      execute "sudo apt-get -y install build-essential"
      execute "sudo apt-get install -y ImageMagick"
      execute "sudo apt-get install -y libmagickwand-dev"
      execute "sudo apt-get install -y libpq-dev"
      execute "sudo apt-get install -y libsqlite3-dev"
    end
  end

  task :configure_ruby do
    on roles(:app) do
      execute "[ ! -f /etc/gemrc ] || sudo rm /etc/gemrc"
      execute "echo 'gem: --no-user-install --no-document' | sudo tee --append /etc/gemrc > /dev/null"
    end
  end

  task :install_db do
    on roles(:db) do
      execute "sudo apt-get install -y postgresql"
      execute "sudo apt-get install -y redis-server"
      execute "sudo apt-get -y install postgresql-contrib"
    end
  end

  task :create_db_config do
    on roles(:db, select: :master) do |role|
      config 'db/postgresql.conf', "/etc/postgresql/#{fetch(:pg_version)}/main/postgresql.conf", {pg_version:fetch(:pg_version), listen:role, slave: false}, 'postgres', 'postgres'
    end
    on roles(:db, exclude: :master) do |role|
      config 'db/postgresql.conf', "/etc/postgresql/#{fetch(:pg_version)}/main/postgresql.conf", {pg_version:fetch(:pg_version), listen:role, slave: true}, 'postgres', 'postgres'
    end
    on roles(:db) do
      config 'db/pg_hba.conf', "/etc/postgresql/#{fetch(:pg_version)}/main/pg_hba.conf", {app_roles:app_roles, db_roles:db_roles, application: fetch(:application)}, 'postgres', 'postgres'
      execute "sudo service postgresql restart"
    end
  end

  task :create_db_replicator do
    on roles(:db, select: :master) do
      execute "sudo -u postgres psql -c \"CREATE USER replicator REPLICATION LOGIN ENCRYPTED PASSWORD '#{(0...50).map { ('a'..'z').to_a[rand(26)] }.join}';\""
    end
  end

  task :setup_db_slave do
    on roles(:db, exclude: :master) do |role|
      host = ""
      DEPLOY_CONFIG[:roles].each do |key, value|
        if key =~ /^db/ && value["master"]
          host = value["name"]
          break
        end
      end
      execute "sudo service postgresql stop"
      execute "sudo -u postgres rm -rf /var/lib/postgresql/#{fetch(:pg_version)}/main"
      execute "sudo su - postgres -s /bin/bash --command='/usr/bin/pg_basebackup -h #{host} -D /var/lib/postgresql/#{fetch(:pg_version)}/main -P -U replicator --xlog-method=stream'"
      config 'db/recovery.conf', "/var/lib/postgresql/#{fetch(:pg_version)}/main/recovery.conf", {primary_role:db_roles[0]}, 'postgres', 'postgres'
      execute "sudo service postgresql start"
    end
  end


  task :configure_db do
    invoke "azure:create_db_config"
    invoke "azure:create_db_replicator"
    on roles(:all) do
      execute "sudo mkdir -pv /srv/http/#{fetch(:application)}/current && sudo chown -R #{fetch(:deploy_user)} /srv/http/#{fetch(:application)}"
    end
    invoke "postgresql:setup"
    on roles(:web, :db, :files) do
      execute "sudo rm -rf /srv/http/#{fetch(:application)}"
    end
  end

  task :install_app do
    on roles(:app, select: :master) do |role|
      execute "sudo apt-get install -y git && mkdir -p ~/git/#{fetch(:application)} && cd ~/git/#{fetch(:application)} && git --bare init && sudo mkdir -p /srv/http/#{fetch(:application)}/current && sudo chown -R #{fetch(:deploy_user)}  /srv/http/#{fetch(:application)} && cd /srv/http/#{fetch(:application)}/current && git init && git remote add origin /home/#{fetch(:deploy_user)}/git/#{fetch(:application)}"
    end
    on roles(:app, exclude: :master) do |role|
      host = ""
      DEPLOY_CONFIG[:roles].each do |key, value|
        if key =~ /^app/ && value["master"]
          host = value["name"]
          break
        end
      end
      execute "sudo apt-get install -y git && sudo mkdir -p /srv/http/#{fetch(:application)}/current && sudo chown -R #{fetch(:deploy_user)} /srv/http/#{fetch(:application)} && cd /srv/http/#{fetch(:application)}/current && git init && git remote add origin ssh://#{fetch(:deploy_user)}@#{host}:/home/#{fetch(:deploy_user)}/git/#{fetch(:application)}"
    end
    run_locally do
      execute "git remote rm origin"
      execute "git remote add origin #{fetch(:repository)}"
      execute "git push origin master"
    end
    on roles(:app) do
      execute("cd #{fetch(:deploy_to)}/current && git pull origin master")
    end
    on roles(:app) do
      execute("sudo gem install bundler")
    end
  end

  task :setup_app_access do
    host = ""
    on roles(:app, exclude: :master) do |role|
      DEPLOY_CONFIG[:roles].each do |key, value|
        if key =~ /^app/ && value["master"]
          host = value["name"]
          break
        end
      end
      execute "sudo apt-get install -y sshpass"
      execute "ssh-keygen -t rsa -C \"yuri@dymov.me\" -P '' -f ~/.ssh/id_rsa"
      execute "cat /home/#{fetch(:deploy_user)}/.ssh/id_rsa.pub | sshpass -p#{fetch(:initial_password)} ssh -o StrictHostKeyChecking=no #{fetch(:initial_user)}@#{host} 'sudo tee -a /home/#{fetch(:deploy_user)}/.ssh/authorized_keys >/dev/null'"
    end
  end

  task :configure_app do
    on roles(:db, select: :master) do
      execute ("sudo -u postgres psql #{fetch(:application)}_production -c \"CREATE EXTENSION IF NOT EXISTS hstore;\"")
    end
    on roles(:app) do
      execute("ln -fs #{fetch(:deploy_to)}/shared/config/database.yml #{fetch(:deploy_to)}/current/config/database.yml")
    end
    invoke "azure:upload_application_configuration"
    invoke "bundler:install"
    on roles(:app) do
#      execute "cd #{fetch(:deploy_to)}/current && bundle exec rake db:migrate RAILS_ENV=production"
    end
#    invoke "me:configure_cron"
  end

  task :upload_application_configuration do
    on roles(:app) do
      hosts = []
      DEPLOY_CONFIG[:roles].each do |key, value|
        if key =~ /^db/
          hosts << value["name"]
        end
      end
      config "application.yml", "/srv/http/#{fetch(:application)}/current/config/application.yml", {redis_hosts:hosts}, "unicorn", "root"
    end
  end

  task :configure_redis do
    on roles(:db, select: :master) do |role|
      config 'redis/redis.conf', "/etc/redis/redis.conf", {host:role}, 'redis', 'redis'
    end
    on roles(:db, exclude: :master) do |role|
      master = ""
      slaves = []
      DEPLOY_CONFIG[:roles].each do |key, value|
        if key =~ /^db/
          if value["master"]
            master = value["name"]
          else
            slaves << value["name"]
          end
        end
      end
      config 'redis/redis.conf', "/etc/redis/redis.conf", {host:role, master:master}, 'redis', 'redis'
    end
    on roles(:db) do |role|
      master = ""
      slaves = []
      DEPLOY_CONFIG[:roles].each do |key, value|
        if key =~ /^db/
          if value["master"]
            master = value["name"]
          else
            slaves << value["name"]
          end
        end
      end
      config "redis/sentinel.conf", "/etc/redis/sentinel.conf", {master:master, slaves:slaves}, "redis", "redis"
      config "redis/redis-sentinel.sh", "/etc/init.d/redis-sentinel", {host:role}, "root", "root"
      execute "sudo nohup service redis-server restart"
      execute "sudo nohup service redis-sentinel restart"
    end
  end

  task :configure_unicorn do
    on roles(:app) do |role|
      app = "unicorn_#{fetch(:application)}"
      config 'unicorn.rb', "#{fetch(:deploy_to)}/current/config/unicorn.rb", {app_root:fetch(:deploy_to) + "/current", port:fetch(:unicorn_port), workers:fetch(:unicorn_workers), host:role}, fetch(:deploy_user)
      config 'unicorn.sh', "/etc/init.d/#{app}", {app_path:fetch(:deploy_to) + "/current", app_user:fetch(:deploy_user)}, 'root'
      execute ("cd #{fetch(:deploy_to)}/current && ([ -d tmp/pids ] || mkdir -p tmp/pids )")
      execute ("sudo systemctl enable #{app}")
      execute ("sudo systemctl start #{app}")
    end
  end


  task :restart_unicorn do
    on roles(:app) do
      execute ("sudo service unicorn_#{fetch(:application)} restart")
    end
  end

  task :install_fs do
    on roles(:files) do
      execute "sudo add-apt-repository ppa:gluster/glusterfs-3.5 -y"
      execute "sudo apt-get update"
      execute "sudo apt-get install -y glusterfs-server"
    end
    on roles(:app) do
      execute "sudo apt-get install -y glusterfs-client"
    end
  end


  task :configure_fs do
    on roles(:files, select: :master) do |role|
    #/etc/glusterfs/vol to fix
      roles = ""
      DEPLOY_CONFIG[:roles].each {|key, value| roles += "#{value["name"]}:/fs " if key =~ /^files/ }
      DEPLOY_CONFIG[:roles].each {|key, value| execute "sudo gluster peer probe #{value["name"]}" if key =~ /^files/ && value["name"] != role.to_s }
      execute "sudo gluster volume create fs replica 2 transport tcp #{roles} force"
      execute "sudo gluster volume start fs"
      apps = ""
      DEPLOY_CONFIG[:roles].each {|key, value| apps += "#{value["ip"]}," if key =~ /^app/ }
      execute "sudo gluster volume set fs server.allow-insecure on"
      execute "sudo gluster volume set fs auth.allow '#{apps[0..-2]}'"
    end
    on roles(:app) do
      role = ""
      DEPLOY_CONFIG[:roles].each do |key, value|
        if key =~ /^files/
          role = value["name"]
          break
        end
      end
      folder = "#{fetch(:deploy_to)}/current/public/system"
      execute "sudo mkdir -pv #{folder}"
      execute "sudo mount -t glusterfs #{role}:fs #{folder}"
      execute "sudo chown -R #{fetch(:deploy_user)} #{folder}"
      execute "echo '#{role}:/fs             #{folder}          glusterfs     defaults,_netdev        ' | sudo tee -a /etc/fstab >/dev/null"
    end
  end



  task :all do
    invoke "azure:init"
    invoke "azure:create_swap"
    invoke "azure:install_ruby"
    invoke "azure:configure_ruby"
    invoke "azure:install_db"
    invoke "azure:configure_db"
    invoke "azure:setup_app_access"
    invoke "azure:install_app"
    invoke "azure:configure_app"
#    invoke "azure:configure_redis"
    invoke "azure:configure_unicorn"
#    invoke "azure:install_fs"
#    invoke "azure:configure_fs"
  end
end


def _roles(prefix)
  ret = []
  ips = {}
  DEPLOY_CONFIG[:roles].each do |key, value|
    if key =~ /^#{prefix}/
      ret << value["name"] if ips[value["ip"]].nil?
      ips[value["ip"]] = 1
    end
  end
  ret
end

def app_roles
  _roles("app")
end

def db_roles
  _roles("db")
end


namespace :me do
  task :make_sh do
    erb = File.read(File.expand_path("../../lib/capistrano/tasks/config/hosts.sh.erb", __FILE__))
    bindings = {servers:DEPLOY_CONFIG[:roles].values}
    File.write('hosts.sh', ERB.new(erb).result(OpenStruct.new(bindings).instance_eval { binding }))
    erb = File.read(File.expand_path("../../lib/capistrano/tasks/config/install.sh.erb", __FILE__))
    bindings = {deploy_user:fetch(:deploy_user), application:fetch(:application), servers:DEPLOY_CONFIG[:roles].values}
    File.write('install.sh', ERB.new(erb).result(OpenStruct.new(bindings).instance_eval { binding }))
  end

  task :roles do
    run_locally do
      erb = File.read(File.expand_path("../../lib/capistrano/tasks/config/hosts.sh.erb", __FILE__))
      bindings = {servers:DEPLOY_CONFIG[:roles].values}
      File.write('hosts.sh', ERB.new(erb).result(OpenStruct.new(bindings).instance_eval { binding }))
      erb = File.read(File.expand_path("../../lib/capistrano/tasks/config/install.sh.erb", __FILE__))
      bindings = {deploy_user:fetch(:deploy_user), application:fetch(:application), servers:DEPLOY_CONFIG[:roles].values}
      File.write('install.sh', ERB.new(erb).result(OpenStruct.new(bindings).instance_eval { binding }))
      system('bash install.sh')
      system('rm hosts.sh')
      system('rm install.sh')
    end
  end

  task :create_swap do
#    on roles(:all) do
#      execute "sudo swapoff -a"
#      execute "[ ! -f /swapfile ] || sudo rm /swapfile"
#    end
    on roles(:web, :files, :db) do
      execute "sudo dd if=/dev/zero of=/swapfile bs=512K count=1024"
      execute "sudo chmod 600 /swapfile"
      execute "sudo mkswap /swapfile"
      execute "sudo swapon /swapfile"
      execute "sudo /bin/bash -c \"echo '/swapfile   none    swap    sw    0   0' >> /etc/fstab\""
    end
    on roles(:app) do
      execute "sudo dd if=/dev/zero of=/swapfile bs=512K count=2048"
      execute "sudo chmod 600 /swapfile"
      execute "sudo mkswap /swapfile"
      execute "sudo swapon /swapfile"
      execute "sudo /bin/bash -c \"echo '/swapfile   none    swap    sw    0   0' >> /etc/fstab\""
    end
  end

  task :install_certificates do
    on roles(:app, exclude: :master) do |role|
      execute "ssh-keygen -f ~/.ssh/id_rsa -t rsa -N ''"
      run_locally do
        execute "scp #{fetch(:deploy_user)}@#{role}:/home/#{fetch(:deploy_user)}/.ssh/id_rsa.pub /tmp/id_rsa.pub"
        execute "cat /tmp/id_rsa.pub | ssh  -o StrictHostKeyChecking=no #{fetch(:deploy_user)}@#{DEPLOY_CONFIG[:roles][app_roles[0]]["name"]} 'cat >> ~/.ssh/authorized_keys'"
        execute "rm /tmp/id_rsa.pub"
      end
    end
  end

  task :install_ruby do
    on roles(:app) do
      execute "sudo apt-get install -y software-properties-common"
      execute "sudo apt-add-repository -y ppa:brightbox/ruby-ng"
      execute "sudo apt-get update"
      execute "sudo apt-get -y install ruby#{fetch(:ruby_version)}-dev"
      execute "sudo apt-get -y install ruby#{fetch(:ruby_version)}"
      execute "sudo apt-get -y install make"
      execute "sudo apt-get -y install zlib1g-dev" #nokogiri
      execute "sudo apt-get -y install build-essential"
      execute "sudo apt-get install -y ImageMagick"
      execute "sudo apt-get install -y libmagickwand-dev"
    end
  end

  task :configure_ruby do
    on roles(:app) do
      execute "[ ! -f /etc/gemrc ] || sudo rm /etc/gemrc"
      execute "sudo /bin/bash -c \"echo gem: --no-user-install --no-document > /etc/gemrc\""
    end
  end

  task :install_db do
    on roles(:db) do
      execute "sudo apt-get install -y postgresql"
      execute "sudo apt-get install -y redis-server"
      execute("sudo apt-get -y install postgresql-contrib")
    end
    on roles(:app) do
      execute "sudo apt-get install -y libpq-dev"
    end
  end

  task :configure_db do
    on roles(:db, select: :master) do |role|
      config('db/postgresql.conf', "/etc/postgresql/#{fetch(:pg_version)}/main/postgresql.conf", {pg_version:fetch(:pg_version), listen:role, slave: false}, 'postgres', 'postgres')
    end
    on roles(:db, exclude: :master) do |role|
      config 'db/postgresql.conf', "/etc/postgresql/#{fetch(:pg_version)}/main/postgresql.conf", {pg_version:fetch(:pg_version), listen:role, slave: true}, 'postgres', 'postgres'
    end
    on roles(:db) do
      config 'db/pg_hba.conf', "/etc/postgresql/#{fetch(:pg_version)}/main/pg_hba.conf", {app_roles:app_roles, db_roles:db_roles, application: fetch(:application)}, 'postgres', 'postgres'
      execute "sudo service postgresql restart"
    end
    on roles(:db, select: :master) do
      execute "sudo -u postgres psql -c \"CREATE USER replicator REPLICATION LOGIN ENCRYPTED PASSWORD '#{(0...50).map { ('a'..'z').to_a[rand(26)] }.join}';\""
    end
    on roles(:all) do
      execute "sudo mkdir -pv /srv/http/#{fetch(:application)}/current && sudo chown -R #{fetch(:deploy_user)} /srv/http/#{fetch(:application)}"
    end
    invoke "postgresql:setup"
    on roles(:web, :db, :files) do
      execute "sudo rm -rf /srv/http/#{fetch(:application)}"
    end
    on roles(:db, exclude: :master) do |role|
      host = ""
      DEPLOY_CONFIG[:roles].each do |key, value|
        if key =~ /^db/ && value["master"]
          host = value["name"]
          break
        end
      end
      execute "sudo service postgresql stop"
      execute "sudo -u postgres rm -rf /var/lib/postgresql/#{fetch(:pg_version)}/main"
      execute "sudo su - postgres -s /bin/bash --command='/usr/bin/pg_basebackup -h #{host} -D /var/lib/postgresql/#{fetch(:pg_version)}/main -P -U replicator --xlog-method=stream'"
      config 'db/recovery.conf', "/var/lib/postgresql/#{fetch(:pg_version)}/main/recovery.conf", {primary_role:db_roles[0]}, 'postgres', 'postgres'
      execute "sudo service postgresql start"
    end
  end

  task :install_app do
    on roles(:app, select: :master) do |role|
      execute "sudo apt-get install -y git && mkdir -p ~/git/#{fetch(:application)} && cd ~/git/#{fetch(:application)} && git --bare init && sudo mkdir -p /srv/http/#{fetch(:application)}/current && sudo chown -R #{fetch(:deploy_user)}  /srv/http/#{fetch(:application)} && cd /srv/http/#{fetch(:application)}/current && git init && git remote add origin /home/#{fetch(:deploy_user)}/git/#{fetch(:application)}"
    end
    on roles(:app, exclude: :master) do |role|
      execute "sudo apt-get install -y git && sudo mkdir -p /srv/http/#{fetch(:application)}/current && sudo chown -R #{fetch(:deploy_user)} /srv/http/#{fetch(:application)} && cd /srv/http/#{fetch(:application)}/current && git init && git remote rm origin && git remote add origin ssh://#{fetch(:deploy_user)}@#{DEPLOY_CONFIG[:roles][app_roles[0]]["name"]}:/home/#{fetch(:deploy_user)}/git/#{fetch(:application)}"
    end
    run_locally do
      execute "git remote rm origin"
      execute "git remote add origin #{fetch(:repository)}"
      execute "git push origin master"
    end
    on roles(:app) do
      execute("cd #{fetch(:deploy_to)}/current && git pull origin master")
    end
    on roles(:app) do
      execute("sudo gem install bundler")
    end
  end

  task :configure_app do
    on roles(:all) do
      execute ("sudo mkdir -pv /srv/http/#{fetch(:application)}/db && sudo chown -R #{fetch(:deploy_user)} /srv/http/#{fetch(:application)}")
    end
    on roles(:db, select: :master) do
      execute ("sudo -u postgres psql #{fetch(:application)}_production -c \"CREATE EXTENSION IF NOT EXISTS hstore;\"")
    end
    on roles(:files, :db, :web) do
      execute "sudo rm -rf /srv/http/#{fetch(:application)}"
    end
    on roles(:app) do
      execute("ln -fs #{fetch(:deploy_to)}/shared/config/database.yml #{fetch(:deploy_to)}/current/config/database.yml")
    end
    invoke "me:upload_application_configuration"
    invoke "bundler:install"
    on roles(:app) do
      execute "cd #{fetch(:deploy_to)}/current && bundle exec rake db:migrate RAILS_ENV=production"
    end
    invoke "me:configure_cron"
  end

  task :configure_cron do
    on roles(:app, select: :master) do
      #tbd cron on many hosts
      execute "cd #{fetch(:deploy_to)}/current && bundle exec whenever -w"
    end
  end

  task :migrate_data do
    invoke "me:upload_application_configuration"
    on roles(:app, select: :master) do |role|
      execute("cd /srv/http/#{fetch(:application)}/current && bundle exec rake db:migrate RAILS_ENV=production && bundle exec rake db:seed RAILS_ENV=production")
    end
  end

  task :upload_application_configuration do
    on roles(:app) do
      hosts = []
      DEPLOY_CONFIG[:roles].each do |key, value|
        if key =~ /^db/
          hosts << value["name"]
        end
      end
      config "application.yml", "/srv/http/#{fetch(:application)}/current/config/application.yml", {redis_hosts:hosts}, "unicorn", "root"
    end
  end

  task :temp do
    on roles(:app) do |role|
      backend = ""
      DEPLOY_CONFIG[:roles].each do |key, value|
        if key =~ /^app/
          backend = value["name"]
          break
        end
      end

      config 'nginx_app.conf', '/etc/nginx/nginx.conf', {app_path:fetch(:deploy_to) + "/current", children:fetch(:unicorn_workers).to_i, port:fetch(:unicorn_port).to_i, host:role, domain_name:fetch(:domain_name)}, 'root'
      execute ("sudo nginx -s reload")
    end

  end

  task :configure_redis do
    on roles(:db, select: :master) do |role|
      config 'redis/redis.conf', "/etc/redis/redis.conf", {host:role}, 'redis', 'redis'
    end
    on roles(:db, exclude: :master) do |role|
      master = ""
      slaves = []
      DEPLOY_CONFIG[:roles].each do |key, value|
        if key =~ /^db/
          if value["master"]
            master = value["name"]
          else
            slaves << value["name"]
          end
        end
      end
      config 'redis/redis.conf', "/etc/redis/redis.conf", {host:role, master:master}, 'redis', 'redis'
    end
    on roles(:db) do |role|
      master = ""
      slaves = []
      DEPLOY_CONFIG[:roles].each do |key, value|
        if key =~ /^db/
          if value["master"]
            master = value["name"]
          else
            slaves << value["name"]
          end
        end
      end
      config "redis/sentinel.conf", "/etc/redis/sentinel.conf", {master:master, slaves:slaves}, "redis", "redis"
      config "redis/redis-sentinel.sh", "/etc/init.d/redis-sentinel", {host:role}, "root", "root"
      execute "sudo nohup service redis-server restart"
      execute "sudo nohup service redis-sentinel restart"
    end
  end

  task :configure_unicorn do
    on roles(:app) do |role|
      app = "unicorn_#{fetch(:application)}"
      config 'unicorn.rb', "#{fetch(:deploy_to)}/current/config/unicorn.rb", {app_root:fetch(:deploy_to) + "/current", port:fetch(:unicorn_port), workers:fetch(:unicorn_workers), host:role}, fetch(:deploy_user)
      config 'unicorn.sh', "/etc/init.d/#{app}", {app_path:fetch(:deploy_to) + "/current", app_user:fetch(:deploy_user)}, 'root'
      execute ("cd #{fetch(:deploy_to)}/current && ([ -d tmp/pids ] || mkdir -p tmp/pids )")
      execute ("sudo service #{app} start")
      execute "sudo update-rc.d #{app} defaults"
    end
  end

  task :configure_unicorn do
    on roles(:app) do
      app = "unicorn_#{fetch(:application)}"
      config 'unicorn.rb', "#{fetch(:deploy_to)}/current/config/unicorn.rb", {app_root:fetch(:deploy_to) + "/current", port:fetch(:unicorn_port), workers:fetch(:unicorn_workers), host:role}, fetch(:deploy_user)
      config 'unicorn.service.sh', "/etc/systemd/system/#{app}.service", {app_path:fetch(:deploy_to) + "/current", app_user:fetch(:deploy_user)}, 'root'
      execute "sudo service #{app} start"
      execute "sudo update-rc.d #{app} defaults"
    end
  end

  task :restart_unicorn do
    on roles(:app) do
      execute ("sudo service unicorn_#{fetch(:application)} restart")
    end
  end


  task :install_fs do
    on roles(:files) do
      execute "sudo apt-get install -y python-software-properties"
      execute "sudo add-apt-repository -y ppa:semiosis/ubuntu-glusterfs-3.5"
      execute "sudo apt-get update"
      execute "sudo apt-get install -y glusterfs-server"
    end
    on roles(:app) do
      execute "sudo apt-get install -y glusterfs-client"
    end
  end

  task :configure_fs do
    on roles(:files, select: :master) do |role|
      roles = ""
      DEPLOY_CONFIG[:roles].each {|key, value| roles += "#{value["name"]}:/fs " if key =~ /^files/ }
      DEPLOY_CONFIG[:roles].each {|key, value| execute "sudo gluster peer probe #{value["name"]}" if key =~ /^files/ && value["name"] != role.to_s }
      execute "sudo gluster volume create fs replica 2 transport tcp #{roles} force"
      execute "sudo gluster volume start fs"
      apps = ""
      DEPLOY_CONFIG[:roles].each {|key, value| apps += "#{value["internal-ip"]}," if key =~ /^app/ }
      execute "sudo gluster volume set fs auth.allow #{apps[0..-2]}"
    end
    on roles(:app) do
      role = ""
      DEPLOY_CONFIG[:roles].each do |key, value|
        if key =~ /^files/
          role = value["name"]
          break
        end
      end
      folder = "#{fetch(:deploy_to)}/current/public/system"
      execute "mkdir -pv #{folder}"
      execute "sudo mount -t glusterfs #{role}:fs #{folder}"
      execute "sudo chown -R #{fetch(:deploy_user)} #{folder}"
      execute "sudo /bin/bash -c \"echo '#{role}:/fs             #{folder}          glusterfs     defaults,_netdev        ' >> /etc/fstab\""
    end
  end

  task :install_web do
    on roles(:web, :app) do
      execute "sudo apt-get install -y nginx"
    end
  end

  task :configure_web do
    on roles(:web) do
      backend = ""
      DEPLOY_CONFIG[:roles].each do |key, value|
        if key =~ /^app/
          backend = value["name"]
          break
        end
      end

      execute "sudo mkdir -pv /etc/nginx/ssl"
      config "real_ip.conf", "/etc/nginx/real_ip.conf", {}, "root"
      upload_config "ssl/#{fetch(:domain_name)}.crt", "/etc/nginx/ssl/#{fetch(:domain_name)}.crt"
      upload_config "ssl/#{fetch(:domain_name)}.key", "/etc/nginx/ssl/#{fetch(:domain_name)}.key"
      config 'nginx.conf', '/etc/nginx/nginx.conf', {domain_name:fetch(:domain_name), backend:backend}, 'root'
      execute ("sudo nginx -s reload")
    end
    on roles(:app) do |role|
      config 'nginx_app.conf', '/etc/nginx/nginx.conf', {app_path:fetch(:deploy_to) + "/current", children:fetch(:unicorn_workers).to_i, port:fetch(:unicorn_port).to_i, host:role, domain_name:fetch(:domain_name)}, 'root'
      execute "sudo nginx -s reload"
    end
  end



  task :setup do
    invoke "me:roles"
    invoke "me:create_swap"
    invoke "me:install_certificates"
    invoke "me:install_ruby"
    invoke "me:configure_ruby"
    invoke "me:install_db"
    invoke "me:configure_db"
    invoke "me:configure_redis"
    invoke "me:install_app"
    invoke "me:configure_app"
    invoke "me:configure_unicorn"
    invoke "me:install_web"
    invoke "me:configure_web"

  end

end


namespace :git do
  desc 'Deploy'
   task :deploy do
     ask(:message, "Commit message?")
     run_locally do
       execute "git add --all"
       execute "git commit -m '#{fetch(:message)}'"
       execute "git push origin master"
     end
     on roles(:app) do
       execute "cd #{fetch(:deploy_to)}/current && git pull origin master"
     end
   end
end

namespace :deploy do
  task :run_with_assets do
    run_locally do
      execute "rake assets:clobber"
      execute "rake assets:precompile RAILS_ENV=production"
      assets = Dir.glob('lib/assets/**/*')
      assets.each do |file|
        source = 'public/assets/' + file.split('/').last
        FileUtils.cp(file, source)
      end
    end
    invoke "deploy:run"
  end

  task :run do
    invoke "git:deploy"
    invoke "bundler:install"
    on roles(:app, select: :master) do
      execute("cd #{fetch(:deploy_to)}/current && bundle exec rake db:migrate RAILS_ENV=production")
    end
    invoke "deploy:restart"
  end

  task :run_no_git do
    invoke "bundler:install"
    on roles(:app, select: :master) do
      execute("cd #{fetch(:deploy_to)}/current && bundle exec rake db:migrate RAILS_ENV=production")
    end
    invoke "deploy:restart"
  end

  task :restart do
    on roles(:app) do
      execute "sudo service unicorn_#{fetch(:application)} restart"
    end
  end
end

# server-based syntax
# ======================
# Defines a single server with a list of roles and multiple properties.
# You can define all roles on a single server, or split them:

# server 'example.com', user: 'deploy', roles: %w{app db web}, my_property: :my_value
# server 'example.com', user: 'deploy', roles: %w{app web}, other_property: :other_value
# server 'db.example.com', user: 'deploy', roles: %w{db}



# role-based syntax
# ==================

# Defines a role with one or multiple servers. The primary server in each
# group is considered to be the first unless any  hosts have the primary
# property set. Specify the username and a domain or IP for the server.
# Don't use `:all`, it's a meta role.

# role :app, %w{deploy@example.com}, my_property: :my_value
# role :web, %w{user1@primary.com user2@additional.com}, other_property: :other_value
# role :db,  %w{deploy@example.com}



# Configuration
# =============
# You can set any configuration variable like in config/deploy.rb
# These variables are then only loaded and set in this stage.
# For available Capistrano configuration variables see the documentation page.
# http://capistranorb.com/documentation/getting-started/configuration/
# Feel free to add new variables to customise your setup.



# Custom SSH Options
# ==================
# You may pass any option but keep in mind that net/ssh understands a
# limited set of options, consult the Net::SSH documentation.
# http://net-ssh.github.io/net-ssh/classes/Net/SSH.html#method-c-start
#
# Global options
# --------------
#  set :ssh_options, {
#    keys: %w(/home/rlisowski/.ssh/id_rsa),
#    forward_agent: false,
#    auth_methods: %w(password)
#  }
#
# The server-based syntax can be used to override options:
# ------------------------------------
# server 'example.com',
#   user: 'user_name',
#   roles: %w{web app},
#   ssh_options: {
#     user: 'user_name', # overrides user setting above
#     keys: %w(/home/user_name/.ssh/id_rsa),
#     forward_agent: false,
#     auth_methods: %w(publickey password)
#     # password: 'please use keys'
#   }
