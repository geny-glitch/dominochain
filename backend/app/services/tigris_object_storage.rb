# frozen_string_literal: true

require "aws-sdk-s3"

class TigrisObjectStorage
  class ConfigurationError < StandardError; end

  class << self
    def configured?
      bucket_name.present? && access_key_id.present? && secret_access_key.present? && endpoint.present?
    end

    def bucket_name
      ENV["BUCKET_NAME"].presence
    end

    def key_prefix
      ENV.fetch("ACTIVE_STORAGE_KEY_PREFIX", "")
    end

    def prefixed_key(key)
      prefix = key_prefix
      return key if prefix.blank? || key.start_with?(prefix)

      "#{prefix}#{key}"
    end

    def upload(key:, body:, content_type: nil)
      client.put_object(
        bucket: bucket_name,
        key: prefixed_key(key),
        body: body,
        content_type: content_type
      )
    end

    def exists?(key)
      client.head_object(bucket: bucket_name, key: prefixed_key(key))
      true
    rescue Aws::S3::Errors::NotFound, Aws::S3::Errors::NoSuchKey
      false
    end

    def download(key)
      response = client.get_object(bucket: bucket_name, key: prefixed_key(key))
      response.body.read
    end

    def presigned_download_url(key, expires_in: 1.hour)
      presigner.presigned_url(
        :get_object,
        bucket: bucket_name,
        key: prefixed_key(key),
        expires_in: expires_in.to_i
      )
    end

    private

    def access_key_id
      ENV["AWS_ACCESS_KEY_ID"].presence
    end

    def secret_access_key
      ENV["AWS_SECRET_ACCESS_KEY"].presence
    end

    def endpoint
      ENV["AWS_ENDPOINT_URL_S3"].presence
    end

    def region
      ENV.fetch("AWS_REGION", "auto")
    end

    def client
      raise ConfigurationError, "Tigris is not configured" unless configured?

      @client ||= Aws::S3::Client.new(
        access_key_id: access_key_id,
        secret_access_key: secret_access_key,
        endpoint: endpoint,
        region: region,
        force_path_style: true
      )
    end

    def presigner
      @presigner ||= Aws::S3::Presigner.new(client: client)
    end
  end
end
