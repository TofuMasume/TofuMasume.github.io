# Assign generated Open Graph images without repeating front matter.
Jekyll::Hooks.register :posts, :pre_render do |post|
  post.data["image"] ||= {
    "path" => "/assets/images/ogp/posts/#{post.data["slug"]}.png",
    "width" => 1200,
    "height" => 630,
    "alt" => post.data["title"],
  }
end
