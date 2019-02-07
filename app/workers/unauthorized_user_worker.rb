# frozen_string_literal: true

class UnauthorizedUserWorker
  include Sidekiq::Worker

  REVOKED_MESSAGES = ["O token de acesso foi revogado", "The access token was revoked"]

  def perform(id)
    @user = User.find(id)
    check_twitter_credentials
    check_mastodon_credentials

    @user.locked = false
    @user.save
  rescue ActiveRecord::RecordNotFound
    Rails.logger.debug { "User not found, ignoring" }
  end

  private
    def check_twitter_credentials
      if @user.twitter
        begin
          @user.twitter_client.verify_credentials
        rescue Twitter::Error::Unauthorized => ex
          if ex.code == 89
            @user.twitter.destroy
            stop_crossposting
          end
        end
      end
    end

    def check_mastodon_credentials
      if @user.mastodon
        begin
          @user.mastodon_client.verify_credentials
        rescue Mastodon::Error::Unauthorized => ex
          # XXX look into this. There should be a code or machine-readable error field
          if REVOKED_MESSAGES.include? ex.message
            @user.mastodon.destroy
            stop_crossposting
          end
        end
      end
    end

    def stop_crossposting
      @user.posting_from_twitter = @user.posting_from_mastodon = false
      @user.save
    end
end
