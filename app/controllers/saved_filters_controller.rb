class SavedFiltersController < ApplicationController
  def create
    filter = current_user.saved_filters.new(name: params[:name].to_s.strip, scope: "props",
                                            params: PropsQuery::Filters.from_params(params).to_query.stringify_keys)
    if filter.save
      redirect_to league_props_path(League.default, filter.params.symbolize_keys), notice: "Saved “#{filter.name}”.", status: :see_other
    else
      redirect_back_or_to root_path, alert: "Give the filter a name.", status: :see_other
    end
  end

  def destroy
    current_user.saved_filters.find(params[:id]).destroy
    redirect_back_or_to root_path, status: :see_other
  end
end
