#!/usr/bin/env ruby
# Generates <lang>.lproj/Localizable.strings into the built product from
# Resources/Localizable.xcstrings, merged over the legacy .lproj tables
# (the catalog wins on conflicts) — the same merge the Fastfile performs
# for the archive. Running it as a build phase means EVERY build ships the
# localization tables: the unit-test host, simulator runs, and the archive.
# Without it, only Fastfile-built archives were localized, which is exactly
# what LanguageResolutionTests caught failing in CI.
#
# Usage: invoked by Xcode build phases with no arguments (destination comes
# from TARGET_BUILD_DIR/UNLOCALIZED_RESOURCES_FOLDER_PATH), or manually with
# an explicit destination directory as ARGV[0].

require "json"
require "fileutils"

project_dir = ENV["PROJECT_DIR"] || File.expand_path("..", __dir__)
dest_root = ARGV[0] || File.join(ENV.fetch("TARGET_BUILD_DIR"),
                                 ENV.fetch("UNLOCALIZED_RESOURCES_FOLDER_PATH"))

catalog = JSON.parse(File.read(File.join(project_dir, "Resources", "Localizable.xcstrings")))

%w[en ro fr nl de].each do |lang|
  merged = {}

  legacy = File.join(project_dir, "Resources", "#{lang}.lproj", "Localizable.strings")
  if File.exist?(legacy)
    File.read(legacy).scan(/^"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)";/m).each do |k, v|
      un = ->(s) { s.gsub('\\n', "\n").gsub('\\"', '"').gsub('\\\\', '\\') }
      merged[un.call(k)] = un.call(v)
    end
  end

  catalog["strings"].each do |key, info|
    value = info.dig("localizations", lang, "stringUnit", "value")
    value ||= info.dig("localizations", "en", "stringUnit", "value")
    merged[key] = value if value
  end

  lproj_dir = File.join(dest_root, "#{lang}.lproj")
  FileUtils.mkdir_p(lproj_dir)
  content = merged.map { |k, v| "#{k.to_json} = #{v.to_json};" }.join("\n") + "\n"
  File.write(File.join(lproj_dir, "Localizable.strings"), content)
  puts "xcstrings → #{lang}.lproj/Localizable.strings (#{merged.size} keys)"
end
