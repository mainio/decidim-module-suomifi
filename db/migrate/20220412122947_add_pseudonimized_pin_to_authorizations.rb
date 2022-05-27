# frozen_string_literal: true

class AddPseudonimizedPinToAuthorizations < ActiveRecord::Migration[6.0]
  def change
    add_column :decidim_authorizations, :pseudonymized_pin, :string, index: true
  end
end
