class AddAndroidVersionToAppSettings < ActiveRecord::Migration[7.2]
  def change
    add_column :app_settings, :android_version_code, :integer
    add_column :app_settings, :android_apk_url, :string
  end
end
