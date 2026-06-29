# frozen_string_literal: true

class AndroidApkStorage
  OBJECT_KEY = "android/app.apk"

  class << self
    def present?
      return false unless TigrisObjectStorage.configured?

      TigrisObjectStorage.exists?(OBJECT_KEY)
    end

    def upload(source_path)
      TigrisObjectStorage.upload(
        key: OBJECT_KEY,
        body: File.binread(source_path),
        content_type: "application/vnd.android.package-archive"
      )
    end

    def upload_io(io)
      TigrisObjectStorage.upload(
        key: OBJECT_KEY,
        body: io.read,
        content_type: "application/vnd.android.package-archive"
      )
    end

    def presigned_download_url(expires_in: 1.hour)
      TigrisObjectStorage.presigned_download_url(OBJECT_KEY, expires_in: expires_in)
    end
  end
end
