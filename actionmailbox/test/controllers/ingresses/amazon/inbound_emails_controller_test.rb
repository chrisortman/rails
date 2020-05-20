# frozen_string_literal: true

require "test_helper"

class ActionMailbox::Ingresses::Amazon::InboundEmailsControllerTest < ActionDispatch::IntegrationTest
  def fixture(name)
    file_fixture("../files/amazon/#{name}").read
  end

  setup do
    ActionMailbox.ingress = :amazon
    ActionMailbox.amazon = ActiveSupport::OrderedOptions.new
    ActionMailbox.amazon.subscribed_topics = %w(
      arn:aws:sns:eu-west-1:111111111111:example-topic
      arn:aws:sns:eu-west-1:111111111111:recognized-topic
    )
    pem_url = "https://sns.eu-west-1.amazonaws.com/SimpleNotificationService-a86cb10b4e1f29c941702d737128f7b6.pem"
    stub_request(:get, pem_url).and_return(body: fixture("certificate.pem"))
    @inbound = fixture("inbound_email.json")
    @invalid_signature = fixture("invalid_signature.json")
    @valid_signature = fixture("valid_signature.json")
    @recognized_topic = fixture("recognized_topic_subscription_request.json")
    @unrecognized_topic = fixture("unrecognized_topic_subscription_request.json")
  end

  test "receiving an inbound email from Amazon" do
    assert_difference -> { ActionMailbox::InboundEmail.count }, +1 do
      post rails_amazon_inbound_emails_url, params: @inbound
    end

    assert_response :no_content

    inbound_email = ActionMailbox::InboundEmail.last
    content = JSON.parse(JSON.parse(@inbound)["Message"])["content"]
    assert_equal inbound_email.raw_email.download, content
    id = "CA+X1WqWD+ZHUimo+gm+=TZt7haLJv9G7LjG4M-wu5ka=CwxpYQ@mail.gmail.com"
    assert_equal inbound_email.message_id, id
  end

  test "accepting subscriptions to recognized topics" do
    params = {
      Action: "ConfirmSubscription",
      Token: "abcd1234" * 32,
      TopicArn: "arn:aws:sns:eu-west-1:111111111111:recognized-topic"
    }
    query = Rack::Utils.build_query(params)
    request = stub_request(:get, "https://sns.eu-west-1.amazonaws.com/?#{query}")
    post rails_amazon_inbound_emails_url, params: @recognized_topic
    assert_requested request
  end

  test "rejecting subscriptions to unrecognized topics" do
    url = %r{https://sns.eu-west-1.amazonaws.com/\?Action=ConfirmSubscription}
    request = stub_request(:get, url)
    post rails_amazon_inbound_emails_url, params: @unrecognized_topic
    assert_not_requested request
  end

  test "rejecting subscriptions with invalid signatures" do
    url = %r{https://sns.eu-west-1.amazonaws.com/\?Action=ConfirmSubscription}
    request = stub_request(:get, url)
    post rails_amazon_inbound_emails_url, params: @invalid_signature
    assert_not_requested request
  end

  test "accepting subscriptions with valid signatures" do
    url = %r{https://sns.eu-west-1.amazonaws.com/\?Action=ConfirmSubscription}
    request = stub_request(:get, url)
    post rails_amazon_inbound_emails_url, params: @valid_signature
    assert_requested request
  end
end
