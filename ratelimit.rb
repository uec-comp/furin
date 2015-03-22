#!/usr/bin/env ruby

def limited?(device)
  not `tc -s qdisc | grep burst`.chomp.empty?
end

def unlimit(device)
  `tc qdisc del dev #{device} root` if limited?(device)
end

def limit(device, rate)
  # limit to rate Mbps
  unlimit(device)
  `tc qdisc add dev #{device} root tbf limit 150kb buffer 200Kb rate #{rate * 1024 / 8}Kbps`
end

if ARGV.size != 2
  puts "usage: #{$0} <nic> <rate>"
  puts "set rate to 0 as unlimit"
  exit 0
end

# exit if no such device ARGV[0]
exit 0 if `ip a show dev #{ARGV[0]} >/dev/null 2>&1 && echo true || echo false`.chomp == 'false'

if ARGV[1].to_i == 0
  unlimit(ARGV[0])
  exit
else
  limit(ARGV[0], ARGV[1].to_i)
end

#Process.daemon



