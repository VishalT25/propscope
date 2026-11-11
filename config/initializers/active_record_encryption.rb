# Keys for Rails' built-in attribute encryption, used for the API keys a person enters in Settings (Setting#value).
# By default they are derived from SECRET_KEY_BASE, so a self-hosted install needs nothing extra; set the
# ACTIVE_RECORD_ENCRYPTION_* variables to use your own. If SECRET_KEY_BASE changes, stored keys can no longer be read
# and the app simply asks for them again (see Setting.get).
derive = ->(name) { Rails.application.key_generator.generate_key("propscope/active_record_encryption/#{name}", 32).unpack1("H*") }

ActiveRecord::Encryption.configure(
  primary_key: ENV["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"].presence || derive.call("primary"),
  deterministic_key: ENV["ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY"].presence || derive.call("deterministic"),
  key_derivation_salt: ENV["ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT"].presence || derive.call("salt")
)
