# frozen_string_literal: true

class AddSessionOnlyToLiveRoomMemberships < ActiveRecord::Migration[7.2]
  def change
    add_column :live_room_memberships, :session_only, :boolean, default: false, null: false
    add_column :live_room_memberships, :fallback_role, :integer
  end
end
