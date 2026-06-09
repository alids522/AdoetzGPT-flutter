import Flutter
import UIKit
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var audioEngine: AVAudioEngine?
  private var playerNode: AVAudioPlayerNode?
  private var audioFormat: AVAudioFormat?
  private let audioQueue = DispatchQueue(label: "com.adoetz.adoetzgpt.audio", qos: .userInteractive)

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    guard let controller = window?.rootViewController as? FlutterViewController else {
      return
    }

    let channel = FlutterMethodChannel(
      name: "adoetzgpt/live_audio",
      binaryMessenger: controller.binaryMessenger
    )

    channel.setMethodCallHandler { [weak self] (call, result) in
      switch call.method {
      case "start":
        let args = call.arguments as? [String: Any]
        let sampleRate = args?["sampleRate"] as? Int ?? 24000
        self?.startPcmPlayback(sampleRate: sampleRate)
        result(nil)

      case "play":
        guard let data = call.arguments as? FlutterStandardTypedData else {
          result(FlutterError(code: "bad_args", message: "PCM payload missing.", details: nil))
          return
        }
        self?.playPcm16(data: data.data)
        result(nil)

      case "stop":
        self?.stopPcmPlayback()
        result(nil)

      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func startPcmPlayback(sampleRate: Int) {
    stopPcmPlayback()

    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playAndRecord, options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers])
      try session.setActive(true)
    } catch {
      NSLog("AdoetzGPT: Failed to configure audio session: \(error)")
      return
    }

    let engine = AVAudioEngine()
    let player = AVAudioPlayerNode()
    guard let format = AVAudioFormat(
      commonFormat: .pcmFormatFloat32,
      sampleRate: Double(sampleRate),
      channels: 1,
      interleaved: false
    ) else {
      NSLog("AdoetzGPT: Failed to create audio format")
      return
    }

    engine.attach(player)
    engine.connect(player, to: engine.mainMixerNode, format: format)

    do {
      try engine.start()
      player.play()
    } catch {
      NSLog("AdoetzGPT: Failed to start audio engine: \(error)")
      return
    }

    self.audioEngine = engine
    self.playerNode = player
    self.audioFormat = format
  }

  private func playPcm16(data: Data) {
    audioQueue.async { [weak self] in
      guard let self = self,
            let player = self.playerNode,
            let format = self.audioFormat,
            data.count >= 2 else { return }

      let sampleCount = data.count / 2
      guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(sampleCount)) else {
        return
      }
      buffer.frameLength = AVAudioFrameCount(sampleCount)

      guard let channelData = buffer.floatChannelData?[0] else { return }

      data.withUnsafeBytes { rawPtr in
        guard let int16Ptr = rawPtr.bindMemory(to: Int16.self).baseAddress else { return }
        for i in 0..<sampleCount {
          channelData[i] = Float(int16Ptr[i]) / 32768.0
        }
      }

      player.scheduleBuffer(buffer, completionHandler: nil)
    }
  }

  private func stopPcmPlayback() {
    playerNode?.stop()
    audioEngine?.stop()
    playerNode = nil
    audioEngine = nil
    audioFormat = nil

    do {
      try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    } catch {
      // Ignore deactivation errors
    }
  }
}
