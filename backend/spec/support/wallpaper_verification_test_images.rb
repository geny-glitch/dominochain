# frozen_string_literal: true

module WallpaperVerificationTestImages
  module_function

  def attach_png(record, attachment_name:, width:, height:, color:)
    png = ChunkyPNG::Image.new(width, height, ChunkyPNG::Color.rgb(*color))
    io = StringIO.new
    png.write(io)
    io.rewind
    record.public_send(attachment_name).attach(
      io: io,
      filename: "test-#{color.join('-')}.png",
      content_type: "image/png"
    )
  end

  def attach_pattern_png(record, attachment_name:, width:, height:, color_a:, color_b:)
    png = ChunkyPNG::Image.new(width, height, ChunkyPNG::Color.rgb(*color_a))
    width.times do |x|
      height.times do |y|
        next unless ((x / 40) + (y / 40)).even?

        png[x, y] = ChunkyPNG::Color.rgb(*color_b)
      end
    end

    io = StringIO.new
    png.write(io)
    io.rewind
    record.public_send(attachment_name).attach(
      io: io,
      filename: "pattern-#{color_a.join('-')}.png",
      content_type: "image/png"
    )
  end

  def attach_overlay_screenshot(device_screenshot, base_color:, overlay_color:)
    width = device_screenshot.device.screen_width
    height = device_screenshot.device.screen_height
    png = ChunkyPNG::Image.new(width, height, ChunkyPNG::Color.rgb(*base_color))

    12.times do |index|
      x = 80 + ((index % 4) * 220)
      y = 320 + ((index / 4) * 220)
      png.rect(x, y, x + 48, y + 48, ChunkyPNG::Color.rgb(*overlay_color), ChunkyPNG::Color.rgb(*overlay_color))
    end

    io = StringIO.new
    png.write(io)
    io.rewind
    device_screenshot.image.attach(
      io: io,
      filename: "overlay-screenshot.png",
      content_type: "image/png"
    )
  end

  def attach_fixture(record, attachment_name:, filename:)
    path = Rails.root.join("spec/fixtures/files", filename)
    record.public_send(attachment_name).attach(
      io: File.open(path, "rb"),
      filename: File.basename(filename),
      content_type: Marcel::MimeType.for(path)
    )
  end
end
