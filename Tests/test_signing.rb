require "tmpdir"
require "fileutils"
require_relative "../fastlane/signing"

Dir.mktmpdir do |dir|
  source = File.expand_path("../Kanpeki.xcodeproj", __dir__)
  path = File.join(dir, "Kanpeki.xcodeproj")
  FileUtils.cp_r(source, path)
  snapshot = lambda do |project|
    project.targets.to_h do |target|
      [target.name, target.build_configurations.to_h { |config| [config.name, config.build_settings] }]
    end
  end
  before = snapshot.call(Xcodeproj::Project.open(path))
  configure_phone_signing(path, "test-profile-uuid")
  after = snapshot.call(Xcodeproj::Project.open(path))
  expected = Marshal.load(Marshal.dump(before))
  expected.fetch("KanpekiPhone").fetch("Release").merge!(
    "CODE_SIGN_STYLE" => "Manual", "DEVELOPMENT_TEAM" => "XYJX89KRDM",
    "CODE_SIGN_IDENTITY" => "Apple Distribution", "PROVISIONING_PROFILE_SPECIFIER" => "test-profile-uuid"
  )
  raise "Unexpected change outside iPhone Release signing settings" unless after == expected
  raise "Project-wide profile would affect package resources" if Xcodeproj::Project.open(path).build_configurations.any? { |config| config.build_settings.key?("PROVISIONING_PROFILE_SPECIFIER") }
end
puts "Signing settings round-trip passed; other targets/configurations unchanged."
