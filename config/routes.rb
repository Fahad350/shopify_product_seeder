Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  resource :settings, only: %i[edit update] do
    post :test_connection
  end

  resources :product_seeds, only: %i[index create]
  resources :products, only: %i[index show]

  root "product_seeds#index"
end
