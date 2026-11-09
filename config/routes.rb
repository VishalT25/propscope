Rails.application.routes.draw do
  resource :session
  resources :passwords, param: :token
  resource :registration, only: %i[new create]
  resource :preferences, only: :update

  root to: redirect("/nba/props")

  scope "/:league", constraints: { league: Regexp.union(League.keys) }, as: :league do
    resources :props, only: :index
    resources :games, only: :index
    resources :insights, only: :index
  end

  get "styleguide" => "styleguide#show" unless Rails.env.production?

  get "up" => "rails/health#show", as: :rails_health_check
end
