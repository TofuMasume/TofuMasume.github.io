#!/usr/bin/env ruby
# frozen_string_literal: true

require "base64"
require "cgi"
require "fileutils"
require "open3"
require "tempfile"
require "yaml"

ROOT = File.expand_path("..", __dir__)
POSTS_DIRECTORY = File.join(ROOT, "_posts")
CONFIG_PATH = File.join(ROOT, "_data/ogp.yml")
OUTPUT_DIRECTORY = File.join(ROOT, "assets/images/ogp/posts")
RSVG_CONVERT = ENV["OGP_RSVG_CONVERT"] || ENV.fetch("PATH", "").split(File::PATH_SEPARATOR)
  .map { |directory| File.join(directory, "rsvg-convert") }
  .find { |path| File.file?(path) && File.executable?(path) }

abort "OGP config was not found: #{CONFIG_PATH}" unless File.file?(CONFIG_PATH)
CONFIG = YAML.safe_load_file(CONFIG_PATH)
AVATAR_PATH = File.join(ROOT, CONFIG.fetch("avatar").fetch("path"))

abort "Avatar image was not found: #{AVATAR_PATH}" unless File.file?(AVATAR_PATH)
abort "rsvg-convert was not found. Install librsvg before running this script." unless RSVG_CONVERT

FileUtils.mkdir_p(OUTPUT_DIRECTORY)

def post_title(contents)
  return unless contents.start_with?("---")

  line = contents.each_line.find { |candidate| candidate.start_with?("title:") }
  return unless line

  line.delete_prefix("title:").strip.delete_prefix('"').delete_suffix('"').delete_prefix("'").delete_suffix("'")
end

def post_slug(path)
  File.basename(path, File.extname(path)).sub(/^\d{4}-\d{2}-\d{2}-/, "")
end

def character_width(character)
  character.ascii_only? ? 0.56 : 1.0
end

def wrap_title(title, max_width:)
  lines = [String.new]
  width = 0.0

  title.each_char do |character|
    next_width = width + character_width(character)
    if next_width > max_width && !lines.last.empty?
      lines << String.new
      width = 0.0
    end
    lines[-1] << character
    width += character_width(character)
  end

  lines
end


def card_svg(title, avatar_data, config)
  font = config.fetch("font")
  title_config = config.fetch("title")
  accent_bar = config.fetch("accent_bar")
  avatar = config.fetch("avatar")
  lines = wrap_title(title, max_width: title_config.fetch("max_line_width").to_f)
  line_height = font.fetch("line_height").to_i
  first_y = 315 - ((lines.length - 1) * line_height / 2)
  title_lines = lines.each_with_index.map do |line, index|
    %(<tspan x="#{title_config.fetch("x")}" y="#{first_y + (index * line_height)}">#{CGI.escapeHTML(line)}</tspan>)
  end.join("\n      ")

  avatar_size = avatar.fetch("size").to_f
  avatar_radius = avatar_size / 2
  avatar_x = avatar.fetch("center_x").to_f - avatar_radius
  avatar_y = avatar.fetch("center_y").to_f - avatar_radius
  avatar_border_radius = avatar_radius - (avatar.fetch("border_width").to_f / 2)

  <<~SVG
    <svg xmlns="http://www.w3.org/2000/svg" width="1200" height="630" viewBox="0 0 1200 630">
      <defs>
        <clipPath id="avatar-clip">
          <circle cx="#{avatar.fetch("center_x")}" cy="#{avatar.fetch("center_y")}" r="#{avatar_radius}" />
        </clipPath>
      </defs>
      <rect width="1200" height="630" fill="#{config.fetch("background_color")}" />
      <rect width="#{accent_bar.fetch("width")}" height="630" fill="#{config.fetch("accent_color")}" />
      <text fill="#{config.fetch("text_color")}" font-family="#{CGI.escapeHTML(font.fetch("family"))}" font-size="#{font.fetch("size")}" font-weight="#{font.fetch("weight")}" dominant-baseline="middle">
        #{title_lines}
      </text>
      <image href="data:image/png;base64,#{avatar_data}" x="#{avatar_x}" y="#{avatar_y}" width="#{avatar_size}" height="#{avatar_size}" clip-path="url(#avatar-clip)" preserveAspectRatio="xMidYMid slice" />
      <circle cx="#{avatar.fetch("center_x")}" cy="#{avatar.fetch("center_y")}" r="#{avatar_border_radius}" fill="none" stroke="#{config.fetch("accent_color")}" stroke-width="#{avatar.fetch("border_width")}" />
    </svg>
  SVG
end

def generate_card(title, output_path, avatar_data, config)
  Tempfile.create(["ogp-", ".svg"]) do |svg_file|
    svg_file.write(card_svg(title, avatar_data, config))
    svg_file.flush

    stdout, stderr, status = Open3.capture3(
      RSVG_CONVERT, "--width", "1200", "--height", "630", "--output", output_path, svg_file.path
    )
    abort "Failed to generate #{output_path}: #{stderr}#{stdout}" unless status.success?
  end

  puts "Generated #{output_path}"
end

avatar_data = Base64.strict_encode64(File.binread(AVATAR_PATH))

generate_card(
  CONFIG.fetch("default_title"),
  File.join(ROOT, "assets/images/ogp.png"),
  avatar_data,
  CONFIG
)

Dir.glob(File.join(POSTS_DIRECTORY, "*.md")).sort.each do |post_path|
  title = post_title(File.read(post_path, encoding: "UTF-8"))
  next unless title

  output_path = File.join(OUTPUT_DIRECTORY, "#{post_slug(post_path)}.png")
  generate_card(title, output_path, avatar_data, CONFIG)
end
