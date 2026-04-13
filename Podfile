# Uncomment the next line to define a global platform for your project
 platform :ios, '15.6'

target 'AudioConverterDemo' do
  # Comment the next line if you don't want to use dynamic frameworks
  use_frameworks!

  # Pods for AudioConverterDemo
  pod 'TPCircularBuffer'
end

post_install do |installer|
  min_target = '15.6'

  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      current = config.build_settings['IPHONEOS_DEPLOYMENT_TARGET']
      if current.nil? || Gem::Version.new(current) < Gem::Version.new(min_target)
        config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = min_target
      end
    end
  end
end
