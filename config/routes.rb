Rails.application.routes.draw do
  resource :session
  resources :passwords, param: :token
  resource :registration, only: %i[new create]
  resource :preferences, only: :update
  patch "books", to: "books#update", as: :books
  resources :saved_filters, only: %i[create destroy]
  resources :picks, only: %i[index create destroy]

  root to: redirect("/nba/props")

  scope "/:league", constraints: { league: Regexp.union(League.keys) }, as: :league do
    resources :props, only: :index do
      get :count, on: :collection
    end
    get "props/:market_id/:side", to: "props#show", as: :prop, constraints: { market_id: /\d+/, side: /over|under/ }
    resources :games, only: %i[index show]
    resources :insights, only: :index
    get "ev", to: "ev#index", as: :ev
    get "arbitrage", to: "arbitrage#index", as: :arbitrage
  end

  get "styleguide" => "styleguide#show" unless Rails.env.production?

  get "up" => "rails/health#show", as: :rails_health_check
end
