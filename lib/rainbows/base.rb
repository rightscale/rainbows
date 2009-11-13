# -*- encoding: binary -*-

module Rainbows

  # base class for Rainbows concurrency models, this is currently
  # used by ThreadSpawn and ThreadPool models
  module Base

    include Unicorn
    include Rainbows::Const
    G = Rainbows::G

    def listen_loop_error(e)
      G.alive or return
      logger.error "Unhandled listen loop exception #{e.inspect}."
      logger.error e.backtrace.join("\n")
    end

    def init_worker_process(worker)
      super(worker)
      G.tmp = worker.tmp

      # we're don't use the self-pipe mechanism in the Rainbows! worker
      # since we don't defer reopening logs
      HttpServer::SELF_PIPE.each { |x| x.close }.clear
      trap(:USR1) { reopen_worker_logs(worker.nr) }
      trap(:QUIT) { G.quit! }
      [:TERM, :INT].each { |sig| trap(sig) { exit!(0) } } # instant shutdown
      logger.info "Rainbows! #@use worker_connections=#@worker_connections"
    end

    # once a client is accepted, it is processed in its entirety here
    # in 3 easy steps: read request, call app, write app response
    def process_client(client)
      buf = client.readpartial(CHUNK_SIZE)
      hp = HttpParser.new
      env = {}
      alive = true
      remote_addr = TCPSocket === client ? client.peeraddr.last : LOCALHOST

      begin # loop
        while ! hp.headers(env, buf)
          buf << client.readpartial(CHUNK_SIZE)
        end

        env[RACK_INPUT] = 0 == hp.content_length ?
                 HttpRequest::NULL_IO :
                 Unicorn::TeeInput.new(client, env, hp, buf)
        env[REMOTE_ADDR] = remote_addr
        response = app.call(env.update(RACK_DEFAULTS))

        if 100 == response.first.to_i
          client.write(EXPECT_100_RESPONSE)
          env.delete(HTTP_EXPECT)
          response = app.call(env)
        end

        alive = hp.keepalive? && G.alive
        out = [ alive ? CONN_ALIVE : CONN_CLOSE ] if hp.headers?
        HttpResponse.write(client, response, out)
      end while alive and hp.reset.nil? and env.clear
      client.close
    # if we get any error, try to write something back to the client
    # assuming we haven't closed the socket, but don't get hung up
    # if the socket is already closed or broken.  We'll always ensure
    # the socket is closed at the end of this function
    rescue => e
      handle_error(client, e)
    end

    def join_threads(threads)
      G.quit!
      expire = Time.now + (timeout * 2.0)
      until (threads.delete_if { |thr| ! thr.alive? }).empty?
        threads.each { |thr|
          G.tick
          thr.join(1)
          break if Time.now >= expire
        }
      end
    end

    def self.included(klass)
      klass.const_set :LISTENERS, HttpServer::LISTENERS
      klass.const_set :G, Rainbows::G
    end

  end
end
