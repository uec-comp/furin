#-*- coding: utf-8 -*-

=begin rdoc
一般的に利用するメソッドを定義
=end

require 'pry'
require 'timeout'
require File.expand_path(File.join(File.dirname(__FILE__), 'config'))

# 出力が重ならないように制御するためのMutex
$print_mutex = Mutex.new

# 時刻を表示するメソッド
def time
  Time.now.strftime('%H:%M:%S.%N')
end

# logfileへの出力
def log_output(message)
  f = open(GlobalSettings::LOG_OUTPUT, 'a')
  f.puts message
  f.close
end

# debugレベルでの出力
def _message(msg, color, label, level, output)
  $print_mutex.synchronize {
    line = "[#{time}] \33[#{color};1m#{label}\33[0m: #{msg}"
    if GlobalSettings::DEBUG_LEVEL >= level and not GlobalSettings::DAEMONIZE
      output.puts line
    end
    log_output line
  }
end

# debugレベルでの出力
def debug(msg)
  _message(msg, 35, "debug", GlobalSettings::DEBUG, GlobalSettings::DEBUG_OUTPUT)
end

# infoレベルでの出力
def info(msg)
  _message(msg, 34, "info", GlobalSettings::INFO, GlobalSettings::INFO_OUTPUT)
end

# warning出力
def warn(msg)
  _message(msg, 33, "warn", GlobalSettings::WARN, GlobalSettings::WARN_OUTPUT)
end

# error出力
# [message] 出力文字
# [binding] Kernel.bindingを設定する
def error(msg, binding = nil)
  _message(msg, 31, "error", GlobalSettings::ERROR, GlobalSettings::ERROR_OUTPUT)
  (binding.pry unless binding.nil?) if GlobalSettings::DEBUG_MODE
  #exit 1 if GlobalSettings::EXIT_ON_ERROR
end

# 与えられた文字列をそのまま表示
def plain_puts(msg)
  _message(msg, 0, "plain", GlobalSettings::PLAIN, GlobalSettings::PLAIN_OUTPUT)
end

# オブジェクトを完全にコピーする
def deep_copy(object)
  begin
    Marshal.load(Marshal.dump(object))
  rescue => e
    e
  end
end

# 指定されたNICのIPアドレスを返すメソッド
def ip_addresses_of(nic, ipv = 4)
  `ip -#{ipv} a show dev #{nic} | grep inet | awk '{print $2}'`.split("\n").map{|ip| ip.split("/").first}.flatten
end


class Fortune
  attr_reader :luck
  def initialize(lucky = false, result = nil)
    @lucky = lucky
    @luck = result
  end

  def alt
    @luck = yield if (block_given? and not @lucky)
    self
  end
end

# ブロックを渡すと数回繰り返す
# pray{ call_some_method }.alt{ set_alternative_value }.luck
def pray(timeout_sec = GlobalSettings::PRAY_TIMEOUT, retry_remaining = GlobalSettings::RETRY_MAX)
  return Fortune.new unless block_given?
  Timeout.timeout(timeout_sec) do
    Fortune.new(true, yield)
  end
rescue StandardError => e
  unless (retry_remaining -= 1) > 0
    debug "rescue: #{e.inspect}"
    debug e.backtrace.map{|s| "  " + s}
    return Fortune.new
  end
  sleep GlobalSettings::RETRY_DELAY
  retry
end

