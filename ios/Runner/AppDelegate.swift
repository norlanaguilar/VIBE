import Flutter
import UIKit
import AVFoundation
import Accelerate

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var widgetChannel: FlutterMethodChannel?
  private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    configurePlaybackAudioSession()

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleDidEnterBackground),
      name: UIApplication.didEnterBackgroundNotification,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleAudioRouteChange),
      name: AVAudioSession.routeChangeNotification,
      object: nil
    )

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func configurePlaybackAudioSession() {
    let session = AVAudioSession.sharedInstance()
    do {
      if session.category != .playback || session.mode != .default {
        try session.setCategory(.playback, mode: .default, policy: .longFormAudio, options: [])
      }
      try session.setActive(true, options: [])
    } catch {
      // Fallback sin policy si el dispositivo no soporta longFormAudio en esa ruta
      try? session.setCategory(.playback, mode: .default, options: [])
      try? session.setActive(true, options: [])
    }
  }

  @objc private func handleDidEnterBackground() {
    configurePlaybackAudioSession()
    if backgroundTask != .invalid {
      UIApplication.shared.endBackgroundTask(backgroundTask)
      backgroundTask = .invalid
    }
    backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "VibeAudioTransition") { [weak self] in
      guard let self = self else { return }
      if self.backgroundTask != .invalid {
        UIApplication.shared.endBackgroundTask(self.backgroundTask)
        self.backgroundTask = .invalid
      }
    }
  }

  @objc private func handleAudioRouteChange(_ notification: Notification) {
    let session = AVAudioSession.sharedInstance()
    if session.category != .playback || session.mode != .default {
      configurePlaybackAudioSession()
    }
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "VibeNativePlugin") else {
      return
    }
    let messenger = registrar.messenger()

    // Canal para análisis de espectro FFT por adelantado (iOS)
    let spectrumChannel = FlutterMethodChannel(name: "vibe/spectrum", binaryMessenger: messenger)
    spectrumChannel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      guard let self = self else { return }
      if call.method == "analyze" {
        guard let args = call.arguments as? [String: Any],
              let path = args["path"] as? String,
              let bands = args["bands"] as? Int,
              let fps = args["fps"] as? Int else {
          result(FlutterError(code: "INVALID_ARGS", message: "Argumentos inválidos", details: nil))
          return
        }

        DispatchQueue.global(qos: .userInitiated).async {
          let data = self.analyzeAudioFile(path: path, bands: bands, fps: fps)
          DispatchQueue.main.async {
            result(data)
          }
        }
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    // Canal para Widget
    let widget = FlutterMethodChannel(name: "vibe/widget", binaryMessenger: messenger)
    self.widgetChannel = widget
    widget.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
      if call.method == "update" {
        // En iOS, las actualizaciones de estado para Widgets se pueden sincronizar con UserDefaults compartidos si se usa App Groups
        result(true)
      } else if call.method == "ready" {
        result(true)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /**
   * Lee la pista de audio con AVAssetReader y calcula la FFT con vDSP (Accelerate)
   * Produce un flujo de fotogramas float32 (0.0 .. 1.0) para cada banda de frecuencia.
   */
  private func analyzeAudioFile(path: String, bands: Int, fps: Int) -> FlutterStandardTypedData? {
    let url = URL(fileURLWithPath: path)
    let asset = AVURLAsset(url: url)

    guard let track = asset.tracks(withMediaType: .audio).first else { return nil }

    let outputSettings: [String: Any] = [
      AVFormatIDKey: kAudioFormatLinearPCM,
      AVLinearPCMBitDepthKey: 32,
      AVLinearPCMIsFloatKey: true,
      AVLinearPCMIsBigEndianKey: false,
      AVLinearPCMIsNonInterleaved: false
    ]

    guard let reader = try? AVAssetReader(asset: asset) else { return nil }
    let trackOutput = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
    trackOutput.alwaysCopiesSampleData = false
    reader.add(trackOutput)

    guard reader.startReading() else { return nil }

    // Acumular muestras mono a 44100Hz aprox
    var samples = [Float]()
    samples.reserveCapacity(44100 * 60)

    while reader.status == .reading {
      guard let sampleBuffer = trackOutput.copyNextSampleBuffer(),
            let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { break }

      let length = CMBlockBufferGetDataLength(blockBuffer)
      let sampleCount = length / MemoryLayout<Float>.size
      var buffer = [Float](repeating: 0, count: sampleCount)

      CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: &buffer)

      // Si es estéreo, promediamos a mono
      if sampleCount >= 2 {
        for i in stride(from: 0, to: sampleCount - 1, by: 2) {
          samples.append((buffer[i] + buffer[i + 1]) * 0.5)
        }
      } else {
        samples.append(contentsOf: buffer)
      }
    }

    if samples.isEmpty { return nil }

    // Procesar FFT en bloques según los FPS solicitados
    let sampleRate: Float = 44100.0
    let samplesPerFrame = Int(sampleRate / Float(fps))
    let fftSize = 512
    let log2n = vDSP_Length(log2(Float(fftSize)))
    guard let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return nil }

    let totalFrames = samples.count / samplesPerFrame
    var outputData = Data(capacity: totalFrames * bands * MemoryLayout<Float>.size)

    var window = [Float](repeating: 0, count: fftSize)
    vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))

    var realp = [Float](repeating: 0, count: fftSize / 2)
    var imagp = [Float](repeating: 0, count: fftSize / 2)

    for f in 0..<totalFrames {
      let startIndex = f * samplesPerFrame
      var frameSamples = [Float](repeating: 0, count: fftSize)

      for i in 0..<fftSize {
        let idx = startIndex + i
        if idx < samples.count {
          frameSamples[i] = samples[idx] * window[i]
        }
      }

      realp.withUnsafeMutableBufferPointer { rPtr in
        imagp.withUnsafeMutableBufferPointer { iPtr in
          var splitComplex = DSPSplitComplex(realp: rPtr.baseAddress!, imagp: iPtr.baseAddress!)

          frameSamples.withUnsafeBufferPointer { sPtr in
            sPtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: fftSize / 2) { cPtr in
              vDSP_ctoz(cPtr, 2, &splitComplex, 1, vDSP_Length(fftSize / 2))
            }
          }

          vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))

          // Magnitudes
          var magnitudes = [Float](repeating: 0, count: fftSize / 2)
          vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(fftSize / 2))

          // Mapeo a bandas logarítmicas
          let n = fftSize / 2
          for b in 0..<bands {
            let normLow = Double(b) / Double(bands)
            let normHigh = Double(b + 1) / Double(bands)
            let fLow = min(n - 1, max(0, Int(1.0 * pow(Double(n), normLow))))
            let fHigh = min(n, max(fLow + 1, Int(1.0 * pow(Double(n), normHigh))))

            var sum: Float = 0
            var count: Float = 0
            for k in fLow..<fHigh {
              sum += sqrt(magnitudes[k])
              count += 1
            }
            let avg = count > 0 ? sum / count : sqrt(magnitudes[fLow])
            var normVal = Float(log(Double(avg) + 1.0) / 4.5)
            normVal = min(1.0, max(0.06, normVal))

            withUnsafeBytes(of: normVal) { bytes in
              outputData.append(contentsOf: bytes)
            }
          }
        }
      }
    }

    vDSP_destroy_fftsetup(fftSetup)
    return FlutterStandardTypedData(bytes: outputData)
  }
}
