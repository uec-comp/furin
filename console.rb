#!/usr/bin/env ruby
#-*- coding: utf-8 -*-

require File.expand_path(File.join(File.dirname(__FILE__), 'netio'))
require 'pry'
require 'readline'

$ipaddress = ARGV[0]

include NetworkIO

def gets_code
  ruby_code = Readline.readline("mnet@#{$ipaddress}> ", true)
  Readline::HISTORY.pop if /^\s*$/ =~ ruby_code
  begin
    if Readline::HISTORY[Readline::HISTORY.length - 2]  == ruby_code
      Readline::HISTORY.pop
    end
  rescue
  end
end

def remote_eval(str)
  socket = TCPSocket.new($ipaddress, GlobalSettings::EVENT_SERVER_PORT)
  send_result = send_obj(socket, {:handler => :eval, :args => [str]})
  receive_result = receive_obj(socket)
  receive_result[:return_value]
end

while input = gets_code
  begin
    p remote_eval(input)
  rescue => e
    puts e.inspect
  end
end

