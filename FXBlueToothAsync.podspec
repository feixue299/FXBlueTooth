Pod::Spec.new do |s|
  s.name             = 'FXBlueToothAsync'
  s.version          = '0.1.0'
  s.summary          = 'Structured concurrency API for FXBlueTooth'

  s.homepage         = 'https://github.com/feixue299/FXBlueTooth'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'feixue299' => 'ariablink299@gmail.com' }
  s.source           = { :git => 'https://github.com/feixue299/FXBlueTooth.git', :tag => s.version.to_s }

  s.ios.deployment_target = '13.0'
  s.swift_version = '5.5'

  s.source_files = 'FXBlueToothAsync/**/*'
end
