#
# Cookbook Name:: app_rails
#
# Copyright RightScale, Inc. All rights reserved.  All access and use subject to the
# RightScale Terms of Service available at http://www.rightscale.com/terms.php and,
# if applicable, other agreements such as a RightScale Master Subscription Agreement.

rs_utils_marker :begin

include_recipe "web_apache"
include_recipe "rails"
include_recipe "passenger_apache2::mod_rails"
include_recipe "mysql::client"

# install optional gems required for the application
node[:rails][:gems_list].each { |gem| gem_package gem } unless "#{node[:rails][:gems_list]}" == ""

# grab application source from remote repository
include_recipe "app_rails::do_update_code"

# reconfigure existing database.yml, or create from scratch
include_recipe "app_rails::setup_db_config"

# this should work but chef breaks -- https://tickets.opscode.com/browse/CHEF-205
 #directory node[:rails][:code][:destination] do
   #owner 'www-data'
   #group 'www-data'
   #mode 0755
   #recursive true
 #end

#we'll just do this for now...

#chown application directory 
bash "chown_home" do
  code <<-EOH
    echo "chown -R #{node[:rails][:app_user]}:#{node[:rails][:app_user]} #{node[:rails][:code][:destination]}" >> /tmp/bash
    chown -R #{node[:rails][:app_user]}:#{node[:rails][:app_user]} #{node[:rails][:code][:destination]}
  EOH
end

passenger_port = node[:rails][:application_port]

# if port 80, disable default vhost
if passenger_port == "80" 
  apache_site "000-default" do
    enable false
  end
end

ports = node[:apache][:listen_ports].include?(passenger_port) \
    ? node[:apache][:listen_ports] \
    : [node[:apache][:listen_ports], passenger_port].flatten

template "#{node[:apache][:dir]}/ports.conf" do
  cookbook "apache2"
  source "ports.conf.erb"
  variables :apache_listen_ports => ports
  notifies :restart, resources(:service => "apache2")
end

# setup the passenger vhost
web_app node[:rails][:application_name] do
  template "passenger_web_app.conf.erb"
  docroot node[:rails][:code][:destination]
  vhost_port node[:rails][:application_port]
  server_name node[:rails][:server_name]
  rails_env node[:rails][:env]
end

# Move rails logs to /mnt  (TODO:create move definition in rs_tools?)
rails_log = '/mnt/log/rails'
ruby 'move_rails_log' do
  not_if do File.symlink?('/var/log/rails') end
  code <<-EOH
    `rm -rf /var/log/rails`
    `mkdir -p #{rails_log}`
    `ln -s #{rails_log} /var/log/rails`
  EOH
end

# configure logrotate for rails (TODO: create logrotate definition)
template "/etc/logrotate.d/rails" do
  source "logrotate.conf.erb"
  variables(
      :app_name => "rails"
   )    
end

rs_utils_marker :end
