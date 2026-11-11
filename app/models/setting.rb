# One value per key, encrypted at rest. Read with Setting.get, which never raises: a missing table (before migrations), a missing
# row or a value that can no longer be decrypted (SECRET_KEY_BASE changed) all read as the default.
class Setting < ApplicationRecord
  encrypts :value

  validates :key, presence: true, uniqueness: true

  class << self
    def get(key, default = nil)
      find_by(key: key.to_s)&.value.presence || default
    rescue ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid, ActiveRecord::Encryption::Errors::Base
      default
    end

    def set(key, value)
      return delete(key) if value.blank?

      record = find_or_initialize_by(key: key.to_s)
      record.update!(value: value.to_s)
      value
    rescue ActiveRecord::RecordNotUnique
      retry
    end

    def delete(key)
      where(key: key.to_s).destroy_all
      nil
    end
  end
end
