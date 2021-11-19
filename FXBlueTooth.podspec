#
# Be sure to run `pod lib lint FXBlueTooth.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see https://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = 'FXBlueTooth'
  s.version          = '0.1.0'
  s.summary          = 'BlueTooth manager'

  s.homepage         = 'https://github.com/feixue299/FXBlueTooth'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'feixue299' => 'ariablink299@gmail.com' }
  s.source           = { :git => 'https://github.com/feixue299/FXBlueTooth.git', :tag => s.version.to_s }

  s.ios.deployment_target = '10.0'
  s.swift_version = '5.0'

  s.source_files = 'FXBlueTooth/Classes/**/*'

  s.dependency "SwiftyBeaver"
end
