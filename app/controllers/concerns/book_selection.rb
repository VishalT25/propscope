# Which books count toward "best price". Stored on the user, or in a cookie for guests. nil = every book.
module BookSelection
  extend ActiveSupport::Concern

  included { helper_method :enabled_book_keys, :all_bookmakers, :books_all_enabled? }

  private

  def all_bookmakers = @all_bookmakers ||= Bookmaker.order(:name).to_a

  def enabled_book_keys
    keys = Current.user ? Current.user.enabled_bookmaker_keys : parse_cookie_keys
    keys.is_a?(Array) ? keys & all_bookmakers.map(&:key) : nil
  end

  def books_all_enabled? = enabled_book_keys.nil?

  # nil means "all books" (no filtering in SQL)
  def enabled_bookmaker_ids
    keys = enabled_book_keys
    keys && all_bookmakers.select { |b| keys.include?(b.key) }.map(&:id)
  end

  def parse_cookie_keys
    JSON.parse(cookies[:enabled_books].to_s)
  rescue JSON::ParserError
    nil
  end

  def save_book_keys(keys)
    value = keys.sort == all_bookmakers.map(&:key).sort ? nil : keys
    cookies.permanent[:enabled_books] = { value: value.to_json, same_site: :lax }
    Current.user&.update!(enabled_bookmaker_keys: value)
  end
end
