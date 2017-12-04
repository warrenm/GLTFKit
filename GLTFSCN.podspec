Pod::Spec.new do |s|
  s.name         = "GLTFSCN"
  s.version      = "0.5.0"
  s.summary      = "A framework for importing GL Transmission Format (glTF) models into SceneKit"
  s.homepage     = "https://github.com/warrenm/GLTFKit"
  s.screenshots  = "https://github.com/warrenm/GLTFKit/raw/master/Images/screenshot-polly.jpg"
  s.license      = { :type => 'MIT', :file => 'LICENSE' }

  s.author           = { "Warren Moore" => "wm@warrenmoore.net" }
  s.social_media_url = "http://twitter.com/warrenm"

  s.ios.deployment_target  = "11.0"
  s.osx.deployment_target  = "10.13"
  s.tvos.deployment_target = "11.0"

  s.source              = { :git => "https://github.com/warrenm/GLTFKit.git", :tag => "#{s.version}" }
  s.source_files        = "Framework/GLTFSCN/**/*.{h,m}"
  s.public_header_files = "Framework/GLTFSCN/**/*.h"

  s.dependency 'GLTF'

  s.frameworks = 'SceneKit'
  s.requires_arc = true
end
