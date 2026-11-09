# Normalizes person/team names for cross-provider matching:
# downcase, strip accents/punctuation, drop suffixes (Jr., III...), hyphens become spaces, common nicknames unified.
class NameNormalizer
  SUFFIXES = %w[jr sr ii iii iv v].freeze
  NICKNAMES = { "mike" => "michael", "nic" => "nicolas", "nick" => "nicolas", "cam" => "cameron",
                "kj" => "kenyon", "pj" => "paul", "tj" => "thomas", "moe" => "maurice", "zach" => "zachary" }.freeze

  def self.call(name)
    ascii = I18n.transliterate(name.to_s).downcase
    tokens = ascii.gsub(/['’`".]/, "").gsub(/[^a-z0-9\s]/, " ").split
    tokens.pop while tokens.size > 1 && SUFFIXES.include?(tokens.last)
    tokens[0] = NICKNAMES.fetch(tokens[0], tokens[0]) if tokens.size > 1
    tokens.join(" ")
  end
end
