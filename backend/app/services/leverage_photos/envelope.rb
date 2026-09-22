# frozen_string_literal: true

require "base64"
require "digest"
require "json"
require "openssl"

# Envelope lock: AES-GCM a payload, tlock only the key (bound to photo_id + hash).
# New locks AES the JPEG. Legacy full_image locks convert on extend/relock by AES
# of the existing tlock onion. Unlock peels the key, AES-unwraps, then peels any
# leftover onion one Node process per layer so the JPEG is restored on the server.
class LeveragePhotos::Envelope
  class Error < StandardError; end

  VERSION = 1
  ALG = "aes-256-gcm"
  IV_LEN = 12
  TAG_LEN = 16
  KEY_LEN = 32

  def self.seal!(photo, locked_until)
    new(photo).seal!(locked_until)
  end

  def self.open!(photo)
    new(photo).open!
  end

  def initialize(photo)
    @photo = photo
  end

  def seal!(locked_until)
    packed, crypto = build(locked_until)
    attach_packed!(packed)
    crypto
  end

  def build(locked_until)
    raise Error, "original missing" unless @photo.original_image.attached?

    plaintext = @photo.original_image.download
    raise Error, "original missing" if plaintext.blank?

    build_from_bytes(plaintext, locked_until)
  end

  # AES-GCM the current full-image tlock onion and tlock only the key, so later
  # extends wrap a tiny payload instead of re-tlocking the whole JPEG.
  def wrap_existing_blob(locked_until)
    raise Error, "locked payload missing" unless @photo.tlock_blob.attached?

    ciphertext = @photo.tlock_blob.download
    raise Error, "locked payload missing" if ciphertext.blank?

    build_from_bytes(ciphertext, locked_until)
  end

  def build_from_bytes(plaintext, locked_until)
    raise Error, "payload missing" if plaintext.blank?

    key = SecureRandom.random_bytes(KEY_LEN)
    packed = encrypt_aes(plaintext, key, aad: @photo.id.to_s)
    unless decrypt_aes(packed, key, aad: @photo.id.to_s) == plaintext
      raise Error, "could not seal original"
    end

    digest = Digest::SHA256.hexdigest(packed)

    payload = {
      v: VERSION,
      photo_id: @photo.id,
      alg: ALG,
      k: Base64.strict_encode64(key),
      ciphertext_sha256: digest
    }.to_json

    crypto = LeveragePhotos::TlockCrypto.encrypt_bytes(payload, locked_until)
    [packed, crypto]
  end

  def open!
    raise Error, "locked payload missing" unless @photo.tlock_blob.attached?
    raise Error, "encrypted original missing" unless @photo.encrypted_original.attached?

    peeled = LeveragePhotos::TlockCrypto.decrypt_attachment(@photo.tlock_blob)
    payload = parse_payload!(peeled)
    packed = @photo.encrypted_original.download
    verify_binding!(payload, packed)
    plaintext = decrypt_aes(
      packed,
      Base64.strict_decode64(payload.fetch("k")),
      aad: @photo.id.to_s
    )
    if LeveragePhotos::TlockCrypto.age_armored?(plaintext)
      plaintext = LeveragePhotos::TlockCrypto.decrypt_bytes(plaintext)
    end

    @photo.persist_restored_original!(
      io: StringIO.new(plaintext),
      filename: @photo.download_filename,
      content_type: "image/jpeg"
    )
    @photo
  end

  private

  def attach_packed!(packed)
    @photo.encrypted_original.purge if @photo.encrypted_original.attached?
    @photo.encrypted_original.attach(
      io: StringIO.new(packed),
      filename: "original.bin",
      content_type: "application/octet-stream"
    )
  end

  def encrypt_aes(plaintext, key, aad:)
    cipher = OpenSSL::Cipher.new("aes-256-gcm")
    cipher.encrypt
    cipher.key = key
    iv = cipher.random_iv
    raise Error, "invalid iv" unless iv.bytesize == IV_LEN

    cipher.auth_data = aad
    ciphertext = cipher.update(plaintext) + cipher.final
    tag = cipher.auth_tag(TAG_LEN)
    iv + ciphertext + tag
  end

  def decrypt_aes(packed, key, aad:)
    raise Error, "ciphertext too short" if packed.bytesize < IV_LEN + TAG_LEN

    iv = packed.byteslice(0, IV_LEN)
    tag = packed.byteslice(-TAG_LEN, TAG_LEN)
    ciphertext = packed.byteslice(IV_LEN, packed.bytesize - IV_LEN - TAG_LEN)
    cipher = OpenSSL::Cipher.new("aes-256-gcm")
    cipher.decrypt
    cipher.key = key
    cipher.iv = iv
    cipher.auth_tag = tag
    cipher.auth_data = aad
    cipher.update(ciphertext) + cipher.final
  rescue OpenSSL::Cipher::CipherError
    raise Error, "could not restore original"
  end

  def parse_payload!(bytes)
    data = JSON.parse(bytes.to_s)
    raise Error, "invalid envelope" unless data.is_a?(Hash)

    data
  rescue JSON::ParserError
    raise Error, "invalid envelope"
  end

  def verify_binding!(payload, packed)
    raise Error, "invalid envelope" unless payload["v"].to_i == VERSION
    raise Error, "invalid envelope" unless payload["alg"] == ALG
    raise Error, "photo mismatch" unless payload["photo_id"].to_i == @photo.id

    expected = payload["ciphertext_sha256"].to_s
    actual = Digest::SHA256.hexdigest(packed)
    raise Error, "ciphertext mismatch" unless expected.match?(/\A[0-9a-f]{64}\z/) && actual == expected
  end
end
