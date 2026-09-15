require "xcodeproj"

# Only the application Release target may receive a provisioning profile.
# Swift Package resource bundles inherit global xcargs and reject profiles.
def configure_phone_signing(path, profile_uuid)
  project = Xcodeproj::Project.open(path)
  target = project.targets.find { |item| item.name == "KanpekiPhone" }
  raise "KanpekiPhone target missing" unless target
  config = target.build_configurations.find { |item| item.name == "Release" }
  raise "KanpekiPhone Release configuration missing" unless config
  config.build_settings.merge!(
    "CODE_SIGN_STYLE" => "Manual",
    "DEVELOPMENT_TEAM" => "XYJX89KRDM",
    "CODE_SIGN_IDENTITY" => "Apple Distribution",
    "PROVISIONING_PROFILE_SPECIFIER" => profile_uuid
  )
  project.save
end
