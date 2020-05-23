# frozen_string_literal: true

module ActionMailbox
  # Ingests inbound emails from Amazon SES/SNS and confirms subscriptions.
  #
  # Subscription requests must provide the following parameters in a JSON body:
  # - +Message+: Notification content
  # - +MessageId+: Notification unique identifier
  # - +Timestamp+: iso8601 timestamp
  # - +TopicArn+: Topic identifier
  # - +Type+: Type of event ("SubscriptionConfirmation")
  #
  # Inbound email events must provide the following parameters in a JSON body:
  # - +Message+: Notification content
  # - +MessageId+: Notification unique identifier
  # - +Timestamp+: iso8601 timestamp
  # - +TopicArn+: Topic identifier
  # - +Type+: Type of event ("Notification")
  #
  # All requests are authenticated by validating the provided AWS signature.
  #
  # Returns:
  #
  # - <tt>204 No Content</tt> if a request is successfully processed
  # - <tt>401 Unauthorized</tt> if a request does not contain a valid signature
  # - <tt>404 Not Found</tt> if the Amazon ingress has not been configured
  # - <tt>422 Unprocessable Entity</tt> if a request provides invalid parameters
  #
  # == Usage
  #
  # 1. {Configure SES}[https://docs.aws.amazon.com/ses/latest/DeveloperGuide/receiving-email-notifications.html] to route emails through SNS. Take note of the topic unique reference (+TopicArn+).
  #
  #    {Configure SNS}[https://docs.aws.amazon.com/ses/latest/DeveloperGuide/receiving-email-action-sns.html] to send notifications to +/rails/action_mailbox/amazon/inbound_emails+.
  #
  #    If your application is found at <tt>https://example.com</tt> you would specify the fully-qualified URL <tt>https://example.com/rails/action_mailbox/amazon/inbound_emails</tt>.
  #
  # 2. Install the {aws-sdk-sns}[https://rubygems.org/gems/aws-sdk-sns] gem:
  #
  #        # Gemfile
  #        gem "aws-sdk-sns", "~> 1.9", require: false
  #
  # 3. Tell Action Mailbox to accept notifications from Amazon:
  #
  #        # config/environments/production.rb
  #        config.action_mailbox.ingress = :amazon
  #
  # 4. Configure which SNS topics will be accepted:
  #
  #        config.action_mailbox.amazon.subscribed_topics = %w(
  #          arn:aws:sns:eu-west-1:123456789001:example-topic-1
  #          arn:aws:sns:us-east-1:123456789002:example-topic-2
  #        )
  #
  # Your application is now ready to accept confirmation requests and email notifications.
  #
  module Ingresses
    module Amazon
      class InboundEmailsController < ActionMailbox::BaseController
        before_action :verify_authenticity
        before_action :validate_topic
        before_action :confirm_subscription

        def create
          head :bad_request unless mail.present?

          ActionMailbox::InboundEmail.create_and_extract_message_id!(mail)
          head :no_content
        end

        private
          def verify_authenticity
            head :bad_request unless notification.present?
            head :unauthorized unless verified?
          end

          def confirm_subscription
            return unless notification["Type"] == "SubscriptionConfirmation"
            return head :ok if confirmation_response_code&.start_with?("2")

            Rails.logger.error("SNS subscription confirmation request rejected.")
            head :unprocessable_entity
          end

          def validate_topic
            return if valid_topics&.include?(topic)

            Rails.logger.warn("Ignoring unknown topic: #{topic}")
            head :unauthorized
          end

          def confirmation_response_code
            @confirmation_response_code ||= begin
              Net::HTTP.get_response(URI(notification["SubscribeURL"])).code
            end
          end

          def notification
            @notification ||= JSON.parse(request.body.read)
          rescue JSON::ParserError => e
            Rails.logger.warn("Unable to parse SNS notification: #{e}")
            nil
          end

          def verified?
            verifier.authentic?(@notification.to_json)
          end

          def verifier
            require "aws-sdk-sns"
            Aws::SNS::MessageVerifier.new
          end

          def message
            @message ||= JSON.parse(notification["Message"])
          end

          def mail
            return nil unless notification["Type"] == "Notification"
            return nil unless message["notificationType"] == "Received"

            message["content"]
          end

          def topic
            return nil unless notification.present?

            notification["TopicArn"]
          end

          def valid_topics
            ActionMailbox.amazon.subscribed_topics
          end
      end
    end
  end
end
