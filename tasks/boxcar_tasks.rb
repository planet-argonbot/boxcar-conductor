require 'highline/import'

class Capistrano::Configuration
  ##
  # Read a file and evaluate it as an ERB template.
  # Path is relative to this file's directory.

  def render_erb_template(filename)
    template = File.read(filename)
    result   = ERB.new(template).result(binding)
  end
    
end

######################################################################## 
# Advanced Configuration
# Only the courageous of ninjas dare pass this! 
######################################################################## 

role :web, boxcar_server
role :app, boxcar_server
role :db, boxcar_server, :primary => true

# What database server are you using?
# Example:
set :database_name, { :development  => "#{application_name}_development",
                      :test         => '#{application_name}_test',
                      :production   => '#{application_name}_production' }
                      
# user
set :user, boxcar_username
set :use_sudo, false

set :domain_names, Proc.new { HighLine.ask("What is the primary domain name?") { |q| q.default = "railsboxcar.com" } }

# subversion / SCM
# Ask the user for their subversion password
# set :svn_password, Proc.new { HighLine.ask("What is your subversion password for #{svn_username}: ") { |q| q.echo = "x" } }
# set :repository, Proc.new { "--username #{svn_username} " + "--password #{svn_password} " + "#{svn_repository_url}" }
# set :checkout,   'export'

set :db_development,database_name[:development]
set :db_test, database_name[:test]
set :db_production, database_name[:production]

# Prompt user to set database user/pass
set :database_username, Proc.new { HighLine.ask("What is your database username?  ") { |q| q.default = "dbuser" } }
set :database_host, Proc.new { HighLine.ask("What host is your database running on?  ") { |q| q.default = "localhost" } }
set :database_adapter, Proc.new { 
  choose do |menu|
    menu.prompt = "What database server will you be using?"
    menu.choices(:postgresql, :mysql) 
  end
}
set :database_password, Proc.new { HighLine.ask("What is your database user's password?  ") { |q| q.echo = "x" } }
set :database_socket, Proc.new { HighLine.ask("Where is the MySQL socket file?  ") { |q| q.default = "/var/run/mysqld/mysqld.sock" } }
set :database_port, Proc.new { 
  HighLine.ask("What port does your database run on?  ") do |q| 
    if database_adapter.to_s == "postgresql"
      q.default = "5432" 
    else
      q.default = "3306" 
    end
  end
}

# directories
set :home, "/home/#{user}"
set :etc, "#{home}/etc"
set :log, "#{home}/log"
set :deploy_to, "#{home}/sites/#{application_name}"

set :shared_dir, "#{deploy_to}/shared"


# mongrel
# What port number should your mongrel cluster start on?
set :mongrel_port, Proc.new { HighLine.ask("What port will your mongrel cluster start with?  ") { |q| q.default = "8000" } }

# How many instances of mongrel should be in your cluster?
set :mongrel_servers, Proc.new { 
 choose do |menu|
    menu.prompt = "How many mongrel servers should run?"
    menu.choices(1,2,3)
  end
}

set :mongrel_conf, "#{etc}/mongrel_cluster.#{application_name}.conf" 
set :mongrel_pid, "#{log}/mongrel_cluster.#{application_name}.pid" 
set :mongrel_address, '127.0.0.1'
set :mongrel_environment, :production        

set :boxcar_conductor_templates, 'vendor/plugins/boxcar-conductor/templates'
 
set :today, Time.now.strftime('%b %d, %Y').to_s
 
namespace :boxcar do
  
  desc 'Configure your Boxcar environment'
  task :setup do
    deploy.setup    
    run "mkdir -p /home/#{boxcar_username}/etc /home/#{boxcar_username}/log /home/#{boxcar_username}/sites"
    database.configure
    mongrel.cluster.generate
  end

  namespace :deploy do 
    desc "Link in the production database.yml" 
    task :link_files do
      run "ln -nfs #{shared_dir}/config/database.yml #{release_path}/config/database.yml"
      run "ln -nfs #{shared_dir}/log #{release_path}/log"
    end    
  end
  
  namespace :database do
    desc "Configure your Boxcar database"
    task :configure do
      database_configuration = render_erb_template("#{boxcar_conductor_templates}/databases/#{database_adapter}.yml.erb")      
      put database_configuration, "#{shared_dir}/config/database.yml"
    end
  end
  
  namespace :mongrel do
    namespace :cluster do
      desc "Generate mongrel cluster configuration" 
      task :generate do
        run "mkdir -p #{shared_dir}/config" 
        mongrel_cluster_configuration = render_erb_template("#{boxcar_conductor_templates}/mongrel_cluster.yml.erb")
        put mongrel_cluster_configuration, mongrel_conf  
      end
      
    end
  end

 after "deploy:update_code", "boxcar:deploy:link_files"
 
end

