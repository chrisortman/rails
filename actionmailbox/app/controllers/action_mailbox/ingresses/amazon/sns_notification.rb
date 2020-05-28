# frozen_string_literal: true

module ActionMailbox
  module Ingresses
    module Amazon
      class SnsNotification
        def initialize(params)
          @params = params
        end

        def subscription_confirmed?
          confirmation_response.code&.start_with?("2")
        end

        def verified?
          require "aws-sdk-sns"
          Aws::SNS::MessageVerifier.new.authentic?(params.to_json)
        end

        def topic
          params[:TopicArn]
        end

        def message_content
          message["content"] if receipt?
        end

        private
          attr_reader :params

          def message
            @message ||= JSON.parse(params[:Message])
          end

          def receipt?
            params[:Type] == "Notification" && message["notificationType"] == "Received"
          end

          def confirmation_response
            @confirmation_response ||= Net::HTTP.get_response(URI(params[:SubscribeURL]))
          end
      end
    end
  end
end
