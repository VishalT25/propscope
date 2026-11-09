# Base for pages that guests can browse (everything read-only).
class PublicController < ApplicationController
  allow_unauthenticated_access
end
