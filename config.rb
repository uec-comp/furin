# -*- coding: utf-8 -*-

module GlobalSettings
  # 接続先ノードのIPアドレス
  CONTENTS_ROOT_IP = '10.0.0.101'
  # 自ノードのNIC
  PUBLIC_NETWORK_INTERFACES = `ip -4 -o a | grep tun. | awk '{print $2}'`.split("\n")

  # EventServerの待ち受けIPとポート番号
  EVENT_SERVER_LISTEN_IP = '0.0.0.0'
  EVENT_SERVER_PORT = 3000

  LOG_OUTPUT = '/var/log/mnet/mnet.log'
  LOG_ROTATE = false

  DAEMONIZE = false

  # ping応答速度を測定するときのping回数
  PING_COUNT = 5
  # iperfで帯域測定を行う際の転送バイト数（MB）
  IPERF_TRANSMIT_SIZE_MB = 10
  # ネットワーク全体で使用するiperfの待ち受けポート番号
  IPERF_SERVER_PORT = 5001
  # 測定間隔
  MEASURE_INTERVAL_SEC = 10

  # デバッグモードのON/OFF
  DEBUG_MODE = true
  # エラー時にabortするかどうか
  EXIT_ON_ERROR = true

  PLAIN = 0x00001
  ERROR = 0x00010
  WARN  = 0x00100
  INFO  = 0x01000
  DEBUG = 0x10000

  DEBUG_LEVEL =  INFO

  # ログメッセージの出力先
  DEBUG_OUTPUT = STDERR
  INFO_OUTPUT  = STDERR
  WARN_OUTPUT  = STDERR
  ERROR_OUTPUT = STDERR
  PLAIN_OUTPUT = STDERR

  PRAY_TIMEOUT = 60
  RETRY_MAX = 3
  RETRY_DELAY = 5

  # 中継ノードを検索する際のパラメータ
  module FindIntermediateHosts
    # リトライする上限
    RETRY_COUNT = 3
    # リトライ間隔秒数
    RETRY_SLEEP_SEC_DEFAULT = 1
    RETRY_SLEEP_SEC_MAX = 10
    RETRY_SLEEP_SEC_SCALE = 1.5
    # タイムアウト秒数
    TIMEOUT_SEC = 2
  end

end
