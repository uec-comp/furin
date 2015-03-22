#-*- coding: utf-8 -*-

require 'socket'
require 'zlib'
require File.expand_path(File.join(File.dirname(__FILE__), 'utils'))
require File.expand_path(File.join(File.dirname(__FILE__), 'nodeinfo'))
require File.expand_path(File.join(File.dirname(__FILE__), 'error'))

# ネットワーク経由でのデータ転送を抽象化するモジュール．
module NetworkIO

  # リモートノードのメソッドを実行して結果をもらう
  def remote_handler_call_oneshot(nodeinfo, handler, *args)
    debug "remote_handler_call_oneshot: #{handler}, => #{nodeinfo.ipaddresses.first}"
    result = pray {
      socket = TCPSocket.new(nodeinfo.ipaddresses.first, nodeinfo.port)
      send_obj(socket, {:handler => handler, :args => args})    
      receive_obj(socket)
    }.alt{ block_given? ? yield : NoDataReceivedException }.luck
  end

  # データ転送時に一意に設定されるIDを生成
  def gen_object_id
    (('a'..'z').to_a + ('A'..'Z').to_a + ('0'..'9').to_a).shuffle[0..9].join
  end
  
  # Rubyオブジェクトを送信可能なテキストに変換する
  # Object => String
  def pack_obj(obj)
    begin
      clone_obj = deep_copy(obj)
      Zlib::Deflate.deflate(Marshal.dump(clone_obj))
    rescue => e
      error "#{__FILE__}:#{__LINE__}: #{e.inspect}"
      nil
    end
  end

  # テキストをRubyオブジェクトに変換する
  # String => Object
  def unpack_obj(obj)
    begin
      Marshal.restore(Zlib::Inflate.inflate(obj))
    rescue => e
      error "#{__FILE__}:#{__LINE__}: #{e.inspect}"
      nil
    end
  end

  # Rubyのオブジェクトを受け取ってMarshal.dumpして送信する
  def send_obj(socket, obj)
    debug "send: #{socket.addr.reverse[1,2].join(':')} => #{socket.peeraddr.reverse[1,2].join(':')}, #{obj.inspect}"
    socket.puts "<object_#{object_id}"
    socket.puts pack_obj(obj)
    socket.puts "object_#{object_id}>"
  end

  # Rubyのオブジェクトを受け取ってMarshal.restoreして受信
  def receive_obj(socket)
    buffer = ''
    line = nil

    line = socket.gets
    if line
      object_id = line.scan(/^<object_(.*)/).flatten.first
      while socket.gets
        line = $_
        break if (line =~ /^object_#{object_id}>/)
        buffer += line
      end
    end

    result = pray {
      unpack_obj(buffer)
    }.alt{ NoDataReceivedException }.luck

    debug "recv: #{socket.addr.reverse[1,2].join(':')} <= #{socket.peeraddr.reverse[1,2].join(':')}, #{result.inspect}"
    result
  end

end
