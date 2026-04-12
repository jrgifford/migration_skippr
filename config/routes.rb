# frozen_string_literal: true

MigrationSkippr::Engine.routes.draw do
  resources :databases, only: [:index, :show], param: :name do
    resources :migrations, only: [:create], param: :version do
      member do
        post :skip
        post :unskip
      end
    end
  end

  root to: "databases#index"
end
