#-*- coding: utf-8 -*-

require 'socket'
require File.expand_path(File.join(File.dirname(__FILE__), 'utils'))
require File.expand_path(File.join(File.dirname(__FILE__), 'netio'))
require File.expand_path(File.join(File.dirname(__FILE__), 'eventhandler'))

# サーバを立てて受け取った結果をもとにEventHandlerを使って対応する処理を行う
class EventServer
  include NetworkIO

  def initialize(listen_ip, listen_port)
    @listen_ip = listen_ip
    @listen_port = listen_port
  end

  def start_server
    @server = TCPServer.new(@listen_ip, @listen_port)
    @server_thread = Thread.new {
      loop do
        client = @server.accept
        debug "accept connection from #{client.inspect}"
        Thread.new(client) { |client|
          begin
            # 受信したらそれに応じたハンドラを実行して結果を返す
            obj = receive_obj(client)
            debug "received object #{obj}"

            client.close if obj == NoDataReceivedException or obj.nil?
            send_obj(client, EventHandler.call(obj[:handler], *obj[:args])) unless client.closed?

          rescue => e
            #Kernel.binding.pry
            error "#{__FILE__}:#{__LINE__}: #{e.inspect}"
          ensure
            client.close
          end
        }
      end
    }
    debug "server started listing #{@listen_ip}:#{@listen_port}"
  end

  def stop_server
    # 既存のセッションは保持する
    @server.close
  end

  def serve_forever
    @server_thread.join
  end
  
end
