# -*- encoding: binary -*-
module Rainbows
  module Fiber

    # A partially complete IO wrapper, this exports an IO.select()-able
    # #to_io method and gives users the illusion of a synchronous
    # interface that yields away from the current Fiber whenever
    # the underlying IO object cannot read or write
    class IO < Struct.new(:to_io, :f)

      # for wrapping output response bodies
      def each(&block)
        begin
          yield readpartial(16384)
        rescue EOFError
          break
        end while true
        self
      end

      def close
        to_io.close
      end

      def write(buf)
        begin
          (w = to_io.write_nonblock(buf)) == buf.size and return
          buf = buf[w..-1]
        rescue Errno::EAGAIN
          WR[self] = false
          ::Fiber.yield
          WR.delete(self)
          retry
        end while true
      end

      # used for reading headers (respecting keepalive_timeout)
      def read_timeout
        expire = false
        begin
          to_io.read_nonblock(16384)
        rescue Errno::EAGAIN
          return if expire && expire < Time.now
          RD[self] = false
          expire = Time.now + G.kato
          ::Fiber.yield
          RD.delete(self)
          retry
        end
      end

      def readpartial(length, buf = "")
        begin
          to_io.read_nonblock(length, buf)
        rescue Errno::EAGAIN
          RD[self] = false
          ::Fiber.yield
          RD.delete(self)
          retry
        end
      end

    end
  end
end
