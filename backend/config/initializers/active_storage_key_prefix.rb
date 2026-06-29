# frozen_string_literal: true

# Prefix blob keys so prod and staging can share one Tigris bucket safely.
ActiveSupport.on_load(:active_storage_blob) do
  before_create do
    prefix = ENV["ACTIVE_STORAGE_KEY_PREFIX"].to_s
    next if prefix.blank?
    next if key.start_with?(prefix)

    self.key = "#{prefix}#{key}"
  end
end
