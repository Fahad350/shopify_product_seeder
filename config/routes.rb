Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  resource :settings, only: %i[edit update] do
    post :test_connection
  end

  root to: redirect("/settings/edit")
end
