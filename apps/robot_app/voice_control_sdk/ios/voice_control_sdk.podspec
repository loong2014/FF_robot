Pod::Spec.new do |s|
  s.name             = 'voice_control_sdk'
  s.version          = '0.0.1'
  s.summary          = 'Flutter plugin for wake-word detection and command recognition.'
  s.description      = <<-DESC
Flutter plugin for wake-word detection and command recognition.
DESC
  s.homepage         = 'https://example.invalid'
  s.license          = { :type => 'MIT' }
  s.author           = { 'xinzhang' => 'xinzhang@example.invalid' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform         = :ios, '12.0'
end
