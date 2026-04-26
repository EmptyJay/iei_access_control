Rails.application.routes.draw do
  root "dashboard#index"

  get    "login",  to: "sessions#new",     as: :login
  post   "login",  to: "sessions#create"
  delete "logout", to: "sessions#destroy", as: :logout

  get  "users/import",      to: "users#import_form",  as: :import_users
  post "users/import",      to: "users#import"
  get  "users/export",      to: "users#export",       as: :export_users
  post "users/bulk_update", to: "users#bulk_update",  as: :bulk_update_users
  resources :users
  resources :access_events, only: [ :index ]
  resource  :settings, only: [ :edit, :update ]

  post "lockdown", to: "dashboard#lockdown", as: :lockdown
  post "restore",  to: "dashboard#restore",  as: :restore

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check
end
