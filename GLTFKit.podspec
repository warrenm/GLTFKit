Pod::Spec.new do |s|
  s.name         = "GLTFKit"
  s.version      = "0.5.0"
  s.summary      = "A framework for loading GL Transmission Format (glTF) models"
  s.homepage     = "https://github.com/warrenm/GLTFKit"
  s.screenshots  = "https://github.com/warrenm/GLTFKit/raw/master/Images/screenshot-polly.jpg"
  s.license      = { :type => 'MIT', :file => 'LICENSE' }

  s.author           = { "Warren Moore" => "wm@warrenmoore.net" }
  s.social_media_url = "http://twitter.com/warrenm"

  s.ios.deployment_target  = "11.0"
  s.osx.deployment_target  = "10.13"
  s.tvos.deployment_target = "11.0"

  s.source = { :git => "https://github.com/warrenm/GLTFKit.git", :tag => "#{s.version}" }

  s.requires_arc = true

  s.default_subspecs = 'GLTF'

  s.subspec 'GLTF' do |ss|
	ss.source_files        = "Framework/GLTF/**/*.{h,m}"
	ss.public_header_files = "Framework/GLTF/**/*.h"
  end

  s.subspec 'GLTFMTL' do |ss|
    ss.source_files        = "Framework/GLTFMTL/**/*.{h,m}"
    ss.public_header_files = "Framework/GLTFMTL/**/*.h"
    ss.resource            = "GLTFViewer/Resources/Shaders/pbr.metal"

    ss.dependency 'GLTFKit/GLTF'

    ss.frameworks = 'Metal', 'MetalKit'
  end

  s.subspec 'GLTFSCN' do |ss|
    ss.source_files        = "Framework/GLTFSCN/**/*.{h,m}"
    ss.public_header_files = "Framework/GLTFSCN/**/*.h"

    ss.dependency 'GLTFKit/GLTF'

    ss.frameworks = 'SceneKit'
  end
end
