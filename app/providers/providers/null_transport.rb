module Providers
  class NullTransport
    def metered? = false
    def get(*) = raise("NullTransport cannot fetch; it is for replaying stored payloads")
  end
end
