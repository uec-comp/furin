#-*- coding: utf-8 -*-

require File.expand_path(File.join(File.dirname(__FILE__), 'utils'))

# イベント駆動のエンジンとなるクラス
=begin 使い方

1．ハンドラの登録
   # 引数を2つ受け取って足し算するメソッドを追加する
   EventHandler.register(:add) { |lhs, rhs| lhs + rhs }

2．イベントの発生
   EventHandler.call(:add, 10, 20) #=> 30

3．ハンドラの削除
   EventHandler.unregister(:add)

=end

class EventHandler
  @@eventpool = {}

  def self.call(symbol, *args)
    debug "call #{symbol}"
    unless @@eventpool[symbol]
      warn "#{__FILE__}:#{__LINE__}: Symbol '#{symbol}' is not registered"
    end
    @@eventpool[symbol].call(args)
  end

  def self.register(symbol, &proc)
    @@eventpool[symbol] = proc
    debug "registered #{symbol} => #{proc.inspect}"
  end

  def self.unregister(symbol)
    @@eventpool.delete(symbol) if @@eventpool[symbol]
    debug "unregistered #{symbol} => #{proc.inspect}"
  end

end

EventHandler.register(:up?){ true }
EventHandler.register(:eval) { |arg|
  begin
    eval arg.first
  rescue => e
    e.inspect
  end
}






