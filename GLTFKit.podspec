Pod::Spec.new do |s|
  s.name         = "GLTFKit"
  s.version      = "0.5.0"
  s.summary      = "A framework for loading GL Transmission Format (glTF) models"
  s.homepage     = "https://github.com/warrenm/GLTFKit"
  s.screenshots  = "https://github.com/warrenm/GLTFKit/raw/master/Images/screenshot-polly.jpg"
  s.license      = { :type => 'MIT', :file => 'LICENSE' }

  s.author             = { "Warren Moore" => "wm@warrenmoore.net" }
  s.social_media_url   = "http://twitter.com/warrenm"

  s.ios.deployment_target  = "11.0"
  s.osx.deployment_target  = "10.13"
  s.tvos.deployment_target = "11.0"

  s.source              = { :git => "https://github.com/warrenm/GLTFKit.git", :tag => "#{s.version}" }
  s.source_files        = "Framework/GLTF/*.h", "Framework/GLTF/Headers/*.h", "Framework/GLTF/Source/*.m"
  s.public_header_files = "Framework/GLTF/*.h", "Framework/GLTF/Headers/*.h"

  s.requires_arc        = true

  s.default_subspec = ''

  s.subspec 'GLTFMTL' do |ss|
    ss.source_files        = "Framework/GLTFMTL/*.h", "Framework/GLTFMTL/Headers/*.h", "Framework/GLTFMTL/Source/*.m"
    ss.public_header_files = "Framework/GLTFMTL/*.h", "Framework/GLTFMTL/Headers/*.h"
    ss.resource            = "GLTFViewer/Resources/Shaders/pbr.metal"

    ss.frameworks   = 'Metal', 'MetalKit'
  end

  s.subspec 'GLTFSCN' do |ss|
    ss.source_files        = "Framework/GLTFSCN/*.h", "Framework/GLTFSCN/Headers/*.h", "Framework/GLTFSCN/Source/*.m"
    ss.public_header_files = "Framework/GLTFSCN/*.h", "Framework/GLTFSCN/Headers/*.h"

    ss.frameworks = 'SceneKit'
  end
end
