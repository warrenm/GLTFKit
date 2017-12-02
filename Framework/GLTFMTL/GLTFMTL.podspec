Pod::Spec.new do |s|
  s.name         = "GLTFMTL"
  s.version      = "0.5.0"
  s.summary      = "A framework for rendering GL Transmission Format (glTF) models with Metal"
  s.homepage     = "https://github.com/warrenm/GLTFKit"
  s.screenshots  = "https://github.com/warrenm/GLTFKit/raw/master/Images/screenshot-polly.jpg"
  s.license      = { :type => 'MIT', :file => 'LICENSE' }

  s.author           = { "Warren Moore" => "wm@warrenmoore.net" }
  s.social_media_url = "http://twitter.com/warrenm"

  s.ios.deployment_target  = "11.0"
  s.osx.deployment_target  = "10.13"
  s.tvos.deployment_target = "11.0"

  s.source              = { :git => "https://github.com/warrenm/GLTFKit.git", :tag => "#{s.version}" }
  s.source_files        = "Framework/GLTFMTL/*.h", "Framework/GLTFMTL/Headers/*.h", "Framework/GLTFMTL/Source/*.m"
  s.public_header_files = "Framework/GLTFMTL/*.h", "Framework/GLTFMTL/Headers/*.h"
  s.resource            = "GLTFViewer/Resources/Shaders/pbr.metal"

  s.dependency 'GLTF'
  
  s.frameworks   = 'Metal', 'MetalKit'
  s.requires_arc = true
end
