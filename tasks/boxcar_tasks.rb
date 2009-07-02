require 'highline/import'

# We'll handle our own printing of default options. Necessary to have
# "nice" output using indentstring
class HighLine::Question
  private
  def append_default()
  end
end

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

DBNAME    = {:postgresql => "PostgreSQL", :mysql => "MySQL"}
GEMNAME   = {:postgresql => "pg", :mysql => "mysql"}
BINDBNAME = {:postgresql => "psql", :mysql => "mysql"}
INSTALLDB = {:postgresql => "postgresql libpq-dev", :mysql => "mysql-server mysql-client libmysqlclient15-dev"}
HTTPDNAME = {:nginx => "Nginx", :apache => "Apache"}
HTTPDSERV = {:nginx => "nginx", :apache => "apache2"}
HTTPDEXEC = {:nginx => "/usr/bin/nginx", :apache => "/usr/sbin/apache2"}

REEDIR = "/usr/local/lib/ruby-enterprise-current"

role :web, boxcar_server
role :app, boxcar_server
role :db, boxcar_server, :primary => true
role :admin_web, "root@#{boxcar_server}", :no_release => true

# What database server are you using?
# Example:
set :database_name, { :development  => "#{application_name}_development",
                      :test         => "#{application_name}_test",
                      :production   => "#{application_name}_production" }

# user
set :user, boxcar_username
set :use_sudo, false

set :domain_names, Proc.new { HighLine.ask(indentstring("What is the primary domain name? |railsboxcar.com|")) { |q| q.default = "railsboxcar.com" } }

set :db_development,database_name[:development]
set :db_test, database_name[:test]
set :db_production, database_name[:production]

# Prompt user to set database user/pass
set :database_username, Proc.new {
  if setyp_type.to_s == "quick"
    "#{user}"
  else
    HighLine.ask(indentstring("What is the database username? |#{user}|")) { |q| q.default = user }
  end
}
set :database_host, Proc.new {
  if setup_type.to_s == "quick"
    "localhost"
  else
    HighLine.ask(indentstring("What host is your database running on? |localhost|")) { |q| q.default = "localhost" }
  end
}
set :database_adapter, Proc.new {
  # currently, this prompt constitutes the longest prompt. Be sure to update indentstring if
  # any changes are made here
  choose do |menu|
    menu.layout = :one_line
    menu.prompt = "What database server will you be using?  "
    menu.choices(:postgresql, :mysql)
  end
}
set :database_password, Proc.new {
  if setup_type.to_s == "quick"
    dbpass = newpass(16)
    print indentstring("Creating random database password:")
    puts "#{dbpass}"
    dbpass
  else
    database_first = "" # Keeping asking for the password until they get it right twice in a row.
    loop do
      database_first = HighLine.ask(indentstring("Please enter your database user's password:")) { |q| q.echo = "." }
      database_confirm = HighLine.ask(indentstring("Please retype the password to confirm:")) { |q| q.echo = "." }
      break if database_first == database_confirm
    end
    database_first
  end
}

set :database_socket, Proc.new {
  if setup_type.to_s == "quick"
    "/var/run/mysqld/mysqld.sock"
  else
    HighLine.ask(indentstring("Where is the MySQL socket file? |/var/run/mysqld/mysqld.sock|")) { |q| q.default = "/var/run/mysqld/mysqld.sock" }
  end
}

set :database_port, Proc.new {
  if database_adapter.to_s == "postgresql"
    default = "5432"
  else
    default = "3306"
  end
  if setup_type.to_s == "quick"
    default
  else
    HighLine.ask(indentstring("What port does your database run on? |#{default}|")) { |q| q.default=default }
  end
}

# server type
set :server_type, Proc.new {
  if setup_type.to_s == "quick"
    :nginx
  else
    # indenting this prompt by hand for now. Can't figure out how to work in indentstring
    choose do |menu|
      menu.layout = :one_line
      menu.prompt = "         What web server will you be using?  "
      menu.choices(:nginx, :apache)
    end
  end
}

# directories
set :home, "/home/#{user}"
set :log, "#{home}/log"
set :deploy_to, "#{home}/sites/#{application_name}"

set :app_shared_dir, "#{deploy_to}/shared"

# what type of setup does the user want?
set :setup_type, Proc.new {
  # another manual indent
  choose do |menu|
    menu.layout = :one_line
    menu.prompt = "         What type of setup would you like?  "
    menu.choices(:quick, :custom)
  end
}

set :boxcar_conductor_templates, 'vendor/plugins/boxcar-conductor/templates'

set :today, Time.now.strftime('%b %d, %Y').to_s

namespace :boxcar do
  desc 'Configure your Boxcar environment'
  task :config,  :roles => :admin_web do
    puts ""
    setup_type
    setup.configdb
    puts "\n\nBeginning remote setup. This process will install and configure the"
    puts "database server and Phusion Passenger modules for your Boxcar. Some"
    puts "of these steps can take a couple of minutes, so relax, get a cup of"
    puts "coffee and then come back.\n\n"
    setup.installdbms
    setup.installgems
    setup.passenger
    puts ""
    if HighLine.agree(indentstring("Setup is complete. Ready to deploy? [y/n]"))
      puts "--------------------cap deploy:cold--------------------"
      if system("cap deploy:cold")
        puts "--------------------cap deploy:cold--------------------"
        setup.startweb
      else
        puts "Errors encountered during the deploy:cold. Please fix them and then try"
        puts "running this task again."
      end
    end
  end
  before "boxcar:config", "boxcar:setup:createuser", "deploy:setup"

  task :testing, :except => { :no_release => true } do
    HighLine.agree(indentstring("Setup is complete. Ready to deploy? [y/n]"))
  end

  namespace :setup do
    desc 'Create deployment user'
    task :createuser, :roles => :admin_web do
      print indentstring("Creating user #{user}:")
      if capture("if [ -d /home/#{user} ]; then echo true; else echo false; fi").chomp.eql?("false")
        run "adduser --gecos '' --disabled-password #{user}"
        puts "#{user} created"
        if capture("if [ -f /home/#{user}/.ssh/authorized_keys ]; then echo true; else echo false; fi").chomp.eql?("false")
          user_password = "" # Keeping asking for the password until they get it right twice in a row.
          loop do
            user_password = HighLine.ask(indentstring("Please enter a password for #{user}:")) { |q| q.echo = "." }
            password_confirm = HighLine.ask(indentstring("Please retype the password to confirm:")) { |q| q.echo = "." }
            break if user_password == password_confirm
          end
          run "echo '#{user}:#{user_password} | chpasswd -m"
        else
          puts indentstring("using root's public key", :end)
        end
      else
        puts "#{user} already exists"
      end
    end

    desc 'Install and configure databases'
    task :installdbms, :roles => :admin_web do
      installdb  = "aptitude -y -q install #{INSTALLDB[database_adapter]} > /dev/null"

      print indentstring("Installing and configuring #{DBNAME[database_adapter]}:")

      begin
        run "! which #{BINDBNAME[database_adapter]} >/dev/null"

        run installdb, :pty => true
        puts "#{DBNAME[database_adapter]} installed"
      rescue Capistrano::CommandError => e
        puts "#{DBNAME[database_adapter]} already installed, skipping."
      end
    end
    after "boxcar:setup:installdbms", "boxcar:setup:createdb"

    desc 'Create application database and user'
    task :createdb, :roles => :admin_web do
      if database_adapter.to_s == "postgresql"
        psqlconfig = "CREATE ROLE #{database_username} PASSWORD '#{database_password}' NOSUPERUSER NOCREATEDB NOCREATEROLE INHERIT LOGIN; CREATE DATABASE #{db_production} OWNER #{database_username};"
        put psqlconfig, "/tmp/setupdb.sql"
        run "psql < /tmp/setupdb.sql", :shell => 'su postgres'
      elsif database_adapter.to_s == "mysql"
        mysqlconfig = "CREATE DATABASE #{db_production}; GRANT ALL PRIVILEGES ON #{db_production}.* TO #{database_username} IDENTIFIED BY '#{database_password}'"
        put mysqlconfig, "/tmp/setupdb.sql"
        run "mysql < /tmp/setupdb.sql"
      end
      run "rm -f /tmp/setupdb.sql"
      puts indentstring("database configured", :end)
    end

    desc 'Set up Phusion Passenger for the selected web server'
    task :passenger, :roles => :admin_web do
      print indentstring("Installing #{HTTPDNAME[server_type]} Passenger modules:")
      begin
        run "test -h #{REEDIR}/lib/ruby/gems/1.8/gems/passenger-current"
      rescue Capistrano::CommandError => e
        puts "failed"
        puts '\n\nPassenger & Ruby Enterprise Edition do not appear to be installed correctly. Please'
        puts 'contact support for further assistance. Aborting.\n\n'
        abort
      end
      begin
        if server_type == :nginx
          other_server = :apache
          run "if [ ! -f #{REEDIR}/lib/ruby/gems/1.8/gems/passenger-current/ext/nginx/HelperServer ]; then #{REEDIR}/bin/passenger-install-nginx-module --auto --prefix=/usr/local/lib/nginx --auto-download > /dev/null 2>&1 && rm -rf /usr/local/lib/nginx; fi"
        elsif server_type == :apache
          other_server = :nginx
          run "if [ ! -f #{REEDIR}/lib/ruby/gems/1.8/gems/passenger-current/ext/apache2/mod_passenger.so ]; then #{REEDIR}/bin/passenger-install-apache2-module --auto >/dev/null 2>&1; fi"
        end
        puts "#{HTTPDNAME[server_type]} module installed"
        run "sysv-rc-conf #{HTTPDSERV[server_type]} on && sysv-rc-conf #{HTTPDSERV[other_server]} off"
        puts indentstring("#{HTTPDNAME[server_type]} startup enabled", :end)
        run "if pidof #{HTTPDEXEC[other_server]} >/dev/null; then /usr/sbin/invoke-rc.d #{HTTPDSERV[other_server]} stop && /usr/sbin/invoke-rc.d #{HTTPDSERV[server_type]} start"
        puts indentstring("#{HTTPDNAME[other_server]} disabled")
      rescue Capistrano::CommandError => e
        puts "\n\nAn unhandled error occured while attempting to install Passenger. Aborting.\n\n"
        abort
      end
    end

    desc "Install necessary gems on Boxcar"
    task :installgems, :roles => :admin_web do
      if File.exists?("config/environment.rb") && ! File.open("config/environment.rb").grep(/RAILS_GEM_VERSION/).first.nil?
        eval(File.open("config/environment.rb").grep(/RAILS_GEM_VERSION/).first)
      else
        RAILS_GEM_VERSION='2.3.2' # this should always be set to the most recent version installed on the Boxcar
      end
      installcmd="#{REEDIR}/bin/gem install --no-rdoc --no-ri -q "
      checkcmd="#{REEDIR}/bin/gem list -i "
      print indentstring("Installing gems:")
      begin
        run(checkcmd + "-v=#{RAILS_GEM_VERSION} rails")
        puts "rails #{RAILS_GEM_VERSION} already installed"
      rescue
        run(installcmd + "-v=#{RAILS_GEM_VERSION} rails")
        puts "rails #{RAILS_GEM_VERSION} installed"
      end
      begin
        capture(checkcmd + "#{GEMNAME[database_adapter]}")
        puts indentstring("#{GEMNAME[database_adapter]} already installed", :end)
      rescue
        run(installcmd + "#{GEMNAME[database_adapter]}")
        puts indentstring("#{GEMNAME[database_adapter]} installed", :end)
      end
    end

    desc "Create remote directory structure"
    task :createdirs, :except => { :no_release => true } do
      run "mkdir -p #{home}/log #{home}/sites"
      run "mkdir -p #{app_shared_dir}/config #{app_shared_dir}/log"
    end

    desc "Configure your Boxcar database"
    task :configdb, :except => { :no_release => true } do
      database_configuration = render_erb_template("#{boxcar_conductor_templates}/databases/#{database_adapter}.yml.erb")
      put database_configuration, "#{app_shared_dir}/config/database.yml"
    end
    before "boxcar:setup:configdb", "boxcar:setup:createdirs"

    task :startweb, :roles => :admin_web do
      print indentstring("Activating #{HTTPDNAME[server_type]}:")
      begin
        run "/usr/local/bin/activate-server -a #{user} #{application_name} > /dev/null 2>&1"
        puts "success!"
        print indentstring("Your application should now be available at:")
        puts "http://#{boxcar_server}\n"
      rescue
        puts "failed!"
        puts "\nPlease log into your Boxcar as root and run 'activate-server' to"
        puts "get more detailed failure information.\n"
      end
    end
  end

  namespace :deploy do
    desc "Link in the production database.yml"
    task :link_files, :except => { :no_release => true } do
      run "ln -nfs #{app_shared_dir}/config/database.yml #{release_path}/config/database.yml"
      run "ln -nfs #{app_shared_dir}/log #{release_path}/log"
    end
  end

  after "deploy:update_code", "boxcar:deploy:link_files"

end

def indentstring(inputstring, placement = :begin)
  #the size of the print "buffer". This should be >= the length of the longest string to be printed
  printgap = "                                                              "
  if placement == :begin
    pgsize = printgap.length - 1
    strsize = inputstring.length - 1
    printgap[pgsize - strsize, pgsize] = inputstring
    inputstring = printgap + "  "
  elsif placement == :end
    inputstring = printgap + "  " + inputstring
  end
end

def newpass(len)
  chars = ("a".."z").to_a + ("A".."Z").to_a + ("0".."9").to_a
  return Array.new(len){||chars[rand(chars.size)]}.join
end
