Rails.application.routes.draw do
  root "dashboard#index"

  get  "setup", to: "setup#new",    as: :setup
  post "setup", to: "setup#create"

  get    "login",  to: "sessions#new",     as: :login
  post   "login",  to: "sessions#create"
  delete "logout", to: "sessions#destroy", as: :logout

  resources :admins, except: [ :show, :destroy ]

  get  "users/import",      to: "users#import_form",  as: :import_users
  post "users/import",      to: "users#import"
  get  "users/export",      to: "users#export",       as: :export_users
  post "users/bulk_update", to: "users#bulk_update",  as: :bulk_update_users
  resources :users
  resources :access_events, only: [ :index ] do
    collection do
      post :fetch
      get  :export
    end
  end
  resource  :settings, only: [ :edit, :update ]

  post "sync_users",  to: "dashboard#sync_users",  as: :sync_users
  post "lockdown",    to: "dashboard#lockdown",    as: :lockdown
  post "restore",     to: "dashboard#restore",     as: :restore
  post "clear_users",       to: "dashboard#clear_users",       as: :clear_users
  post "force_clear_users", to: "dashboard#force_clear_users", as: :force_clear_users

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check
end
