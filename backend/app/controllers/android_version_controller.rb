class AndroidVersionController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:update]

  APK_PATH = Rails.root.join("storage", "android", "app.apk")

  def show
    setting = AppSetting.instance
    render json: {
      versionCode: setting.android_version_code || 0,
      url: setting.android_apk_url || ""
    }
  end

  def apk
    if File.exist?(APK_PATH)
      send_file APK_PATH,
        type: "application/vnd.android.package-archive",
        disposition: "attachment",
        filename: "app.apk"
    else
      render json: { error: "Not found" }, status: :not_found
    end
  end

  def update
    expected = ENV["DEPLOY_SECRET"].presence
    provided  = request.headers["Authorization"]&.delete_prefix("Bearer ")

    if expected.nil? || provided != expected
      return render json: { error: "Unauthorized" }, status: :unauthorized
    end

    version_code = params.require(:versionCode).to_i
    apk_file     = params[:apk]

    if apk_file.present?
      FileUtils.mkdir_p(APK_PATH.dirname)
      FileUtils.cp(apk_file.tempfile.path, APK_PATH)
    end

    apk_url = "#{request.base_url}/android/app.apk"

    AppSetting.instance.update!(
      android_version_code: version_code,
      android_apk_url: apk_url
    )

    render json: { versionCode: version_code, url: apk_url }
  end
end
