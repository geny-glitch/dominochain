# frozen_string_literal: true

module WallpaperHelper
  def wallpaper_verification_badge(screenshot)
    status = screenshot.verification_status
    return if status.blank? || status == "pending"

    badge_class = case status
    when "verified" then "ds-badge--success"
    when "mismatch" then "ds-badge--error"
    when "inconclusive" then "ds-badge--pending"
    else "ds-badge--neutral"
    end

    label = t("wallpaper.verification.#{status}")
    text = if screenshot.similarity_score.present?
      t("wallpaper.verification.score", label: label, percent: (screenshot.similarity_score * 100).round)
    else
      label
    end

    hint = case status
    when "mismatch" then t("wallpaper.verification.mismatch_hint")
    when "inconclusive" then t("wallpaper.verification.inconclusive_hint")
    end

    content_tag(:div, class: "ds-verification") do
      safe_join([
        content_tag(:span, text, class: "ds-badge #{badge_class}"),
        (content_tag(:span, hint, class: "ds-verification-hint") if hint.present?)
      ].compact)
    end
  end
end
