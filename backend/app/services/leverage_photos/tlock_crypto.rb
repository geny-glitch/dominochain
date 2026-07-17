# frozen_string_literal: true

require "base64"
require "json"
require "open3"
require "timeout"

class LeveragePhotos::TlockCrypto
  class Error < StandardError; end

  RUNNER = Rails.root.join("script/leverage_tlock_runner.mjs").to_s
  DEFAULT_TIMEOUT = 60

  def self.encrypt_bytes(bytes, locked_until)
    new.encrypt_bytes(bytes, locked_until)
  end

  def self.encrypt_outer_layer(armored_blob, locked_until)
    new.encrypt_outer_layer(armored_blob, locked_until)
  end

  def encrypt_bytes(bytes, locked_until)
    run!(
      "encrypt-bytes",
      {
        "bytes_base64" => Base64.strict_encode64(bytes.to_s),
        "locked_until_ms" => locked_until_ms(locked_until)
      }
    )
  end

  def encrypt_outer_layer(armored_blob, locked_until)
    run!(
      "encrypt-outer",
      {
        "armored" => armored_blob.to_s,
        "locked_until_ms" => locked_until_ms(locked_until)
      }
    )
  end

  private

  def locked_until_ms(locked_until)
    raise Error, "locked_until required" if locked_until.blank?

    time = locked_until.respond_to?(:to_time) ? locked_until.to_time : Time.zone.parse(locked_until.to_s)
    raise Error, "invalid locked_until" if time.blank? || time <= Time.current

    (time.to_f * 1000).to_i
  end

  def run!(command, payload)
    raise Error, "node runner missing" unless File.exist?(RUNNER)

    stdout = stderr = status = nil
    begin
      Timeout.timeout(DEFAULT_TIMEOUT) do
        stdout, stderr, status = Open3.capture3("node", RUNNER, command, stdin_data: JSON.generate(payload))
      end
    rescue Timeout::Error
      raise Error, "tlock encryption timed out"
    rescue Errno::ENOENT
      raise Error, "node is not installed"
    end

    unless status&.success?
      detail = stderr.to_s.strip.presence || stdout.to_s.strip.presence || "unknown error"
      raise Error, "tlock encryption failed: #{detail.truncate(500)}"
    end

    data = JSON.parse(stdout.to_s)
    armored = data["armored"].to_s
    round = data["round"].to_i
    raise Error, "empty armored output" if armored.blank?
    raise Error, "invalid round" if round <= 0

    {
      armored: armored,
      round: round,
      chain_hash: data["chain_hash"].presence || LeveragePhoto::DEFAULT_DRAND_CHAIN_HASH
    }
  rescue JSON::ParserError => e
    raise Error, "invalid tlock runner output: #{e.message}"
  end
end
