# -*- coding: utf-8 -*-

require File.expand_path(File.join(File.dirname(__FILE__), 'config'))


class NodeInfo

  attr_accessor :ipaddresses, :port, :iperf_port, :id, :throughput_to_top, :downstream_nodes, :upstream_node, :neighbor_nodes, :faster_ipaddress

  def initialize(my_ipaddresses, top_ipaddress, communication_port = GlobalSettings::EVENT_SERVER_PORT, iperf_port = GlobalSettings::IPERF_SERVER_PORT)
    # 自ノードのIPアドレスのリスト
    @ipaddresses = my_ipaddresses
    @faster_ipaddress = @ipaddresses.first
    # EventServerの待ち受けポート
    @port = communication_port
    # iperfサーバの待ち受けポート
    @iperf_port = iperf_port
    # ノードの識別子
    @id = gen_node_id
    # 上位ノード
    @upstream_node = nil
    # 最上位ノード
    @top_ipaddress = top_ipaddress
    # 最上位ノードまでのスループット
    @throughput_to_top = top_node? ? 1000.0 : 0.0
  end
  
  def top_node?
    # 自分のIPアドレスと最上位のIPアドレスを比べる
    not (@ipaddresses & [@top_ipaddress]).empty?
  end

  def ==(node)
    return false if node.nil?
    @id == node.id
  end

  def network_ip(network)
    @ipaddresses.select{|addr| addr =~ /#{network}/}.first
  end

  def gen_node_id
    #ipaddresses.first.split(".")[3].to_i
    ipaddresses.sort.first
    #eval ipaddresses.sort.first.split(".").zip([11, 13, 17, 19].map(&:to_s)).map{|a| a.join('*')}.join('+')
  end

end
