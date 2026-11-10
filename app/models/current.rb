class Current < ActiveSupport::CurrentAttributes
  attribute :session, :local_user

  # Signed in (multi-user mode) or the built-in local user (single-user mode, the default for self-hosting).
  def user = session&.user || local_user
end
