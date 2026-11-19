# frozen_string_literal: true

require "rails_helper"

RSpec.describe Live::StageRoles do
  fab!(:admin)
  fab!(:owner, :user)
  fab!(:listener, :user)
  fab!(:permanent_speaker, :user)
  fab!(:private_member, :user)
  fab!(:room) do
    Fabricate(:live_room, creator: owner, public: true, room_type: Live::Room::ROOM_TYPE_STAGE)
  end
  fab!(:private_room) do
    Fabricate(:live_room, creator: owner, public: false, room_type: Live::Room::ROOM_TYPE_STAGE)
  end

  before do
    SiteSetting.live_enabled = true
    SiteSetting.live_allowed_groups = "#{Group::AUTO_GROUPS[:logged_in_users]}"
  end

  after do
    Live::ParticipantTracker.clear(room.id)
    Live::ParticipantTracker.clear(private_room.id)
  end

  describe ".effective_role" do
    it "treats a site admin without an explicit membership as a moderator in stage rooms" do
      expect(described_class.effective_role(room, admin)).to eq("moderator")
    end

    it "returns participant for a regular user without a membership" do
      expect(described_class.effective_role(room, listener)).to eq("participant")
    end

    it "returns speaker for a user with a speaker membership" do
      room.room_memberships.create!(
        user: permanent_speaker,
        role: Live::RoomMembership::ROLE_SPEAKER,
      )
      expect(described_class.effective_role(room, permanent_speaker)).to eq("speaker")
    end
  end

  describe ".assign_role! and .revert_session_speakers!" do
    it "creates a session-only speaker and removes the row when reverted" do
      membership =
        described_class.assign_role!(
          room,
          listener,
          role: Live::RoomMembership::ROLE_SPEAKER,
          session_only: true,
        )

      expect(membership).to be_speaker
      expect(membership).to be_session_only
      expect(membership.fallback_role).to be_nil

      described_class.revert_session_speakers!(room)

      expect(room.room_memberships.find_by(user: listener)).to be_nil
    end

    it "preserves a private room participant fallback role and restores it on revert" do
      private_room.room_memberships.create!(
        user: private_member,
        role: Live::RoomMembership::ROLE_PARTICIPANT,
      )

      membership =
        described_class.assign_role!(
          private_room,
          private_member,
          role: Live::RoomMembership::ROLE_SPEAKER,
          session_only: true,
        )

      expect(membership).to be_speaker
      expect(membership).to be_session_only
      expect(membership.fallback_role).to eq(Live::RoomMembership::ROLE_PARTICIPANT)

      described_class.revert_session_speakers!(private_room)

      restored = private_room.room_memberships.find_by(user: private_member)
      expect(restored).to be_present
      expect(restored).to be_participant
      expect(restored).not_to be_session_only
      expect(restored.fallback_role).to be_nil
    end

    it "never downgrades a permanent speaker or moderator to session-only" do
      perm =
        room.room_memberships.create!(
          user: permanent_speaker,
          role: Live::RoomMembership::ROLE_SPEAKER,
        )

      described_class.assign_role!(
        room,
        permanent_speaker,
        role: Live::RoomMembership::ROLE_SPEAKER,
        session_only: true,
      )

      expect(perm.reload).to be_speaker
      expect(perm).not_to be_session_only

      described_class.revert_session_speakers!(room)
      expect(perm.reload).to be_speaker
    end
  end

  describe "demotion media cleanup" do
    it "immediately resets muted, video, and screen share metadata when demoting a present speaker" do
      membership =
        described_class.assign_role!(
          room,
          listener,
          role: Live::RoomMembership::ROLE_SPEAKER,
          session_only: true,
        )
      Live::ParticipantTracker.add(room.id, listener.id)
      Live::ParticipantTracker.update_metadata(
        room.id,
        listener.id,
        role: "speaker",
        is_muted: false,
        is_video_on: true,
        is_screen_sharing: true,
      )

      described_class.update_membership!(
        room,
        membership,
        role: Live::RoomMembership::ROLE_PARTICIPANT,
      )

      metadata = Live::ParticipantTracker.get_metadata(room.id, listener.id)
      expect(metadata[:role]).to eq("participant")
      expect(metadata[:is_muted]).to eq(true)
      expect(metadata[:is_video_on]).to eq(false)
      expect(metadata[:is_screen_sharing]).to eq(false)
    end
  end

  describe ".step_down!" do
    it "reverts a session-only speaker and resets their media state" do
      described_class.assign_role!(
        room,
        listener,
        role: Live::RoomMembership::ROLE_SPEAKER,
        session_only: true,
      )
      Live::ParticipantTracker.add(room.id, listener.id)
      Live::ParticipantTracker.update_metadata(
        room.id,
        listener.id,
        role: "speaker",
        is_muted: false,
        is_video_on: true,
      )

      messages =
        MessageBus.track_publish(Live.room_channel(room.id)) do
          described_class.step_down!(room, listener)
        end

      expect(room.room_memberships.find_by(user: listener)).to be_nil
      metadata = Live::ParticipantTracker.get_metadata(room.id, listener.id)
      expect(metadata[:role]).to eq("participant")
      expect(metadata[:is_muted]).to eq(true)
      expect(metadata[:is_video_on]).to eq(false)
      expect(
        messages.any? { |m| m.data[:type] == "role_change" && m.data[:role] == "participant" },
      ).to eq(true)
    end
  end

  describe ".mute_participant!" do
    it "sets is_muted and broadcasts force_mute without making LiveKit calls on mesh" do
      Live::ParticipantTracker.pin_transport!(room.id, "mesh")
      Live::ParticipantTracker.add(room.id, listener.id)
      Live::ParticipantTracker.update_metadata(
        room.id,
        listener.id,
        role: "speaker",
        is_muted: false,
      )

      messages =
        MessageBus.track_publish(Live.room_channel(room.id)) do
          described_class.mute_participant!(room, listener, acting_user: owner)
        end

      expect(Live::ParticipantTracker.get_metadata(room.id, listener.id)[:is_muted]).to eq(true)
      force_mute = messages.find { |m| m.data[:type] == "force_mute" }
      expect(force_mute).to be_present
      expect(force_mute.data[:user_id]).to eq(listener.id)
      expect(force_mute.user_ids).to eq([listener.id])
    end

    it "mutes published microphone tracks on LiveKit when pinned to livekit" do
      SiteSetting.live_livekit_url = "wss://livekit.example.com"
      SiteSetting.live_livekit_api_key = "lk_key"
      SiteSetting.live_livekit_api_secret = "lk_secret"
      Live::ParticipantTracker.pin_transport!(room.id, "livekit")
      Live::ParticipantTracker.add(room.id, listener.id)

      get_stub =
        stub_request(
          :post,
          "https://livekit.example.com/twirp/livekit.RoomService/GetParticipant",
        ).to_return(
          status: 200,
          body: {
            identity: listener.id.to_s,
            tracks: [
              { sid: "TR_mic1", type: "AUDIO", source: "MICROPHONE", muted: false },
              { sid: "TR_cam1", type: "VIDEO", source: "CAMERA", muted: false },
            ],
          }.to_json,
        )
      mute_stub =
        stub_request(
          :post,
          "https://livekit.example.com/twirp/livekit.RoomService/MutePublishedTrack",
        )
          .with do |req|
            body = JSON.parse(req.body)
            body["identity"] == listener.id.to_s && body["track_sid"] == "TR_mic1" &&
              body["muted"] == true
          end
          .to_return(status: 200, body: "{}")

      described_class.mute_participant!(room, listener, acting_user: owner)

      expect(get_stub).to have_been_requested.once
      expect(mute_stub).to have_been_requested.once
    end
  end

  describe ".sync_room_type_change!" do
    it "resets non-speaker media metadata when switching open to stage" do
      open_room =
        Fabricate(:live_room, creator: owner, public: true, room_type: Live::Room::ROOM_TYPE_OPEN)
      Live::ParticipantTracker.add(open_room.id, listener.id)
      Live::ParticipantTracker.update_metadata(
        open_room.id,
        listener.id,
        role: "participant",
        is_muted: false,
        is_video_on: true,
        is_screen_sharing: true,
      )

      open_room.update!(room_type: Live::Room::ROOM_TYPE_STAGE)
      described_class.sync_room_type_change!(open_room)

      metadata = Live::ParticipantTracker.get_metadata(open_room.id, listener.id)
      expect(metadata[:is_muted]).to eq(true)
      expect(metadata[:is_video_on]).to eq(false)
      expect(metadata[:is_screen_sharing]).to eq(false)
    ensure
      Live::ParticipantTracker.clear(open_room.id)
    end

    it "clears raised hands, invitations, and session speakers when switching stage to open" do
      Live::ParticipantTracker.add(room.id, listener.id)
      Live::ParticipantTracker.raise_hand(room.id, listener.id)
      Live::ParticipantTracker.set_speak_invitation(room.id, listener.id, inviter: owner)
      described_class.assign_role!(
        room,
        permanent_speaker,
        role: Live::RoomMembership::ROLE_SPEAKER,
        session_only: true,
      )

      room.update!(room_type: Live::Room::ROOM_TYPE_OPEN)
      described_class.sync_room_type_change!(room)

      metadata = Live::ParticipantTracker.get_metadata(room.id, listener.id)
      expect(metadata[:hand_raised_at]).to be_nil
      expect(metadata[:speak_invited_at]).to be_nil
      expect(Live::ParticipantTracker.speak_invitation(room.id, listener.id)).to be_nil
      expect(room.room_memberships.find_by(user: permanent_speaker)).to be_nil
    end
  end
end
