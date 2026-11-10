module Ev
  # The "true" probability of each side of a two-way market.
  #   sharp     : if a sharp book (bookmakers.sharp) quotes both sides, remove its vig and use that.
  #   consensus : otherwise average the no-vig probability across every book quoting both sides (needs `min_books`).
  # The free data tier has no sharp book, so in practice this is the consensus.
  class FairPrice
    METHODS = %w[multiplicative power].freeze
    Result = Data.define(:left, :right, :kind, :book_ids, :per_book)

    def self.call(**) = new(**).call

    def initialize(pair:, method: "multiplicative", min_books: 3, sharp_book_ids: [])
      @pair, @method, @min_books, @sharp = pair, METHODS.include?(method) ? method : "multiplicative", min_books, sharp_book_ids
    end

    def call
      lefts = @pair.left_snaps.index_by(&:bookmaker_id)
      rights = @pair.right_snaps.index_by(&:bookmaker_id)
      per_book = per_book_fair(lefts, rights)
      sharp = per_book.slice(*@sharp)
      reference, kind = if sharp.any? then [ sharp, :sharp ] elsif per_book.size >= @min_books then [ per_book, :consensus ] end
      return nil unless reference

      left = (reference.values.sum / reference.size).round(6)
      Result.new(left: left, right: BigDecimal(1) - left, kind: kind, book_ids: reference.keys, per_book: per_book)
    end

    private

    # Multiplicative is cheap. Power solves an equation per book (milliseconds each), so it is cached against the exact
    # snapshots it was computed from: a new price means a new snapshot id, which means a new key.
    def per_book_fair(lefts, rights)
      compute = ->(*) { (lefts.keys & rights.keys).to_h { |id| [ id, devig(lefts[id], rights[id]) ] } }
      return compute.call unless @method == "power"

      key = [ "fair-power", (lefts.keys & rights.keys).sort.map { |id| [ lefts[id].id, rights[id].id ] } ].flatten.join("-")
      Rails.cache.fetch("ev/#{Digest::SHA256.hexdigest(key)}", expires_in: 1.day, &compute)
    end

    # No-vig probability of the left side from one book's two prices.
    def devig(left, right)
      OddsMath::Devig.public_send(@method, [ OddsMath.american_to_implied(left.american_odds), OddsMath.american_to_implied(right.american_odds) ]).first
    end
  end
end
