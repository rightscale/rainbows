# -*- encoding: binary -*-

module Rainbows

  # Rack response middleware wrapping any IO-like object with an
  # OS-level file descriptor associated with it.  May also be used to
  # create responses from integer file descriptors or existing +IO+
  # objects.  This may be used in conjunction with the #to_path method
  # on servers that support it to pass arbitrary file descriptors into
  # the HTTP response without additional open(2) syscalls

  class DevFdResponse < Struct.new(:app, :to_io, :to_path)
    include Rack::Utils

    # Rack middleware entry point, we'll just pass through responses
    # unless they respond to +to_io+ or +to_path+
    def call(env)
      status, headers, body = response = app.call(env)

      # totally uninteresting to us if there's no body
      return response if STATUS_WITH_NO_ENTITY_BODY.include?(status)

      io = body.to_io if body.respond_to?(:to_io)
      io ||= File.open(body.to_path, 'rb') if body.respond_to?(:to_path)
      return response if io.nil?

      headers = HeaderHash.new(headers)
      st = io.stat
      if st.file?
        headers['Content-Length'] ||= st.size.to_s
        headers.delete('Transfer-Encoding')
      elsif st.pipe? || st.socket? # epoll-able things
        if env['rainbows.autochunk']
          headers['Transfer-Encoding'] = 'chunked'
          headers.delete('Content-Length')
        else
          headers['X-Rainbows-Autochunk'] = 'no'
        end

        # we need to make sure our pipe output is Fiber-compatible
        env["rainbows.model"] == :FiberSpawn and
          return [ status, headers.to_hash, Fiber::IO.new(io,::Fiber.current) ]
      else # unlikely, char/block device file, directory, ...
        return response
      end
      resp = dup # be reentrant here
      resp.to_path = "/dev/fd/#{io.fileno}"
      resp.to_io = io
      [ status, headers.to_hash, resp ]
    end

    # called by the webserver or other middlewares if they can't
    # handle #to_path
    def each(&block)
      to_io.each(&block)
    end

    # remain Rack::Lint-compatible for people with wonky systems :P
    unless File.exist?("/dev/fd/0")
      alias to_path_orig to_path
      undef_method :to_path
    end

    # called by the web server after #each
    def close
      begin
        to_io.close if to_io.respond_to?(:close)
      rescue IOError # could've been IO::new()'ed and closed
      end
    end

  end # class
end
