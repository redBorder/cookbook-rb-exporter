# Cookbook:: rb-exporter
# Provider:: config

action :add do
  begin
    user = new_resource.user
    split_traffic_logstash = new_resource.split_traffic_logstash
    config_dir = new_resource.config_dir
    arp_ifaces = []

    dnf_package 'rb-exporter' do
      action :upgrade
      flush_cache[:before]
    end

    execute 'create_user' do
      command "/usr/sbin/useradd -r #{user}"
      ignore_failure true
      not_if "getent passwd #{user}"
    end

    directory config_dir do
      action :create
    end

    template '/etc/rsyslog.d/arp.conf' do
      source 'rsyslog_arp_conf.erb'
      owner 'root'
      group 'root'
      cookbook 'rb-exporter'
      mode '0644'
      retries 2
      notifies :restart, 'service[rsyslog]', :delayed
    end

    if node['interfaces'] && !node['interfaces'].empty?
      node['interfaces'].each do |iface_key, _orig_iface|
        iface = node['interfaces'][iface_key].to_hash.clone

        arp_ifaces.push(iface_key) if iface['arp'] == 'true'

        ['rb-exporter'].each do |s|
          %w(restart stop start).each do |s_action|
            execute "#{s_action}_#{s}_#{iface_key}" do
              command "/bin/env WAIT=1 /etc/init.d/#{s} #{s_action} #{iface_key}"
              ignore_failure false
              action :nothing
            end
          end
        end

        if !iface['dstAddress'].empty?

          execute "iface_restart_#{iface_key}" do
            command "ifconfig #{iface_key} down && ifconfig #{iface_key} up"
            ignore_failure false
            action :nothing
          end

          template "/etc/sysconfig/network-scripts/ifcfg-#{iface_key}" do
            source 'ifcfg.erb'
            owner 'root'
            group 'root'
            cookbook 'rb-exporter'
            mode '0644'
            retries 2
            variables(iface: iface_key, iface_type: iface['iface_type'], iface_ip: iface['iface_ip'], iface_netmask: iface['iface_netmask'], iface_gateway: iface['iface_gateway'])
            notifies :run, "execute[iface_restart_#{iface_key}]", :immediately if iface_key != 'eth0'
          end

          template "/etc/logrotate.d/rb-exporter-#{iface_key}" do
            source 'rb-exporter_log-rotate.erb'
            owner 'root'
            group 'root'
            cookbook 'rb-exporter'
            mode '0644'
            retries 2
            variables(iface: iface_key)
          end

          directory "/var/log/rb-exporter/#{iface_key}" do
            owner 'root'
            group 'root'
            mode '0755'
            recursive true
            action :create
          end

          directory "/etc/rb-exporter/#{iface_key}" do
            owner 'root'
            group 'root'
            mode '0755'
            recursive true
            action :create
          end

          # Calculate observation_id
          observation_id = (iface['observationId'] && !iface['observationId'].empty?) ? iface['observationId'] : nil
          observation_id = 4294967295 if observation_id.nil? && iface['protocol_type'].downcase.include?('sflow')
          observation_id_filters = iface['observation_id_filters'] || {}

          template "/etc/rb-exporter/#{iface_key}/rb-exporter.conf" do
            source 'rb-exporter_conf.erb'
            owner 'root'
            group 'root'
            cookbook 'rb-exporter'
            mode '0644'
            retries 2
            variables(dstAddress: iface['dstAddress'], type: iface['protocol_type'], ipAddress: node['ipaddress'], iface: iface_key, observation_id: observation_id, observation_id_filters: observation_id_filters, sampling_rate: iface['sampling_rate'])
            notifies :run, "execute[restart_rb-exporter_#{iface_key}]", :delayed
          end

          template "/etc/rb-exporter/#{iface_key}/pretag.map" do
            source 'rb-exporter_pretag_map.erb'
            owner 'root'
            group 'root'
            cookbook 'rb-exporter'
            mode '0644'
            retries 2
            variables(observation_id: observation_id, observation_id_filters: observation_id_filters, split_traffic_logstash: split_traffic_logstash)
            notifies :run, "execute[restart_rb-exporter_#{iface_key}]", :delayed
          end
        else
          directory "/opt/rb/etc/rb-exporter/#{iface_key}" do
            recursive true
            action :delete
            only_if { ::Dir.exist?("/opt/rb/etc/rb-exporter/#{iface_key}") }
            notifies :run, "execute[stop_rb-exporter_#{iface_key}]", :immediately
          end

          file "/etc/logrotate.d/rb-exporter-#{iface_key}" do
            action :delete
            only_if { ::File.exist?("/etc/logrotate.d/rb-exporter-#{iface_key}") }
          end
        end
      end
    end

    template '/etc/sysconfig/arpwatch' do
      source 'arpwatch.erb'
      owner 'root'
      group 'root'
      cookbook 'rb-exporter'
      mode '0644'
      retries 2
      variables(arp_ifaces: arp_ifaces)
      notifies :restart, 'service[arpwatch]', :delayed
    end

    service 'rsyslog' do
      service_name 'rsyslog'
      supports status: true, reload: true, restart: true, start: true, enable: true
      action [:enable, :start]
      ignore_failure true
      action([:start, :enable])
    end

    service 'arpwatch' do
      service_name 'arpwatch'
      supports status: true, reload: true, restart: true, start: true, enable: true
      ignore_failure true
      action([:start, :enable])
    end

    service 'rb-exporter' do
      service_name 'rb-exporter'
      supports status: true, reload: true, restart: true, start: true, enable: true
      ignore_failure true
      action([:start, :enable, :restart])
    end

    Chef::Log.info('rb-exporter cookbook has been processed')
  rescue => e
    Chef::Log.error(e.message)
  end
end

action :remove do
  begin
    Chef::Log.info('rb-exporter cookbook has been processed')
  rescue => e
    Chef::Log.error(e.message)
  end
end
