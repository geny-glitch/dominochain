# frozen_string_literal: true

require "rails_helper"

RSpec.describe LeveragePhotos::TlockCrypto do
  it "encrypts bytes into an armored age payload", :aggregate_failures do
    skip "node is not available" unless system("node", "-v", out: File::NULL, err: File::NULL)

    locked_until = 1.hour.from_now
    result = described_class.encrypt_bytes("hello-photo", locked_until)

    expect(result[:armored]).to include("-----BEGIN AGE ENCRYPTED FILE-----")
    expect(result[:round]).to be > 0
    expect(result[:chain_hash]).to be_present
  end
end
