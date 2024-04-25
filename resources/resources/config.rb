# Cookbook Name:: rb-exporter
#
# Resource:: config
#

actions :add, :remove
default_action :add

attribute :user, :kind_of => String, :default => "rb-exporter"
attribute :config_dir, :kind_of => String, :default => "/etc/rb-exporter"
