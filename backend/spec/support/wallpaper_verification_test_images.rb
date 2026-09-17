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

  LANDMARKS = [
    [60, 180, 90, 90, [210, 40, 50]],
    [280, 320, 80, 110, [40, 180, 90]],
    [120, 560, 100, 80, [50, 90, 210]],
    [350, 700, 70, 90, [220, 180, 40]]
  ].freeze

  def attach_landmark_png(record, attachment_name:, width:, height:, shift_y: 0)
    png = ChunkyPNG::Image.new(width, height, ChunkyPNG::Color.rgb(22, 26, 32))
    LANDMARKS.each do |x, y, w, h, color|
      top = y + shift_y
      bottom = top + h - 1
      next if bottom < 0 || top >= height || x >= width

      clipped_top = [top, 0].max
      clipped_bottom = [bottom, height - 1].min
      clipped_right = [x + w - 1, width - 1].min
      fill = ChunkyPNG::Color.rgb(*color)
      png.rect(x, clipped_top, clipped_right, clipped_bottom, fill, fill)
    end

    io = StringIO.new
    png.write(io)
    io.rewind
    record.public_send(attachment_name).attach(
      io: io,
      filename: "landmarks-#{shift_y}.png",
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
    path = Pathname.new(filename)
    path = Rails.root.join("spec/fixtures/files", filename) unless path.file?
    record.public_send(attachment_name).attach(
      io: File.open(path, "rb"),
      filename: File.basename(path),
      content_type: Marcel::MimeType.for(path)
    )
  end

  def attach_from_path(record, attachment_name:, path:)
    path = Pathname.new(path)
    record.public_send(attachment_name).attach(
      io: File.open(path, "rb"),
      filename: path.basename.to_s,
      content_type: Marcel::MimeType.for(path)
    )
  end
end
