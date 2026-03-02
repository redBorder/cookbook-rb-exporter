# Cookbook:: rb-exporter
# Provider:: config

action :add do
  begin
    user                    = new_resource.user
    split_traffic_logstash  = new_resource.split_traffic_logstash
    config_dir              = new_resource.config_dir
    arp_ifaces              = []

    dnf_package 'rb-exporter' do
      action :install
    end

    service 'rb-exporter-legacy-stop' do
      service_name 'rb-exporter'
      action :stop
      ignore_failure true
      only_if { ::File.exist?('/etc/init.d/rb-exporter') }
    end

    file '/etc/init.d/rb-exporter' do
      action :delete
      only_if { ::File.exist?('/etc/init.d/rb-exporter') }
    end

    execute 'create_user' do
      command "/usr/sbin/useradd -r #{user}"
      ignore_failure true
      not_if "getent passwd #{user}"
    end

    directory config_dir do
      recursive true
      action :create
    end

    template '/etc/rsyslog.d/arp.conf' do
      source 'rsyslog_arp_conf.erb'
      owner 'root'
      group 'root'
      mode '0644'
      retries 2
      notifies :restart, 'service[rsyslog]', :delayed
    end

    interfaces = node['redborder']['interfaces'] || {}

    interfaces.each do |iface_key, iface_raw|
      iface = iface_raw.to_hash.clone

      arp_ifaces << iface_key if iface['arp'] == 'true'

      if iface['dstAddress'].to_s.empty?

        directory "/etc/rb-exporter/#{iface_key}" do
          recursive true
          action :delete
          only_if { ::Dir.exist?("/etc/rb-exporter/#{iface_key}") }
        end

        file "/etc/logrotate.d/rb-exporter-#{iface_key}" do
          action :delete
          only_if { ::File.exist?("/etc/logrotate.d/rb-exporter-#{iface_key}") }
        end

        next
      end

      execute "iface_restart_#{iface_key}" do
        command "ifconfig #{iface_key} down && ifconfig #{iface_key} up"
        action :nothing
      end

      template "/etc/sysconfig/network-scripts/ifcfg-#{iface_key}" do
        source 'ifcfg.erb'
        owner 'root'
        group 'root'
        mode '0644'
        retries 2
        variables(
          iface: iface_key,
          iface_type: iface['iface_type'],
          iface_ip: iface['iface_ip'],
          iface_netmask: iface['iface_netmask'],
          iface_gateway: iface['iface_gateway']
        )
        notifies :run, "execute[iface_restart_#{iface_key}]", :immediately if iface_key != 'eth0'
      end

      template "/etc/logrotate.d/rb-exporter-#{iface_key}" do
        source 'rb-exporter_log-rotate.erb'
        owner 'root'
        group 'root'
        mode '0644'
        retries 2
        variables(iface: iface_key)
      end

      directory "/var/log/rb-exporter/#{iface_key}" do
        owner 'root'
        group 'root'
        mode '0755'
        recursive true
      end

      directory "/etc/rb-exporter/#{iface_key}" do
        owner 'root'
        group 'root'
        mode '0755'
        recursive true
      end

      observation_id =
        if iface['observationId'] && !iface['observationId'].empty?
          iface['observationId']
        elsif iface['protocol_type'].to_s.downcase.include?('sflow')
          4294967295
        end

      observation_id_filters = iface['observation_id_filters'] || {}

      template "/etc/rb-exporter/#{iface_key}/rb-exporter.conf" do
        source 'rb-exporter_conf.erb'
        owner 'root'
        group 'root'
        mode '0644'
        retries 2
        variables(
          dstAddress: iface['dstAddress'],
          type: iface['protocol_type'],
          ipAddress: node['ipaddress'],
          iface: iface_key,
          observation_id: observation_id,
          observation_id_filters: observation_id_filters,
          sampling_rate: iface['sampling_rate']
        )
        notifies :restart, "service[rb-exporter@#{iface_key}]", :delayed
      end

      template "/etc/rb-exporter/#{iface_key}/pretag.map" do
        source 'rb-exporter_pretag_map.erb'
        owner 'root'
        group 'root'
        mode '0644'
        retries 2
        variables(
          observation_id: observation_id,
          observation_id_filters: observation_id_filters,
          split_traffic_logstash: split_traffic_logstash
        )
        notifies :restart, "service[rb-exporter@#{iface_key}]", :delayed
      end

      service "rb-exporter@#{iface_key}" do
        action :nothing
        supports restart: true, status: true
      end
    end

    active_ifaces = []

    interfaces.each do |iface_key, iface|
      next if iface['dstAddress'].to_s.empty?

      active_ifaces << iface_key

      service "rb-exporter@#{iface_key}" do
        action [:enable, :start]
      end
    end

    if ::Dir.exist?('/etc/rb-exporter')
      Dir.glob('/etc/rb-exporter/*').each do |dir|
        iface = File.basename(dir)
        next if active_ifaces.include?(iface)

        service "rb-exporter@#{iface}" do
          action [:stop, :disable]
          ignore_failure true
        end
      end
    end

    template '/etc/sysconfig/arpwatch' do
      source 'arpwatch.erb'
      owner 'root'
      group 'root'
      mode '0644'
      retries 2
      variables(arp_ifaces: arp_ifaces)
      notifies :restart, 'service[arpwatch]', :delayed
    end

    service 'rsyslog' do
      supports status: true, reload: true, restart: true
      action [:enable, :start]
    end

    service 'arpwatch' do
      supports status: true, reload: true, restart: true
      action [:enable, :start]
    end

    Chef::Log.info('rb-exporter cookbook has been processed')

  rescue => e
    Chef::Log.error(e.message)
    raise
  end
end

action :remove do
  Chef::Log.info('rb-exporter remove action executed')
end