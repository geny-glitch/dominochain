# frozen_string_literal: true

require "rails_helper"
require "vips"

RSpec.describe WallpaperRotations::Collage do
  def solid(red, green, blue, width = 8, height = 8)
    Vips::Image.black(width, height, bands: 3).new_from_image([red, green, blue])
  end

  def channel(image, x, y, band)
    image.getpoint(x, y)[band].to_f
  end

  it "uses an even canvas and caps the long side" do
    expect(described_class.canvas_size(nil, nil)).to eq([1080, 1920])
    expect(described_class.canvas_size(1081, 1921)).to eq([1080, 1920])
    expect(described_class.canvas_size(4000, 2000)).to eq([2048, 1024])
  end

  it "places two photos side by side" do
    image = described_class.compose([solid(255, 0, 0), solid(0, 0, 255)], 8, 8)

    expect(image.width).to eq(8)
    expect(image.height).to eq(8)
    expect(channel(image, 1, 1, 0)).to be > 200
    expect(channel(image, 6, 1, 2)).to be > 200
  end

  it "places four photos in a grid" do
    image = described_class.compose(
      [solid(255, 0, 0), solid(0, 255, 0), solid(0, 0, 255), solid(255, 255, 0)],
      8,
      8
    )

    expect(channel(image, 1, 1, 0)).to be > 200
    expect(channel(image, 6, 1, 1)).to be > 200
    expect(channel(image, 1, 6, 2)).to be > 200
    expect(channel(image, 6, 6, 0)).to be > 200
    expect(channel(image, 6, 6, 1)).to be > 200
  end

  it "writes a jpeg" do
    bytes = described_class.to_jpeg(solid(10, 20, 30))
    expect(bytes.byteslice(0, 2).bytes).to eq([0xFF, 0xD8])
  end
end
