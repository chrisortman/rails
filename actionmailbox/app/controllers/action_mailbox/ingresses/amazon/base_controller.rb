# frozen_string_literal: true

module ActionMailbox
  module Ingresses
    module Amazon
      class BaseController < ActionMailbox::BaseController
        before_action :set_notification, :ensure_valid_topic, :ensure_verified

        def ingress_name
          :amazon
        end

        private
          def set_notification
            @notification = SnsNotification.new params.except(:controller, :action)
          end

          def ensure_valid_topic
            unless @notification.topic.in? Array(ActionMailbox.amazon.subscribed_topics)
              Rails.logger.warn "Ignoring unknown topic: #{@notification.topic}"
              head :unauthorized
            end
          end

          def ensure_verified
            head :unauthorized unless @notification.verified?
          end
      end
    end
  end
end
