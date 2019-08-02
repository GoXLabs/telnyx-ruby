# frozen_string_literal: true

require "openssl"
require "base64"
require "ed25519"

module Telnyx
  module Webhook
    DEFAULT_TOLERANCE = 300

    # Initializes an Event object from a JSON payload.
    #
    # This may raise JSON::ParserError if the payload is not valid JSON, or
    # SignatureVerificationError if the signature verification fails.
    def self.construct_event(payload, signature_header, timestamp_header, tolerance: DEFAULT_TOLERANCE)
      Signature.verify(payload, signature_header, timestamp_header, tolerance: tolerance)

      # It's a good idea to parse the payload only after verifying it. We use
      # `symbolize_names` so it would otherwise be technically possible to
      # flood a target's memory if they were on an older version of Ruby that
      # doesn't GC symbols. It also decreases the likelihood that we receive a
      # bad payload that fails to parse and throws an exception.
      data = JSON.parse(payload, symbolize_names: true)
      Event.construct_from(data)
    end

    module Signature
      # Verifies the signature for a given payload.
      #
      # Raises a SignatureVerificationError in the following cases:
      # - the signature does not match the expected format
      # - no signatures found
      # - a tolerance is provided and the timestamp is not within the
      #   tolerance
      #
      # Returns true otherwise
      def self.verify(payload, signature_header, timestamp, tolerance: nil)
        signature = Base64.decode64(signature_header)
        timestamp = timestamp.to_i
        signed_payload = "#{timestamp}|#{payload}"

        if tolerance && timestamp < Time.now.to_f - tolerance
          raise SignatureVerificationError.new(
            "Timestamp outside the tolerance zone (#{Time.at(timestamp)})",
            signature_header, http_body: payload
          )
        end

        begin
          verify_key.verify(signature, signed_payload)
        rescue Ed25519::VerifyError
          raise SignatureVerificationError.new(
            "Signature is invalid and does not match the payload",
            signature, http_body: payload
          )
        end

        true
      end

      def self.verify_key
        @verify_key ||= reload_verify_key
      end

      def self.reload_verify_key
        @verify_key = Ed25519::VerifyKey.new(Base64.decode64(ENV.fetch("TELNYX_PUBLIC_KEY")))
      end
    end
  end
end
