#
# Cookbook Name:: chatsecure_web
# Recipe:: default
#
# Copyright 2013, Chris Ballinger
#
# Licensed under the AGPLv3
#

# Setup postgresql database
postgresql_database node['chatsecure_web']['db_name'] do
  connection ({
  		:host => "127.0.0.1", 
  		:port => node['chatsecure_web']['db_port'], 
  		:username => node['chatsecure_web']['db_user'], 
  		:password => node['postgresql']['password']['postgres']
  })
  action :create
end

# Setup virtualenvs

directory node['chatsecure_web']['virtualenvs_dir'] do
  owner node['chatsecure_web']['service_user']
  group node['chatsecure_web']['service_user_group']
  recursive true
  action :create
end

virtualenv_path = node['chatsecure_web']['virtualenvs_dir'] + node['chatsecure_web']['virtualenv_name']
python_virtualenv virtualenv_path do
  owner node['chatsecure_web']['service_user']   
  group node['chatsecure_web']['service_user_group']
  action :create
end

python_pip "uwsgi" do
  virtualenv virtualenv_path
end

execute "fix_virtualenv_permissions" do
  command "chmod -R 770 ."
  cwd virtualenv_path
end

owner = node['chatsecure_web']['service_user']
group = node['chatsecure_web']['service_user_group']
execute "fix_virtualenv_ownership" do
  command "chown -R #{owner}:#{group} ."
  cwd virtualenv_path
end

# Make uwsgi params file
cookbook_file "uwsgi_params" do
  path "/etc/nginx/uwsgi_params"
  owner node['nginx']['user']
  group node['nginx']['group']
  action :create
end


# Git stuff
# Make git checkout directories
directory node['chatsecure_web']['app_root'] do
  owner node['chatsecure_web']['git_user']
  group node['chatsecure_web']['service_user_group']
  recursive true
  action :create
end

directory node['chatsecure_web']['git_root'] do
  owner node['chatsecure_web']['git_user']
  group node['chatsecure_web']['service_user_group']
  recursive true
  action :create
end

ssh_known_hosts_entry 'github.com'

# Git checkout
git node['chatsecure_web']['git_root'] do
   repository node['chatsecure_web']['git_url'] 
   revision node['chatsecure_web']['git_rev']  
   action :sync
   user node['chatsecure_web']['git_user']
   group node['chatsecure_web']['service_user_group']
end

template node['chatsecure_web']['git_root'] + "/.git/hooks/post-receive" do
  source "post-receive.erb"
  owner node['chatsecure_web']['git_user']
  group node['chatsecure_web']['service_user_group']
  mode "770"
  variables({
    :app_root => node['chatsecure_web']['app_root'],
    :virtualenv_path => virtualenv_path
  })
end

# Git checkout
git node['chatsecure_web']['app_root'] do
  repository node['chatsecure_web']['git_root']
  revision node['chatsecure_web']['git_rev']  
  action :sync
  user node['chatsecure_web']['git_user']
  group node['chatsecure_web']['service_user_group']
end

execute "fix_app_permissions" do
  command "chmod -R 770 ."
  cwd node['chatsecure_web']['app_root']
end

owner = node['chatsecure_web']['service_user']
group = node['chatsecure_web']['service_user_group']
execute "fix_app_ownership" do
  command "chown -R #{owner}:#{group} ."
  cwd virtualenv_path
end

# Make the static file directories
containing_dir = node['chatsecure_web']['static_container_dir'] + node['chatsecure_web']['service_name']
static_root =  containing_dir + node['chatsecure_web']['static_dir_name']
media_root = containing_dir + node['chatsecure_web']['media_dir_name']

directory static_root do
  owner node['chatsecure_web']['service_user']
  group node['chatsecure_web']['service_user_group']
  recursive true
  action :create
end

directory media_root do
  owner node['chatsecure_web']['service_user']
  group node['chatsecure_web']['service_user_group']
  recursive true
  action :create
end

secrets = data_bag_item(node['chatsecure_web']['secret_databag_name'] , node['chatsecure_web']['secret_databag_item_name'])
django_secret_key = secrets['django_secret_key']
memcached_location = node['memcached']['listen'] + ":" + node['memcached']['port'].to_s
# Make local_settings.py 
app_name = node['chatsecure_web']['app_name']
template node['chatsecure_web']['app_root'] + "/#{app_name}/#{app_name}/local_settings.py" do
    source "local_settings.py.erb"
    owner node['chatsecure_web']['git_user']   
    group node['chatsecure_web']['service_user_group']   
    mode "770"
    variables({
      :django_secret_key => django_secret_key,
      :db_name => node['chatsecure_web']['db_name'],
      :db_user => node['chatsecure_web']['db_user'],
      :db_password => node['postgresql']['password']['postgres'],
      :db_host => node['chatsecure_web']['db_host'],
      :db_port => node['chatsecure_web']['db_port'],
      :chef_node_name => Chef::Config[:node_name],
      :static_root => static_root,
      :media_root => media_root,
      :memcached_location => memcached_location
    })
    action :create
end


# Make Nginx log dirs
directory node['chatsecure_web']['log_dir'] do
  owner node['nginx']['user']
  group node['nginx']['group']
  recursive true
  action :create
end

# Nginx config file
template node['nginx']['dir'] + "/sites-enabled/chatsecure_web.nginx" do
    source "chatsecure_web.nginx.erb"
    owner node['nginx']['user']
    group node['nginx']['group']
    variables({
    :http_listen_port => node['chatsecure_web']['http_listen_port'],
    :https_listen_port => node['chatsecure_web']['https_listen_port'],
    :domain => Chef::Config[:node_name],
    :internal_port => node['chatsecure_web']['internal_port'],
    :ssl_cert => node['chatsecure_ssl']['ssl_dir'] + node['chatsecure_ssl']['ssl_cert'],
    :ssl_key => node['chatsecure_ssl']['ssl_dir'] + node['chatsecure_ssl']['ssl_key'],
    :app_root => node['chatsecure_web']['app_root'],
    :access_log => node['chatsecure_web']['log_dir'] + node['chatsecure_web']['access_log'],
    :error_log => node['chatsecure_web']['log_dir'] + node['chatsecure_web']['error_log'],
    :static_root => static_root,
    :media_root => media_root
    })
    notifies :restart, "service[nginx]"
    action :create
end

log_path = node['chatsecure_web']['log_dir'] + node['chatsecure_web']['service_log']
# Upstart service config file
template "/etc/init/" + node['chatsecure_web']['service_name'] + ".conf" do
    source "upstart.conf.erb"
    owner 'root' 
    group 'root'
    variables({
    :service_user => node['chatsecure_web']['service_user'],
    :virtualenv_path => virtualenv_path,
    :app_root => node['chatsecure_web']['app_root'],
    :app_name => node['chatsecure_web']['app_name'],
    :log_path => log_path,
    :app_port => node['chatsecure_web']['internal_port'],
    :app_workers => node['chatsecure_web']['app_workers'],
    :max_requests => node['chatsecure_web']['max_requests'],
    :harakiri => node['chatsecure_web']['harakiri'],
    :service_user_id => node['chatsecure_web']['service_user_id'],
    :service_user_gid => node['chatsecure_web']['service_user_gid'],
    :service_name => node['chatsecure_web']['service_name']
    })
end

# Make service log file
file log_path do
  owner node['chatsecure_web']['service_user']
  group node['chatsecure_web']['service_user_group'] 
  action :create_if_missing # see actions section below
end

# Register capture app as a service
service node['chatsecure_web']['service_name'] do
  provider Chef::Provider::Service::Upstart
  action :enable
end
