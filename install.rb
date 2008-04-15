def copy(file_name, from_dir, to_dir)
  FileUtils.mkdir to_dir unless File.exist?(File.expand_path(to_dir))   
  from = File.expand_path(File.join(from_dir,file_name))
  to = File.expand_path(File.join(to_dir, file_name.gsub('.example', '')))
  FileUtils.cp from, to, :verbose => true unless File.exist?(to)
end

# copy example files to application directories
begin 
  copy_file 'Capfile.example', File.join(File.dirname(__FILE__), 'templates'), RAILS_ROOT
  copy_file 'deploy.rb.example', File.join(File.dirname(__FILE__), 'templates'), File.join(RAILS_ROOT, 'config')
rescue Exception => e
  puts "There are problems copying Boxcar configuration files to you app: #{e.message}"
end