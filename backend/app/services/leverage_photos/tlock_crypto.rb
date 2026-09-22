# frozen_string_literal: true

require "json"
require "open3"
require "timeout"
require "tmpdir"

class LeveragePhotos::TlockCrypto
  class Error < StandardError; end

  RUNNER = Rails.root.join("script/leverage_tlock_runner.mjs").to_s
  DEFAULT_TIMEOUT = 90
  DECRYPT_LAYER_TIMEOUT = 120
  MAX_ATTEMPTS = 2
  MAX_INPUT_BYTES = 48.megabytes
  NODE_HEAP_MB = 1536
  AGE_ARMOR_PREFIX = "-----BEGIN AGE ENCRYPTED FILE-----"

  def self.encrypt_bytes(bytes, locked_until)
    new.encrypt_bytes(bytes, locked_until)
  end

  def self.encrypt_outer_layer(armored_blob, locked_until)
    new.encrypt_outer_layer(armored_blob, locked_until)
  end

  def self.encrypt_attachment(attachment, locked_until, command:)
    new.encrypt_attachment(attachment, locked_until, command: command)
  end

  def self.decrypt_attachment(attachment)
    new.decrypt_attachment(attachment)
  end

  def self.decrypt_bytes(bytes)
    new.decrypt_bytes(bytes)
  end

  def self.age_armored?(bytes)
    bytes.to_s.lstrip.start_with?(AGE_ARMOR_PREFIX)
  end

  def encrypt_bytes(bytes, locked_until)
    with_input_file(bytes.to_s) do |in_path|
      encrypt_from_path("encrypt-bytes", in_path, locked_until)
    end
  end

  def encrypt_outer_layer(armored_blob, locked_until)
    with_input_file(armored_blob.to_s) do |in_path|
      encrypt_from_path("encrypt-outer", in_path, locked_until)
    end
  end

  def encrypt_attachment(attachment, locked_until, command:)
    raise Error, "attachment missing" unless attachment&.attached?

    attachment.open do |file|
      encrypt_from_path(command, file.path, locked_until)
    end
  end

  def decrypt_attachment(attachment)
    raise Error, "attachment missing" unless attachment&.attached?

    attachment.open do |file|
      decrypt_from_path(file.path)
    end
  end

  def decrypt_bytes(bytes)
    raise Error, "payload missing" if bytes.blank?

    with_input_file(bytes.to_s) do |in_path|
      decrypt_from_path(in_path)
    end
  end

  private

  def locked_until_ms(locked_until)
    raise Error, "locked_until required" if locked_until.blank?

    time = locked_until.respond_to?(:to_time) ? locked_until.to_time : Time.zone.parse(locked_until.to_s)
    raise Error, "invalid locked_until" if time.blank? || time <= Time.current

    (time.to_f * 1000).to_i
  end

  def with_input_file(data)
    Dir.mktmpdir("tlock-in-") do |dir|
      in_path = File.join(dir, "payload.bin")
      File.binwrite(in_path, data)
      yield in_path
    end
  end

  def decrypt_from_path(in_path)
    raise Error, "node runner missing" unless File.exist?(RUNNER)

    current = File.binread(in_path)
    raise Error, "empty decrypted output" if current.blank?

    layers = 0
    while self.class.age_armored?(current)
      layers += 1
      raise Error, "tlock decryption failed" if layers > LeveragePhoto::MAX_PEEL_LAYERS

      current = decrypt_one_layer(current)
    end

    raise Error, "empty decrypted output" if current.blank?

    current
  end

  def decrypt_one_layer(armored)
    with_input_file(armored) do |in_path|
      Dir.mktmpdir("tlock-out-") do |dir|
        out_path = File.join(dir, "payload.bin")
        stdout, stderr, status = run_node_with_retries(
          ["node", RUNNER, "decrypt-once", in_path, out_path],
          timeout_message: "tlock decryption timed out",
          timeout_seconds: DECRYPT_LAYER_TIMEOUT
        )

        unless status&.success?
          raise_runner_failure("tlock decryption failed", stdout, stderr)
        end

        raise Error, "empty decrypted output" unless File.exist?(out_path) && File.size(out_path).positive?

        File.binread(out_path)
      end
    end
  end

  def encrypt_from_path(command, in_path, locked_until)
    raise Error, "node runner missing" unless File.exist?(RUNNER)

    Dir.mktmpdir("tlock-out-") do |dir|
      out_path = File.join(dir, "payload.age")
      stdout, stderr, status = run_with_retries(command, in_path, out_path, locked_until_ms(locked_until))

      unless status&.success?
        raise_runner_failure(
          "tlock encryption failed",
          stdout,
          stderr,
          extra: "command=#{command} bytes=#{File.size(in_path)}"
        )
      end

      armored = File.exist?(out_path) ? File.read(out_path) : ""
      data = JSON.parse(stdout.to_s)
      round = data["round"].to_i
      raise Error, "empty armored output" if armored.blank?
      raise Error, "invalid round" if round <= 0

      {
        armored: armored,
        round: round,
        chain_hash: data["chain_hash"].presence || LeveragePhoto::DEFAULT_DRAND_CHAIN_HASH
      }
    end
  rescue JSON::ParserError => e
    raise Error, "invalid tlock runner output: #{e.message}"
  end

  def run_with_retries(command, in_path, out_path, locked_until_ms)
    run_node_with_retries(
      ["node", RUNNER, command, in_path, out_path, locked_until_ms.to_s],
      timeout_message: "tlock encryption timed out"
    )
  end

  def run_node_with_retries(argv, timeout_message:, timeout_seconds: DEFAULT_TIMEOUT)
    in_path = argv[3]
    if in_path.present? && File.exist?(in_path)
      size = File.size(in_path)
      raise Error, "tlock input too large" if size > MAX_INPUT_BYTES
    end

    attempt = 0
    begin
      attempt += 1
      stdout = stderr = status = nil
      Timeout.timeout(timeout_seconds) do
        stdout, stderr, status = Open3.capture3(node_env, *argv)
      end
      [stdout, stderr, status]
    rescue Timeout::Error
      retry if attempt < MAX_ATTEMPTS
      raise Error, timeout_message
    rescue Errno::ENOENT
      raise Error, "node is not installed"
    end
  end

  def node_env
    options = ENV["NODE_OPTIONS"].to_s
    unless options.include?("max-old-space-size")
      options = [options, "--max-old-space-size=#{NODE_HEAP_MB}"].reject(&:blank?).join(" ")
    end
    ENV.to_h.merge("NODE_OPTIONS" => options)
  end

  def raise_runner_failure(prefix, stdout, stderr, extra: nil)
    detail = stderr.to_s.strip.presence || stdout.to_s.strip.presence || "unknown error"
    suffix = extra.present? ? " (#{extra})" : ""
    Rails.logger.error("[TlockCrypto] #{prefix}#{suffix}: #{detail.truncate(2000)}")
    raise Error, prefix
  end
end
