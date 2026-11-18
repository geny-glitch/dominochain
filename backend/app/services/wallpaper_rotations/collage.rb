# frozen_string_literal: true

require "vips"

module WallpaperRotations
  # Builds one background from several photos.
  # Two photos sit side by side. Four photos fill a 2x2 grid.
  # Each photo is cover-cropped into its cell. Canvas size matches the phone.
  class Collage
    CANVAS_MAX_SIDE = 2048

    class << self
      def canvas_size(width, height)
        width = width.to_i
        height = height.to_i
        width = 1080 if width <= 1
        height = 1920 if height <= 1
        longest = [width, height].max
        if longest > CANVAS_MAX_SIDE
          scale = CANVAS_MAX_SIDE.to_f / longest
          width = (width * scale).to_i
          height = (height * scale).to_i
        end
        width -= 1 if width.odd?
        height -= 1 if height.odd?
        width = 2 if width < 2
        height = 2 if height < 2
        [width, height]
      end

      def render(wallpapers:, device:)
        width, height = canvas_size(device.screen_width, device.screen_height)
        images = wallpapers.map { |wallpaper| load_image(wallpaper, device) }
        compose(images, width, height)
      end

      def compose(images, width, height)
        raise ArgumentError, "collage needs at least 2 images" if images.size < 2

        width, height = canvas_size(width, height)
        cells = if images.size >= 4
          cell_w = width / 2
          cell_h = height / 2
          images.first(4).map { |image| cover_crop(image, cell_w, cell_h) }
        else
          cell_w = width / 2
          images.first(2).map { |image| cover_crop(image, cell_w, height) }
        end
        Vips::Image.arrayjoin(cells, across: 2)
      end

      def to_jpeg(image)
        image.write_to_buffer(".jpg[Q=85]")
      end

      def cover_crop(image, cell_w, cell_h)
        image = prepare(image)
        scale = [cell_w.to_f / image.width, cell_h.to_f / image.height].max
        resized = image.resize(scale, vscale: scale)
        resized = resized.cast(:uchar) if resized.format != :uchar

        if resized.width < cell_w || resized.height < cell_h
          return resized.embed(
            [(cell_w - resized.width) / 2, 0].max,
            [(cell_h - resized.height) / 2, 0].max,
            cell_w,
            cell_h,
            extend: :white
          )
        end

        left = [((resized.width - cell_w) / 2.0).floor, 0].max
        top = [((resized.height - cell_h) / 2.0).floor, 0].max
        left = [left, resized.width - cell_w].min
        top = [top, resized.height - cell_h].min
        resized.crop(left, top, cell_w, cell_h)
      end

      def prepare(image)
        image = image.colourspace(:srgb) unless image.interpretation == :srgb
        image = image.flatten(background: 255) if image.has_alpha?
        image = image.extract_band(0, n: 3) if image.bands > 3
        image = image.bandjoin([image, image]) if image.bands == 1
        image
      rescue Vips::Error
        image
      end

      private

      def load_image(wallpaper, device)
        blob = source_blob(wallpaper, device)
        blob.open do |file|
          image = Vips::Image.new_from_file(file.path)
          data = image.write_to_memory
          Vips::Image.new_from_memory(data, image.width, image.height, image.bands, image.format)
        end
      end

      def source_blob(wallpaper, device)
        if device.screen_width.to_i > 1 && device.screen_height.to_i > 1
          processed = wallpaper.image.variant(
            resize_to_fill: [device.screen_width, device.screen_height]
          ).processed
          # VariantWithRecord#blob is the original. The resized file lives on the variant record.
          variant_blob = processed.image&.blob
          return variant_blob if variant_blob
        end
        wallpaper.image.blob
      rescue Vips::Error, ActiveStorage::Error, ActiveStorage::InvariableError
        wallpaper.image.blob
      end
    end
  end
end
