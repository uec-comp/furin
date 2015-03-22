#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

require 'fileutils'
require 'pry'
require File.expand_path(File.join(File.dirname(__FILE__), 'config'))

puts "creating #{File.dirname(GlobalSettings::LOG_OUTPUT)}"
FileUtils.mkdir_p(File.dirname(GlobalSettings::LOG_OUTPUT))
FileUtils.touch(GlobalSettings::LOG_OUTPUT)

require File.expand_path(File.join(File.dirname(__FILE__), 'utils'))
require File.expand_path(File.join(File.dirname(__FILE__), 'monitor'))
require File.expand_path(File.join(File.dirname(__FILE__), 'routingmanager'))
require File.expand_path(File.join(File.dirname(__FILE__), 'eventserver'))

# ログファイルの準備
if GlobalSettings::LOG_ROTATE
  if File.exists? GlobalSettings::LOG_OUTPUT
    new_filename =
      GlobalSettings::LOG_OUTPUT + Time.now.strftime("%Y-%m-%d-%H-%M-%S")
    File.rename(GlobalSettings::LOG_OUTPUT, new_filename)
  end
end

# 帯域測定用サーバの起動
info "starting iperf server listening #{GlobalSettings::IPERF_SERVER_PORT}"
Thread.new {
  `killall iperf`
  `iperf -s -p #{GlobalSettings::IPERF_SERVER_PORT}`
}

sleep 0.5

# 自分のIPアドレスを取得
my_ips = []
GlobalSettings::PUBLIC_NETWORK_INTERFACES.each do |dev|
  my_ips += ip_addresses_of(dev)
end
my_ips.flatten!
info "my ipaddresses are [#{my_ips.join(", ")}]"

# 自分のNodeInfoオブジェクトを生成
debug "main: creating self_nodeinfo"
self_nodeinfo = NodeInfo.new(my_ips, GlobalSettings::CONTENTS_ROOT_IP)

# 目的ノードのNodeInfoオブジェクトを生成
debug "main: creating dest_nodeinfo"
dest_nodeinfo = NodeInfo.new([GlobalSettings::CONTENTS_ROOT_IP], GlobalSettings::CONTENTS_ROOT_IP)

# 他のノードからの接続を受付開始
event_server = EventServer.new(GlobalSettings::EVENT_SERVER_LISTEN_IP, GlobalSettings::EVENT_SERVER_PORT)
debug "starting EventServer"
event_server.start_server

# 経路選択を開始
debug "starting RoutingManager"
routing_manager = RoutingManager.new(self_nodeinfo, dest_nodeinfo)

# 永続動作
debug "serve forever"
event_server.serve_forever

Process.daemon if GlobalSettings::DAEMONIZE

