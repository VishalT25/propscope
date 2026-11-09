class BooksController < PublicController
  def update
    keys = Array(params[:keys]).map(&:to_s) & all_bookmakers.map(&:key)
    if keys.empty?
      redirect_back_or_to root_path, alert: "Keep at least one book enabled.", status: :see_other
    else
      save_book_keys(keys)
      redirect_back_or_to root_path, status: :see_other
    end
  end
end
