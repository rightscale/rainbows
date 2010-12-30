# -*- encoding: binary -*-
# :enddoc:
module Rainbows::Coolio::Core
  include Rainbows::Base

  # runs inside each forked worker, this sits around and waits
  # for connections and doesn't die until the parent dies (or is
  # given a INT, QUIT, or TERM signal)
  def worker_loop(worker)
    Rainbows::Response.setup(Rainbows::Coolio::Client)
    require 'rainbows/coolio/sendfile'
    Rainbows::Coolio::Client.__send__(:include, Rainbows::Coolio::Sendfile)
    init_worker_process(worker)
    mod = Rainbows.const_get(@use)
    rloop = Rainbows::Coolio::Server.const_set(:LOOP, Coolio::Loop.default)
    Rainbows::Coolio::Client.const_set(:LOOP, rloop)
    Rainbows::Coolio::Server.const_set(:MAX, @worker_connections)
    Rainbows::Coolio::Server.const_set(:CL, mod.const_get(:Client))
    Rainbows::EvCore.const_set(:APP, G.server.app)
    Rainbows::EvCore.setup
    Rainbows::Coolio::Heartbeat.new(1, true).attach(rloop)
    LISTENERS.map! { |s| Rainbows::Coolio::Server.new(s).attach(rloop) }
    rloop.run
  end
end