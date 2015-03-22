#!/usr/bin/env ruby
# -*- coding: utf-8 -*-
require File.expand_path(File.join(File.dirname(__FILE__), 'eventhandler'))
require File.expand_path(File.join(File.dirname(__FILE__), 'netio'))

class NetworkMonitor
  include NetworkIO

  def initialize(self_nodeinfo, ping_count = GlobalSettings::PING_COUNT, measure_interval = GlobalSettings::MEASURE_INTERVAL_SEC)
    @self_nodeinfo = self_nodeinfo
    @ping_count = ping_count
    @measure_interval = measure_interval
    @servers = []

    # 近隣のノードを格納
    @neighbors = []

    EventHandler.register(:add_neighbor) { |args|
      add_neighbor(*args)
    }
    EventHandler.register(:del_neighbor) { |args|
      del_neighbor(*args)
    }
  end

  def measure_latency(hostname)
    debug "measure_latency #{hostname}"
    ping_responses = `ping -c #{@ping_count} #{hostname} | grep icmp_seq | sed -e 's/^.*time=\\|\\s*ms//g'`.split("\n").map{|time| time.to_f}
    avg = 0.0
    ping_responses.each do |sec|
      avg += sec
    end
    avg /= ping_responses.size
    find_monitoring_server(hostname)[:latency] = avg

    #EventHandler.call(:update_status, @self_nodeinfo, hostname, :latency, avg)
    my_nodeinfo = NodeInfo.new(@self_nodeinfo)
    EventHandler.call(:update_status, @self_nodeinfo, hostname, :latency, avg)

    @neighbors.each do |remote_nodeinfo|
      remote_handler_call_oneshot(remote_nodeinfo, :update_status, @self_nodeinfo, hostname, :latency, avg) unless remote_nodeinfo == my_nodeinfo
    end

    avg
  end

  def measure_throughput(hostname, port)

    throughput = `iperf -c #{hostname} -p #{port} -n #{GlobalSettings::IPERF_TRANSMIT_SIZE_MB}M | grep -A 1 Transfer | tail -1 | grep -Eo '[0-9\\.]+\\s+Mbits/sec' | awk '{print $1}'`.to_f
    find_monitoring_server(hostname)[:throughput] = throughput

    my_nodeinfo = NodeInfo.new(@self_nodeinfo)
    EventHandler.call(:update_status, @self_nodeinfo, hostname, :throughput, throughput)

    @neighbors.each do |remote_nodeinfo|
      remote_handler_call_oneshot(remote_nodeinfo, :update_status, @self_nodeinfo, hostname, :throughput, throughput) unless remote_nodeinfo == my_nodeinfo
    end

    throughput
  end

  def monitoring?(hostname)
    not @servers.select{|srv| srv[:hostname] == hostname}.empty?
  end

  def find_monitoring_server(hostname)
    return if (not monitoring?(hostname))
    @servers.select{|srv| srv[:hostname] == hostname}.first
  end


  def add_neighbor(nodeinfo)
    info "adding a neighbor #{nodeinfo.id}"
    @neighbors << nodeinfo 
    start_server(nodeinfo)
  end

  def del_neighbor(nodeinfo)
    warn "deleting a neighbor #{nodeinfo.id}"
    @neighbors.delete_if{|node| node.id == nodeinfo.id}
    nodeinfo.ipaddresses.each do |ip|
      stop_server(ip)
    end
  end

  def start_server(nodeinfo)

    # net_a = nodeinfo.ipaddresses.map{|addr| addr.sub(/\.[0-9]+$/, '')}
    # net_b = @self_nodeinfo.ipaddresses.map{|addr| addr.sub(/\.[0-9]+$/, '')}
    # mutual_network = (net_a & net_b).first
    # hostname = nodeinfo.ipaddress.select{|addr| addr =~ /#{mutual_network}/}.first
    hostname = nodeinfo.faster_ipaddress
    return if monitoring?(hostname) # already monitoring
    return if @self_nodeinfo.top_node?

    warn "start monitoring #{hostname}"
    @servers << {
      :hostname => hostname,
      :latency => 0.0,
      :throughput => 0.0,
      :latency_thread => Thread.new(hostname) { |dest|
        loop do
          if `ip r | grep "#{dest} via"`.chomp.empty?
            measure_latency(dest)
          end
          sleep @measure_interval
        end
      },
      :throughput_thread => Thread.new(hostname) { |dest|
        loop do
          # warn "measure throughput!"
          # if `ip r | grep "#{dest} via"`.chomp.empty?
          #   warn "empty!"
          EventHandler.call(:refine_neighbors)
          #   #measure_throughput(dest, nodeinfo.iperf_port)
          # end
          sleep @measure_interval
        end
      }
    }
  end

  def stop_server(hostname)
    return if (not monitoring?(hostname)) # currently not monitoring
    target = @servers.select{ |srv| srv[:hostname] == hostname }.first
    target[:latency_thread].exit
    target[:throughput_thread].exit
    @servers.delete_if{|srv| srv[:hostname] == hostname}
  end


end

