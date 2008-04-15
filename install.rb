def copy(file_name, from_dir, to_dir)
  FileUtils.mkdir to_dir unless File.exist?(File.expand_path(to_dir))   
  from = File.expand_path(File.join(from_dir,file_name))
  to = File.expand_path(File.join(to_dir, file_name.gsub('.example', '')))
  FileUtils.cp from, to, :verbose => true unless File.exist?(to)
end

def copy_file(file_name)
  templates = File.join(File.dirname(__FILE__), 'templates')
  config_dir = File.join(RAILS_ROOT, 'config')
  copy file_name, templates, config_dir 
end

# copy static assets
begin 
  copy_file 'Capfile.example'
  copy_file 'deploy.rb.example'  
rescue Exception => e
  puts "There are problems copying Boxcar configuration files to you app: #{e.message}"
end