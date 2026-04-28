Pod::Spec.new do |s|
  s.name = 'hand_gesture_sdk'
  s.version = '0.0.1'
  s.summary = 'Flutter plugin for launching the hand gesture recognizer and receiving gesture events.'
  s.description = <<-DESC
  Flutter plugin for launching the hand gesture recognizer and receiving gesture events.
  DESC
  s.homepage = 'https://example.invalid'
  s.license = { :file => '../LICENSE' }
  s.author = { 'xinzhang' => 'xinzhang@example.invalid' }
  s.source = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.resources = 'Resources/Models/**/*'
  s.dependency 'Flutter'
  s.dependency 'MediaPipeTasksVision'
  s.platform = :ios, '12.0'
  s.swift_version = '5.0'
end
