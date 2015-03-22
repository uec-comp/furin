# -*- coding: utf-8 -*-
require File.expand_path(File.join(File.dirname(__FILE__), 'eventhandler'))
require File.expand_path(File.join(File.dirname(__FILE__), 'netio'))
require 'open3'
require 'timeout'

class RoutingManager
  include NetworkIO

  # 初期化
  def initialize(_self_nodeinfo, _top_nodeinfo = nil)
    # 自ノードの情報
    @self_nodeinfo = _self_nodeinfo
    # 最上位ノード
    @top_nodeinfo = _top_nodeinfo
    # 隣接ノード
    @neighbor_nodes = []
    # 自分を中継しているノード
    @downstream_nodes = []

    @iperf_test_check_mutex ||= Mutex.new
    @refine_neighbors_reservation = []

    @locked_ids_lock = Mutex.new
    @locked_ids = []
    @lock_reminder = []

    @known_nodes = [@self_nodeinfo, @top_nodeinfo]

    # ネットワーク状況監視サーバの起動
    @network_monitor = NetworkMonitor.new(@self_nodeinfo)

    EventHandler.register(:get_neighbor_nodes) { |args|
      begin
        @neighbor_nodes
      rescue => e
        Kernel.binding.pry
      end
    }
    EventHandler.register(:upstream_node) { |args|
      begin
        @self_nodeinfo.upstream_node
      rescue => e
        Kernel.binding.pry
      end
    }
    EventHandler.register(:iperf_test) { |args|
      begin
        iperf_test(*args)
      rescue => e
        Kernel.binding.pry
      end
    }
    EventHandler.register(:add_downstream_node) { |args|
      begin
        Thread.new { add_downstream_nodes(*args) }
        true
      rescue => e
        Kernel.binding.pry
      end
    }
    EventHandler.register(:delete_downstream_node) { |args|
      begin
        Thread.new { delete_downstream_node(*args) }
        true
      rescue => e
        Kernel.binding.pry
      end
    }
    EventHandler.register(:notice_new_neighbor) { |args|
      begin
        Thread.new { notice_new_neighbor(*args) }
        true
      rescue => e
        Kernel.binding.pry
      end
    }
    EventHandler.register(:throughput_to_top) { |args|
      begin
        @self_nodeinfo.throughput_to_top
      rescue => e
        Kernel.binding.pry
      end
    }
    EventHandler.register(:notify_me_as_new_neighbor) { |args|
      begin
        Thread.new { notify_me_as_new_neighbor(*args) }
        true
      rescue => e
        Kernel.binding.pry
      end
    }
    EventHandler.register(:upstream_chain_ids) { |args|
      begin
        upstream_chain_ids(*args)
      rescue => e
        Kernel.binding.pry
      end
    }
    EventHandler.register(:refine_neighbors) { |args|
      begin
        @refine_neighbors_reservation.push(1) if @refine_neighbors_reservation.size < 2
      rescue => e
        Kernel.binding.pry
      end
    }
    EventHandler.register(:reroute_recursive) { |args|
      begin
        Thread.new { reroute_recursive(*args) }
        true
      rescue => e
        Kernel.binding.pry
      end
    }
    EventHandler.register(:lock_node) { |args|
      begin
        lock_node(*args)
      rescue => e
        Kernel.binding.pry
      end
    }
    EventHandler.register(:unlock_node) { |args|
      begin
        unlock_node(*args)
      rescue => e
        Kernel.binding.pry
      end
    }
    EventHandler.register(:http_session_count) { |args|
      begin
        http_session_count
      rescue => e
        Kernel.binding.pry
      end
    }

    delete_route_to_top if defined_route_to_top?

    # @node_status = {}
    # EventHandler.register(:update_status) { |args|
    #   update_status(*args)
    # }
    # EventHandler.register(:update_status_local) { |args|
    #   update_status(*(args + [true]))
    # }

    # 自分が最上位ノードではない場合は既存のネットワークに接続する
    fresh_join unless @self_nodeinfo.top_node?

    @refine_thread = Thread.new {
      loop do
        unless @refine_neighbors_reservation.empty?
          @refine_neighbors_reservation.pop
          refine_neighbors
        end
        sleep 10
      end
    }

  end

  def http_session_count_of(nodeinfo)
    remote_handler_call_oneshot(nodeinfo, :http_session_count)
  end

  def throughput_to_top_of(nodeinfo)
    remote_handler_call_oneshot(nodeinfo, :throughput_to_top)
  end

  def upstream_node_of(nodeinfo)
    remote_handler_call_oneshot(nodeinfo, :upstream_node)
  end

  def upstream_chain_ids_of(nodeinfo)
    result = remote_handler_call_oneshot(nodeinfo, :upstream_chain_ids)
    Kernel.binding.pry unless result.instance_of? Array
    result
  end

  def lock_node(nodeinfo)
    @locked_ids_lock.synchronize {
      @locked_ids << nodeinfo.id
    }
  end

  def unlock_node(nodeinfo)
    @locked_ids_lock.synchronize {
      @locked_ids.delete(nodeinfo.id)
    }
  end

  def safely_connectable_node?(candidate)
=begin
・自分には接続できない
・孤島には接続できない
・ループが発生する場合は危険
=end
    if @locked_ids.include? candidate.id
      debug "cannot connect to #{candidate.id} (reason: locked)"
      return false
    end
    if candidate.id == @self_nodeinfo.id
      debug "cannot connect to #{candidate.id} (reason: self)"
      return false
    end
    if upstream_node_of(candidate).nil?
      debug "cannot connect to #{candidate.id} (reason: independent)"
      return false 
    end
    if upstream_chain_ids_of(candidate).include? @self_nodeinfo.id
      debug "cannot connect to #{candidate.id} (reason: loop)"
      return false
    end

    @locked_ids_lock.synchronize {
      remote_handler_call_oneshot(candidate, :lock_node, @self_nodeinfo)
      @lock_reminder << candidate
    }

    true

  end

  def upstream_chain_ids
    begin

      # 上位ノードがいる場合
      if @self_nodeinfo.upstream_node
        [@self_nodeinfo.id] + upstream_chain_ids_of(@self_nodeinfo.upstream_node)

      # 上位ノードがいない場合
      else
        [@self_nodeinfo.id]
      end

    rescue => e
      Kernel.binding.pry
    end

  end

  def add_neighbor_node(nodeinfo)
    return if @neighbor_nodes.select{|n| n.id == nodeinfo.id}.size > 0
    return if nodeinfo.id == @self_nodeinfo.id
    remote_handler_call_oneshot(nodeinfo, :notice_new_neighbor, @self_nodeinfo)
    @neighbor_nodes << nodeinfo
    @neighbor_nodes.uniq!{|n| n.id}
    @network_monitor.add_neighbor(nodeinfo)
  end

  def delete_neighbor_node(nodeinfo)
    return if @neighbor_nodes.select{|n| n.id == nodeinfo.id}.size == 0
    @neighbor_nodes.delete_if{|n| n.id == nodeinfo.id}
    @network_monitor.del_neighbor(nodeinfo)
  end

  def fresh_join
    debug "called method: fresh_join"
    # 隣接ノードを見つけ出す
    upstream_candidates = find_neighbor_nodes(@top_nodeinfo, true)

    real_candidates = upstream_candidates.select { |candidate|
      safely_connectable_node?(candidate)
    }

    info "setting upstream node (first time)"

    # 隣接ノードがいない場合はそのまま接続
    if real_candidates.empty?
      @top_nodeinfo.throughput_to_top = remote_handler_call_oneshot(@top_nodeinfo, :throughput_to_top)
      throughput = remote_handler_call_oneshot(@top_nodeinfo, :iperf_test, @self_nodeinfo)
      warn "#{throughput[1]} Mbps to #{@top_nodeinfo.id}"
      add_neighbor_node(@top_nodeinfo)
      set_upstream_node(@top_nodeinfo, throughput[0], throughput[1])

    # 隣接ノードがいる場合は最も速い子ノードに接続
    else
      real_candidates.each do |node|
        add_neighbor_node(node)
      end
      set_upstream_node(*select_fastest_node(real_candidates))
    end

    debug "end of fresh_join"
  end

  # 隣接ノードを検証する
  def refine_neighbors
    warn "called method: refine_neighbors"

    nodes_to_delete = []
    @neighbor_nodes.each do |neighbor|
      unless neighbor_node?(neighbor)
        # 隣接ノードではないノードが見つかった場合は@neighborから削除
        nodes_to_delete << neighbor
      end
    end
    # 隣接ノードから削除
    nodes_to_delete.each do |node|
      delete_neighbor_node(node)
    end

    real_candidates = @neighbor_nodes.select { |candidate|
      safely_connectable_node?(candidate)
    }

    # warn real_candidates
    # Kernel.binding.pry if real_candidates.empty?

    # 隣接ノードがいない場合はそのまま接続
    if real_candidates.empty?
      @top_nodeinfo.throughput_to_top = remote_handler_call_oneshot(@top_nodeinfo, :throughput_to_top)
      throughput = remote_handler_call_oneshot(@top_nodeinfo, :iperf_test, @self_nodeinfo)
      warn "#{throughput[1]} Mbps to #{@top_nodeinfo.id}"
      set_upstream_node(@top_nodeinfo, throughput[0], throughput[1])
      # 隣接ノードがいる場合は最も速い子ノードに接続
    else
      set_upstream_node(*select_fastest_node(real_candidates))
    end


    debug "end of refine_neighbors"
  end


  def notice_new_neighbor(nodeinfo)
    debug "called method: notice_new_neighbor"
    # 隣接ノードから新しいノードがきたことがお知らせされた
    # 知っていたら何もしない
    return if @known_nodes.include?(nodeinfo)
    # 知らなかった場合，とりあえず知っているホストのリストに追加
    @known_nodes |= [nodeinfo]
    @known_nodes.uniq!{|node| node.id}
    # 隣接ノードだったら隣接ノードのリストに追加
    if neighbor_node?(nodeinfo)
      # 隣接ノードに不整合が起きている可能性があるので検証する
      find_neighbor_nodes(nodeinfo)
      @refine_neighbors_reservation.push(1) if @refine_neighbors_reservation.size < 2
    end
  end

  def add_downstream_nodes(nodeinfo)
    debug "called method: add_downstream_nodes"

    # # 隣接ノードであることを検証する
    # if neighbor_node?(nodeinfo)
      # 隣接ノードのリストに追加
      add_neighbor_node(nodeinfo)
      # 子ノードのリストに追加
      @downstream_nodes |= [nodeinfo]
      @downstream_nodes.uniq!{|n| n.id}

      true
    # # 隣接ノードではなかった場合は自分の隣接ノードを紹介する
    # else
    #   error "I'm not neighbor of #{nodeinfo.id}"
    #   @neighbor_nodes
    # end
  end

  def notify_me_as_new_neighbor(nodeinfo)
    # 隣接ノードにノードの追加をお知らせ
    @neighbor_nodes.each do |neighbor|
      next if neighbor.id == nodeinfo.id or neighbor.id == @self_nodeinfo.id
      remote_handler_call_oneshot(neighbor, :notice_new_neighbor, nodeinfo)
    end
  end


  def delete_downstream_node(nodeinfo)
    debug "called method: delete_downstream_node"
    # 子ノードのリストから削除する
    @downstream_nodes.delete(nodeinfo)
    # refine_neighbors
  end

  def set_upstream_node(nodeinfo, faster_ipaddress, throughput_to_top)
    @locked_ids_lock.synchronize {
      @lock_reminder.each do |node|
        remote_handler_call_oneshot(node, :unlock_node, @self_nodeinfo)
      end
      @lock_reminder = []
    }

    return if @self_nodeinfo.top_node?
    unless @self_nodeinfo.upstream_node.nil?
      return if nodeinfo.id == @self_nodeinfo.upstream_node.id
    end

    debug "called_method: set_upstream_node to #{nodeinfo.id} (#{throughput_to_top})"

    Kernel.binding.pry if nodeinfo.id == @self_nodeinfo.id
    nou = upstream_node_of(nodeinfo)
    if nou
      return if nou.id == @self_nodeinfo.id
    end

    # 最上位ノードまでの帯域を設定
    @self_nodeinfo.throughput_to_top = throughput_to_top

    last_upstream_node = @self_nodeinfo.upstream_node
    # 上位ノードを設定する
    @self_nodeinfo.upstream_node = nodeinfo
    @self_nodeinfo.upstream_node.upstream_node = nil
    # 上位ノードに通知（上位ノードの@downstream_nodesに追加される）
    remote_handler_call_oneshot(@self_nodeinfo.upstream_node, :add_downstream_node, @self_nodeinfo)
    remote_handler_call_oneshot(@self_nodeinfo.upstream_node, :notify_me_as_new_neighbor, @self_nodeinfo)
    # 以前の上位ノードに切断要求を出す
    unless last_upstream_node.nil?
      remote_handler_call_oneshot(last_upstream_node, :delete_downstream_node, @self_nodeinfo)
    end

    # お隣さんにご挨拶
    @neighbor_nodes.each do |neigh|
      next if neigh.id == nodeinfo.id or neigh.id == @self_nodeinfo.id
      remote_handler_call_oneshot(neigh, :notice_new_neighbor, @self_nodeinfo)
    end

    upstream_ip = update_upstream_route(nodeinfo)
    info "set upstream_node to #{upstream_ip} (#{throughput_to_top})"

  end

  def neighbor_node?(node)
    debug "called method: neighbor_node?"
    # 知っているIPアドレスのリスト
    known_ips = @known_nodes.map{|node| node.ipaddresses}.flatten.uniq

    # 対象ノードのすべてのIPアドレスについて検査
    is_neighbor = false
    node.ipaddresses.each do |ipaddress|
      return true if is_neighbor
      # 中継IPアドレスのリスト
      intermediate_ips = find_intermediate_ips(ipaddress, node)
      next if intermediate_ips.nil?
      # 中継IPアドレスの中に知っているIPアドレスが含まれていないことを確認する
      # 集合積が空集合であることを検証すればよい
      begin
        is_neighbor = (is_neighbor or (intermediate_ips & known_ips).empty?)
      rescue => e
        Kernel.binding.pry
      end
    end

    is_neighbor
  end

  def neighbor_ip?(ipaddress, nodeinfo = nil)
    known_ips = @known_nodes.map{|node| node.ipaddresses}.flatten.uniq
    intermediate_ips = find_intermediate_ips(ipaddress, nodeinfo)
    (intermediate_ips & known_ips).empty?
  end

  def find_neighbor_nodes(search_origin_node = @top_nodeinfo, refresh = false)
    debug "called method: find_neighbor_nodes"
    # 近くのノードを忘れる
    @neighbor_nodes = [] if refresh
    # まずはすべてのノードを検索する
    find_all_nodes(search_origin_node, refresh)
    @known_nodes.uniq!{|node| node.id}
    # 知っているノード群から隣接ノードを抽出する
    @known_nodes.reverse.each do |known_node|
      add_neighbor_node(known_node) if neighbor_node?(known_node)
    end
    @neighbor_nodes
  end

  def find_all_nodes(search_origin_node = @top_nodeinfo, refresh = false)
    debug "called method: find_all_nodes"

    # 最初はどのノードも知らない
    @known_nodes = [@self_nodeinfo, search_origin_node] if refresh

    # 起点のノードから隣接ノードを取得．この集合に順次検索をかけていく．
    strange_nodes = remote_handler_call_oneshot(search_origin_node, :get_neighbor_nodes)

    # 知っているノードは検索対象から外す
    @known_nodes.each do |node|
      strange_nodes.delete_if{|n| n.id == node.id}
    end

    # 今から検索するノードは知っているものとみなす
    @known_nodes += strange_nodes
    @known_nodes.uniq!{|node| node.id}

    # 今検索したノードも知ってるよね
    @known_nodes += [search_origin_node]

    # 知らなかったノード群から再帰的に隣接ノードを取得
    strange_nodes.each do |candidate|
      @known_nodes += find_all_nodes(candidate)
      @known_nodes.uniq!{|node| node.id}
    end

    @known_nodes
  end

  def direct_link?(ipaddress, nodeinfo = nil)
    intermediate_ips = find_intermediate_ips(ipaddress, nodeinfo)
    return [false, 0] if intermediate_ips.nil?
    is_direct = (@known_nodes.map{|node| node.ipaddresses}.flatten & intermediate_ips).empty?
    rank = intermediate_ips.size
    [is_direct, rank]
  end

  def iperf_test(nodeinfo)
    @iperf_test_check_mutex.synchronize {
      @scan_log ||= {}
      @iperf_test_mutex ||= {}
    }

    debug "called method: iperf_test"
    throughput_list = [[nil, 0.0]]

    $iperf_test_count ||= 1

    # 直接リンクしてるノードについて検査する
    target_ips = nodeinfo.ipaddresses.map{|ip|
      [ip, direct_link?(ip, nodeinfo)].flatten
    }.select{|ip, is_direct, rank| is_direct }

    # すべてのIPが間接アクセスだったら適当なIPを速度0として報告する
    return [nodeinfo.ipaddresses.first, 0.0] if target_ips.empty?

    scanned_rank_0 = false
    # 速い方を選択する
    target_ips.each do |ipaddress, is_direct, rank|

      @iperf_test_check_mutex.synchronize {
        @iperf_test_mutex[ipaddress] ||= Mutex.new
      }

      if rank == 0
        next if scanned_rank_0
        scanned_rank_0 = true
      end
      # IPアドレスに到達できなければ検査しない
      next unless host_up?(ipaddress)

      @iperf_test_mutex[ipaddress].synchronize {

        # 初期値を設定しておく
        @scan_log[ipaddress] ||= {}
        @scan_log[ipaddress][:last_time] ||= (Time.now - (60 * 60 * 24))
        @scan_log[ipaddress][:last_throughput_list] ||= []
        throughput = 0.0

        # 30秒以内に更新されたものだったらそのまま利用する
        if Time.now - @scan_log[ipaddress][:last_time] < 30
          @scan_log[ipaddress][:last_throughput_list].each do |bw|
            throughput += bw
          end
          throughput /= @scan_log[ipaddress][:last_throughput_list].size
          Kernel.binding.pry if throughput.nan?
          info "skipped iperf test for #{ipaddress} (report last value: #{throughput}Mbps)"

          # それ以上経過していたら新しく計測し直す
        else
          # 計測

          transfer_b = `grep : /proc/net/dev | awk '{print $1" "$2" "$10}' | sed 's/://g'`.split("\n").map{|line| line.split(/\s+/)}
          time_b = Time.now
          `iperf -f m -c #{ipaddress} -p #{GlobalSettings::IPERF_SERVER_PORT} -n #{GlobalSettings::IPERF_TRANSMIT_SIZE_MB}M`
          time_a = Time.now
          transfer_a = `grep : /proc/net/dev | awk '{print $1" "$2" "$10}' | sed 's/://g'`.split("\n").map{|line| line.split(/\s+/)}
          delta_t = time_a - time_b
          nic = find_port(ipaddress)
          rx_before, tx_before = transfer_b.select{|dev, rx, tx| dev == nic}.first[1..2]
          rx_after, tx_after   = transfer_a.select{|dev, rx, tx| dev == nic}.first[1..2]
          rx_bytes = rx_after.to_i - rx_before.to_i
          tx_bytes = tx_after.to_i - tx_before.to_i
          bw = {:rx_bw => rx_bytes*8/delta_t/1024/1024, :tx_bw => tx_bytes*8/delta_t/1024/1024}
          current_throughput = bw[:tx_bw]

          #current_throughput = `iperf -f m -c #{ipaddress} -p #{GlobalSettings::IPERF_SERVER_PORT} -n #{GlobalSettings::IPERF_TRANSMIT_SIZE_MB}M | grep -A 1 Transfer | tail -1 | grep -Eo '[0-9\\.]+\\s+Mbits/sec' | awk '{print $1}'`.to_f

          # どれくらいテスト転送したか出力
          info "iperf test request from #{ipaddress} (total #{$iperf_test_count * GlobalSettings::IPERF_TRANSMIT_SIZE_MB}MB)"
          $iperf_test_count += 1

          # タイムスタンプを更新
          @scan_log[ipaddress][:last_time] = Time.now

          # スループットのリストを更新
          @scan_log[ipaddress][:last_throughput_list] << current_throughput

          # 大きくなり過ぎたら古いデータを削除
          if @scan_log[ipaddress][:last_throughput_list].size > 5
            @scan_log[ipaddress][:last_throughput_list].delete_at(0)
          end
          # 新しいスループットを計算
          throughput = 0.0
          @scan_log[ipaddress][:last_throughput_list].each do |bw|
            throughput += bw
          end
          throughput /= @scan_log[ipaddress][:last_throughput_list].size

        end

        throughput_list << [ipaddress, throughput]
        Kernel.binding.pry if throughput.nan?
      }
    end

    result = throughput_list.sort_by{|ip, throughput| -throughput}.first
    Kernel.binding.pry if result.first.nil?
    result
  end

  def count_http_sessions(ipaddress, only_my_sessions = false)
    my_sessions = `ss -n | grep #{ipaddress}:80 | wc -l`.chomp.to_i
    return my_sessions if only_my_sessions
    upstream_node_sessions = 0
    upstream_node_sessions = http_session_count_of(@self_nodeinfo.upstream_node) if @self_nodeinfo.upstream_node
    total_sessions = [my_sessions, upstream_node_sessions].max
  end

  def http_session_count(ipaddress = GlobalSettings::CONTENTS_ROOT_IP, only_my_sessions = false)
    @last_session_counts ||= []

    return 0.0 if @self_nodeinfo.top_node?
    if @self_nodeinfo.upstream_node
      if @self_nodeinfo.upstream_node.top_node?
        return 0.0
      end
    end

    if @last_session_counts.empty?
      # 空だったらとりあえず測定する
      @last_session_counts << [Time.now, count_http_sessions(ipaddress, only_my_sessions)]
    elsif Time.now - @last_session_counts.last.first > 0
      # 最終更新から5秒以上経過していたら再測定する
      @last_session_counts << [Time.now, count_http_sessions(ipaddress, only_my_sessions)]
    end

    # 直近5つを超えたら古い情報を削除
    @last_session_counts.delete_at(0) if @last_session_counts.size > 5

    # 平均を計算して返す
    avg_sessions = 0
    @last_session_counts.each{|time, count| avg_sessions += count}
    avg_sessions / @last_session_counts.size.to_f
  end

  def ip2bin(ipaddress)
    ipaddress.split(".").map{|n| n.to_i.to_s(2)}.map{|s| "0" * (8 - s.size) + s}.join
  end

  def bin2ip(ipaddress_bin)
    ip = []
    4.times do |i|
      ip << ipaddress_bin[8*i..8*i+7]
    end
    ip.map{|sub| sub.to_i(2).to_s}.join(".")
  end

  def find_port(ipaddress)

    return "lo" if @self_nodeinfo.ipaddresses.include? ipaddress

    routes = `ip r`.split("\n")
    
    # default link
    dl = routes.select{|route| route =~ /default/}.map{|route|
      splitline = route.split(/\s+/)
      [splitline[0], splitline[4]]
    }
    
    # on link
    otl = routes.select{|route| route =~ /link/}.map{|route|
      splitline = route.split(/\s+/)
      [splitline[0], splitline[2]]
    } - dl
    
    # not on link
    notl = routes.select{|route| (not route =~ /link/) }.map{|route|
      splitline = route.split(/\s+/)
      [splitline[0], splitline[4]]
    } - dl - otl
    
    port_map = otl + notl
    
    port_map_net = port_map.select{|net, dev| net =~ /\//}
    port_map_host = port_map - port_map_net
    
    # host base search
    port = port_map_host.select{|host, dev| host == ipaddress}
    unless port.empty?
      return port.first.last
    end
    
    # network base search
    port_map_net.map!{|network, dev|
      ip, prefix = network.split("/")
      bin = ip2bin(ip)
      net = bin[0..prefix.to_i-1]
      [net, prefix.to_i, dev]
    }
    
    ipaddress_bin = ip2bin(ipaddress)
    port_map_net.sort_by{|netbin, prefix, dev| -prefix}.each do |netbin, prefix, dev|
      if ipaddress_bin[0..prefix-1] == netbin
        return dev
      end
    end

    # return default route device
    return dl.flatten.last
  end

  def measure_throughput(candidate)
    ip, bw = remote_handler_call_oneshot(candidate, :iperf_test, @self_nodeinfo)

    sessions = 0.0
    if @self_nodeinfo.upstream_node
      if candidate.id == @self_nodeinfo.upstream_node.id
        # 自分の上流ノードのときは普通に数える
        sessions = http_session_count
      else
        # 自分の上流ノードでないとき
        sessions = (http_session_count(GlobalSettings::CONTENTS_ROOT_IP, true) + http_session_count_of(candidate)).to_f
      end
    end

    [ ip, bw, sessions ]

  end

  # 複数のノードの中から最も速いノードを選択する
  def select_fastest_node(candidates)
    debug "called method: select_fastest_node"

    # 最上位ノードが選択可能なら優先的に接続する
    # return @top_nodeinfo if candidates.select{|candidate| candidate.id == @top_nodeinfo.id}.size > 0

    # スループットを計測
    candidate_throughput = []
    threads = []

    candidates.each do |candidate|
      # 自分は除外する
      next if candidate.id == @self_nodeinfo.id

      # 自ノード宛てにiperfでデータを送信してもらい，帯域を計測する
      ip, bw, sessions = measure_throughput(candidate)

      warn "#{bw} Mbps to #{candidate.id} (#{sessions} sessions)"
      fastest_ip = nil
      begin
        fastest_ip = (ip.split(".")[0..2] + [candidate.ipaddresses.first.split(".")[3]]).join(".")
      rescue => e
        Kernel.binding.pry
      end
      candidate.faster_ipaddress = fastest_ip
      candidate_throughput << [candidate, bw, sessions]
    end

    # [([候補ノード~最上位ノード間スループット, 自ノード~候補ノード間スループット].min)/sessions].max となるノードを選択

    fastest_node = candidate_throughput.map { |candidate, throughput, sessions|
      if sessions >= 1.0
        [candidate, ([throughput_to_top_of(candidate), throughput].min)/sessions.to_f]
      else
        [candidate, ([throughput_to_top_of(candidate), throughput].min)]
      end
    }.sort_by{|candidate, throughput| -throughput}.first

    return @top_nodeinfo if fastest_node.nil?
    fastest_node = fastest_node.first

    fastest_ip, fastest_bw, sessions = candidate_throughput.select{|candidate, throughput, sessions| candidate.id == fastest_node.id}.first

    [fastest_node, fastest_ip, fastest_bw]
  end

  def nmap_up?(ipaddress)
    not `nmap -T5 -n -sT --disable-arp-ping -Pn -p #{GlobalSettings::EVENT_SERVER_PORT} #{ipaddress} | grep open`.empty?
  end

  # ホストが起動しているかを調べる
  def host_up?(ipaddress)
    #debug "called method: host_up?"
    #nmap_up = nmap_up?(ipaddress)
    nmap_up = true
    ping_up = `timeout 3 ping -c 1 #{ipaddress} >/dev/null 2>&1 && echo -n true || echo -n false` == "true"
    nmap_up and ping_up
  end

  # tracerouteで中継ホストのIPアドレスのリストを取得する
  def find_intermediate_ips(ipaddress, nodeinfo = nil)
    debug "called method: find_intermediate_ips (#{ipaddress}, pseudo = #{not nodeinfo.nil?})"
    @intermediate_ips ||= {}
    @intermediate_ips[ipaddress] ||= {:data => [], :time => Time.now - 10000}

    if nodeinfo
      # 対象ホストのIPアドレス群
      net_ids = nodeinfo.ipaddresses.map{|addr| addr.split(".")[2].to_i}
      # 自ノードのIPアドレス群
      my_net_ids = @self_nodeinfo.ipaddresses.map{|addr| addr.split(".")[2].to_i}

      # 共通するネットワークが存在する
      unless (net_ids & my_net_ids).empty?
        @intermediate_ips[ipaddress][:data] = []
        @intermediate_ips[ipaddress][:time] = Time.now
        debug "find_intermediate_ips: return []"
        return []
      end
    end

    # memoize
    return @intermediate_ips[ipaddress][:data] if (Time.now - @intermediate_ips[ipaddress][:time]) < 10

    total_result = []
    result = nil
    retry_count_max = GlobalSettings::FindIntermediateHosts::RETRY_COUNT
    retry_count = -1

    retry_sleep_sec = GlobalSettings::FindIntermediateHosts::RETRY_SLEEP_SEC_DEFAULT
    loop do
      retry_count += 1
      start = Time.now
      return unless host_up?(ipaddress) # ホストが死んでたらnilを返す
      result = `timeout #{GlobalSettings::FindIntermediateHosts::TIMEOUT_SEC} traceroute -I -n -q 1 #{ipaddress} | tail -n +2 | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+'`.split("\n")
      time = Time.now - start
      total_result += result # 取得したホスト一覧を追加（予備のリスト）
      if time < GlobalSettings::FindIntermediateHosts::TIMEOUT_SEC # 正常終了
        break
      else
        result = nil
        if retry_count == retry_count_max
          result = total_result.uniq
        end
      end

      sleep [retry_sleep_sec, GlobalSettings::FindIntermediateHosts::RETRY_SLEEP_SEC_MAX].min
      retry_sleep_sec *= GlobalSettings::FindIntermediateHosts::RETRY_SLEEP_SEC_SCALE ** retry_count
    end

    @intermediate_ips[ipaddress][:data] = result.reject{|ip| ip == ipaddress}
    @intermediate_ips[ipaddress][:time] = Time.now

    result.reject{|ip| ip == ipaddress}
  end

  def ip_r(arg)
    @ip_r_mutex ||= Mutex.new
    @ip_r_mutex.synchronize {
      result = `ip r #{arg}`
      sleep 0.15
      result
    }
  end

  def defined_route_to_top?
    not ip_r(" | awk '{print $1}' | grep #{GlobalSettings::CONTENTS_ROOT_IP}").empty?
  end

  def delete_route_to_top
    ip_r(" | grep #{GlobalSettings::CONTENTS_ROOT_IP}").split("\n").each do |route|
      next unless route =~ /^#{GlobalSettings::CONTENTS_ROOT_IP}/
      ip_r("del #{route}")
    end
  end

  def add_route_to_top(via)
    info "set route to #{GlobalSettings::CONTENTS_ROOT_IP} via #{via}"
    debug "ip r add #{GlobalSettings::CONTENTS_ROOT_IP} via #{via}"
    ip_r("add #{GlobalSettings::CONTENTS_ROOT_IP} via #{via}")
  end

  def my_links
    ip_r(" | grep link | grep tun | awk '{print $1}'").split("\n")
  end

  def defined_routes
    ip_r(" | grep -v link | grep tun | awk '{print $1}'").split("\n")
  end

  def mutual_network(nodeinfo_a, nodeinfo_b)
    network = (nodeinfo_a.ipaddresses.map{|ip| ip.split(".")[0..2].join(".")} &
               nodeinfo_b.ipaddresses.map{|ip| ip.split(".")[0..2].join(".")}).first
  end

  def one_hop?(cidr)
    network = cidr.split(".")[0..2].join(".")
    one_hop = false
    @neighbor_nodes.each do |nodeinfo|
      one_hop |= (not nodeinfo.network_ip(network).nil?)
    end
    one_hop
  end

  def reroute(target_links, via_nodeinfo)
    return if @self_nodeinfo.top_node?

    routes_to_modify = (target_links - my_links) & defined_routes
    network = mutual_network(@self_nodeinfo, via_nodeinfo)
    return if network.nil?

    via_ip = via_nodeinfo.network_ip(network)
    routes_to_modify.each do |route|
      next if one_hop?(route)
      ip_r(" | grep #{route}").split("\n").select{|line| line =~ /^#{route}/}.each do |args|
        next if args =~ /#{via_ip}/
        ip_r("del #{args}")
      end
      if ip_r(" | grep #{route} | grep #{via_ip}").empty?
        debug "ip r add #{route} via #{via_ip}"
        ip_r("add #{route} via #{via_ip}")
      end
    end
  end

  def reroute_recursive(target_links, via_nodeinfo)
    reroute(target_links, via_nodeinfo)
    return if @self_nodeinfo.top_node?
    remote_handler_call_oneshot(@self_nodeinfo.upstream_node, :reroute_recursive, target_links, @self_nodeinfo)
  end

  def update_upstream_route(nodeinfo)

    return nodeinfo.id if nodeinfo.top_node?

    # network = (nodeinfo.ipaddresses.map{|ip| ip.split(".")[0..2].join(".")} &
    # @self_nodeinfo.ipaddresses.map{|ip| ip.split(".")[0..2].join(".")}).first
    network = mutual_network(nodeinfo, @self_nodeinfo)
    return nodeinfo.id if network.nil?

    via = nodeinfo.network_ip(network)
    delete_route_to_top if defined_route_to_top?
    add_route_to_top(via)
    remote_handler_call_oneshot(@self_nodeinfo.upstream_node, :reroute_recursive, my_links, @self_nodeinfo)

    via
  end


end

