# frozen_string_literal: true

class EmailValidator < ActiveModel::EachValidator
  DOMAIN_RESTRICTION_REGEXPS = LruRedux::ThreadSafeCache.new(32)
  private_constant :DOMAIN_RESTRICTION_REGEXPS

  def validate_each(record, attribute, value)
    if value.blank?
      record.errors.add(attribute, I18n.t(:"user.email.blank"))
      invalid = true
    elsif !EmailAddressValidator.valid_value?(value)
      if Invite === record && attribute == :email
        record.errors.add(:base, I18n.t(:"invite.invalid_email", email: CGI.escapeHTML(value)))
      else
        record.errors.add(attribute, I18n.t(:"user.email.invalid"))
      end
      invalid = true
    end

    if !EmailValidator.allowed?(value)
      record.errors.add(attribute, I18n.t(:"user.email.not_allowed"))
      invalid = true
    end

    if !invalid && ScreenedEmail.should_block?(value)
      record.errors.add(attribute, I18n.t(:"user.email.blocked"))
    end
  end

  def self.allowed?(email)
    if (setting = SiteSetting.allowed_email_domains).present?
      return email_in_restriction_setting?(setting, email) || is_developer?(email)
    elsif (setting = SiteSetting.blocked_email_domains).present?
      return !(email_in_restriction_setting?(setting, email) && !is_developer?(email))
    end

    true
  end

  def self.can_auto_approve_user?(email)
    if (setting = SiteSetting.auto_approve_email_domains).present?
      return !!(EmailValidator.allowed?(email) && email_in_restriction_setting?(setting, email))
    end

    false
  end

  def self.email_in_restriction_setting?(setting, value)
    value =~ domain_restriction_regexp(setting)
  end

  def self.domain_restriction_regexp(setting)
    key = setting.frozen? ? setting : setting.dup.freeze
    DOMAIN_RESTRICTION_REGEXPS.getset(key) do
      domains = key.gsub(".", '\.')
      Regexp.new("@(.+\\.)?(#{domains})$", true)
    end
  end
  private_class_method :domain_restriction_regexp

  def self.is_developer?(value)
    Developer.configured_email?(value)
  end
end
