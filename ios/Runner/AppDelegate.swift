import Flutter
import UIKit
import AVFoundation
import MediaToolbox
import Accelerate
import Photos
import PhotosUI

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, PHPickerViewControllerDelegate {
  private var widgetChannel: FlutterMethodChannel?
  private var pendingGalleryResult: FlutterResult?
  private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    configurePlaybackAudioSession()
    VibeEqualizerEngine.shared.startObserving()

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

    // Canal para elegir y reproducir videos directamente desde la Galería de iOS sin duplicar archivos
    let galleryChannel = FlutterMethodChannel(name: "vibe/gallery", binaryMessenger: messenger)
    galleryChannel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      guard let self = self else { return }
      if call.method == "pickVideo" {
        self.presentGalleryVideoPicker(result: result)
      } else if call.method == "resolveVideo" {
        guard let args = call.arguments as? [String: Any],
              let ref = args["ref"] as? String else {
          result(nil)
          return
        }
        self.resolveGalleryVideo(ref: ref, result: result)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    // Canal para Ecualizador Paramétrico Real de 5 Bandas (60Hz, 230Hz, 910Hz, 4kHz, 14kHz)
    let equalizerChannel = FlutterMethodChannel(name: "vibe/equalizer", binaryMessenger: messenger)
    equalizerChannel.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
      if call.method == "setGains" {
        if let args = call.arguments as? [String: Any],
           let gains = args["gains"] as? [Double] {
          VibeEqualizerEngine.shared.updateGains(gains)
          result(true)
        } else {
          result(false)
        }
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func topViewController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    for scene in scenes {
      if let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController ?? scene.windows.first?.rootViewController {
        var current = root
        while let presented = current.presentedViewController {
          current = presented
        }
        return current
      }
    }
    return nil
  }

  private func presentGalleryVideoPicker(result: @escaping FlutterResult) {
    let openPicker = { [weak self] in
      DispatchQueue.main.async {
        guard let self = self, let presenter = self.topViewController() else {
          result(nil)
          return
        }
        self.pendingGalleryResult = result
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .videos
        config.selectionLimit = 1
        config.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        presenter.present(picker, animated: true)
      }
    }

    if #available(iOS 14, *) {
      PHPhotoLibrary.requestAuthorization(for: .readWrite) { _ in
        openPicker()
      }
    } else {
      PHPhotoLibrary.requestAuthorization { _ in
        openPicker()
      }
    }
  }

  func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
    picker.dismiss(animated: true)
    guard let pending = self.pendingGalleryResult else { return }
    self.pendingGalleryResult = nil

    guard let first = results.first else {
      pending(nil)
      return
    }

    // 1. Si tenemos el identificador permanente del activo en la Fototeca de iOS, lo guardamos como ph://<id>
    // De esta forma NUNCA se duplica el archivo en Documents ni se pierde al reinstalar/renovar cada 7 días
    if let assetId = first.assetIdentifier, !assetId.isEmpty {
      pending("ph://\(assetId)")
      return
    }

    // 2. Respaldo si el usuario dio acceso limitado sin assetIdentifier
    let provider = first.itemProvider
    if provider.hasItemConformingToTypeIdentifier("public.movie") {
      provider.loadFileRepresentation(forTypeIdentifier: "public.movie") { url, _ in
        guard let srcUrl = url else {
          DispatchQueue.main.async { pending(nil) }
          return
        }
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let targetUrl = tempDir.appendingPathComponent("vibe_gallery_\(Int(Date().timeIntervalSince1970)).mov")
        try? FileManager.default.removeItem(at: targetUrl)
        try? FileManager.default.copyItem(at: srcUrl, to: targetUrl)
        DispatchQueue.main.async {
          pending(targetUrl.path)
        }
      }
    } else {
      pending(nil)
    }
  }

  private func resolveGalleryVideo(ref: String, result: @escaping FlutterResult) {
    if ref.hasPrefix("ph://") {
      let localId = String(ref.dropFirst("ph://".count))
      let assets = PHAsset.fetchAssets(withLocalIdentifiers: [localId], options: nil)
      guard let asset = assets.firstObject else {
        result(nil)
        return
      }
      let options = PHVideoRequestOptions()
      options.isNetworkAccessAllowed = true
      options.deliveryMode = .highQualityFormat

      PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { [weak self] avAsset, _, _ in
        guard let self = self, let avAsset = avAsset else {
          DispatchQueue.main.async { result(nil) }
          return
        }
        let cropScale = self.computeLetterboxCropScale(asset: avAsset)
        if let urlAsset = avAsset as? AVURLAsset {
          DispatchQueue.main.async {
            result([
              "path": urlAsset.url.path,
              "cropScale": cropScale
            ])
          }
        } else {
          // Solo para composiciones especiales (ej. cámara lenta) exportamos a directorio temporal del sistema
          let safeKey = localId.replacingOccurrences(of: "/", with: "_")
          let tempUrl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ph_\(safeKey).mp4")
          if FileManager.default.fileExists(atPath: tempUrl.path) {
            DispatchQueue.main.async {
              result([
                "path": tempUrl.path,
                "cropScale": cropScale
              ])
            }
            return
          }
          guard let exportSession = AVAssetExportSession(asset: avAsset, presetName: AVAssetExportPresetMediumQuality) else {
            DispatchQueue.main.async { result(nil) }
            return
          }
          exportSession.outputURL = tempUrl
          exportSession.outputFileType = .mp4
          exportSession.exportAsynchronously {
            DispatchQueue.main.async {
              if exportSession.status == .completed {
                result([
                  "path": tempUrl.path,
                  "cropScale": cropScale
                ])
              } else {
                result(nil)
              }
            }
          }
        }
      }
    } else {
      let url = URL(fileURLWithPath: ref)
      guard FileManager.default.fileExists(atPath: url.path) else {
        result(nil)
        return
      }
      DispatchQueue.global(qos: .userInitiated).async { [weak self] in
        let avAsset = AVURLAsset(url: url)
        let cropScale = self?.computeLetterboxCropScale(asset: avAsset) ?? 1.06
        DispatchQueue.main.async {
          result([
            "path": url.path,
            "cropScale": cropScale
          ])
        }
      }
    }
  }

  /// Detecta si el video tiene franjas negras arriba/abajo (o a los lados) y calcula el zoom exacto
  /// para que el contenido real del video cubra el 100% del cuadro de la carátula sin líneas negras.
  private func computeLetterboxCropScale(asset: AVAsset) -> Double {
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = CGSize(width: 120, height: 240)

    let durSec = CMTimeGetSeconds(asset.duration)
    let sampleTime = CMTimeMakeWithSeconds(durSec > 2.0 ? min(1.5, durSec * 0.35) : 0.2, preferredTimescale: 600)
    guard let cgImage = try? generator.copyCGImage(at: sampleTime, actualTime: nil) else {
      return 1.06
    }

    let width = cgImage.width
    let height = cgImage.height
    guard width > 16 && height > 16 else { return 1.06 }

    var pixelData = [UInt8](repeating: 0, count: width * height * 4)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
      data: &pixelData,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: width * 4,
      space: colorSpace,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
      return 1.06
    }
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

    func isRowContent(_ y: Int) -> Bool {
      var brightPixels = 0
      let xStart = width / 8
      let xEnd = width - xStart
      for x in xStart..<xEnd {
        let offset = (y * width + x) * 4
        let r = Int(pixelData[offset])
        let g = Int(pixelData[offset + 1])
        let b = Int(pixelData[offset + 2])
        if r > 22 || g > 22 || b > 22 {
          brightPixels += 1
          if brightPixels > (xEnd - xStart) / 10 {
            return true
          }
        }
      }
      return false
    }

    var topRow = 0
    while topRow < height / 2 && !isRowContent(topRow) {
      topRow += 1
    }
    var bottomRow = height - 1
    while bottomRow > height / 2 && !isRowContent(bottomRow) {
      bottomRow -= 1
    }

    let activeHeight = max(1, bottomRow - topRow + 1)
    let activeRatio = Double(activeHeight) / Double(height)

    // En un contenedor casi cuadrado (~0.94), BoxFit.cover en un video vertical (9:16) ya muestra una
    // fracción central igual a (width / height) / 0.94. Si el contenido activo es menor que eso,
    // aplicamos el factor de escala adicional para recortar las barras negras por completo.
    let frameAspect = Double(width) / Double(height)
    let targetBoxAspect = 0.94
    let visibleHeightRatioInCover = frameAspect < targetBoxAspect ? (frameAspect / targetBoxAspect) : 1.0

    if activeRatio < visibleHeightRatioInCover {
      let neededZoom = (visibleHeightRatioInCover / activeRatio) * 1.04
      return min(max(neededZoom, 1.06), 2.6)
    }
    if topRow > 2 || (height - 1 - bottomRow) > 2 {
      let barZoom = (1.0 / activeRatio) * 1.03
      return min(max(barZoom, 1.06), 2.4)
    }
    return 1.06
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

// MARK: - Procesador DSP de Ecualizador de 5 Bandas en Tiempo Real (MTAudioProcessingTap)

private struct BiquadCoeffs {
  var b0: Float = 1.0
  var b1: Float = 0.0
  var b2: Float = 0.0
  var a1: Float = 0.0
  var a2: Float = 0.0
}

private struct BiquadState {
  var x1: Float = 0.0
  var x2: Float = 0.0
  var y1: Float = 0.0
  var y2: Float = 0.0

  @inline(__always)
  mutating func process(_ x: Float, _ c: BiquadCoeffs) -> Float {
    let y = c.b0 * x + c.b1 * x1 + c.b2 * x2 - c.a1 * y1 - c.a2 * y2
    x2 = x1
    x1 = x
    y2 = y1
    y1 = y
    return y
  }
}

private final class VibeTapContext {
  var sampleRate: Double = 44100.0
  var channels: Int = 2
  var isNonInterleaved: Bool = true
  var isFloat: Bool = true
  var cachedVersion: Int = -1
  var coeffs: [BiquadCoeffs] = Array(repeating: BiquadCoeffs(), count: 5)
  var preampGain: Float = 1.0
  var isBypassed: Bool = true
  // Estado por canal (hasta 2 canales estéreo) y 5 bandas
  var states: [[BiquadState]] = Array(
    repeating: Array(repeating: BiquadState(), count: 5),
    count: 2
  )

  func prepare(format: AudioStreamBasicDescription) {
    if format.mSampleRate > 8000 {
      sampleRate = format.mSampleRate
    }
    channels = max(1, min(2, Int(format.mChannelsPerFrame)))
    isFloat = (format.mFormatFlags & kAudioFormatFlagIsFloat) != 0
    isNonInterleaved = (format.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0
    cachedVersion = -1
    states = Array(repeating: Array(repeating: BiquadState(), count: 5), count: 2)
  }

  func syncCoefficientsIfNeeded() {
    let engine = VibeEqualizerEngine.shared
    let (version, gains) = engine.snapshotGains()
    guard version != cachedVersion else { return }
    cachedVersion = version

    // Verificar si todas las bandas están en 0.0 dB (0.5 normalizado)
    let allFlat = gains.allSatisfy { abs($0 - 0.5) < 0.008 }
    isBypassed = allFlat
    if allFlat {
      preampGain = 1.0
      return
    }

    // Rango de -15 dB a +15 dB para que el cambio sea claramente perceptible y contundente
    let freqs: [Double] = [60.0, 230.0, 910.0, 4000.0, 14000.0]
    var maxBoostDb: Double = 0.0

    for i in 0..<5 {
      let norm = max(0.0, min(1.0, gains[i]))
      let db = (norm - 0.5) * 30.0 // -15.0 dB .. +15.0 dB
      if db > maxBoostDb { maxBoostDb = db }

      if i == 0 {
        coeffs[i] = Self.makeLowShelf(freq: freqs[i], sampleRate: sampleRate, dbGain: db)
      } else if i == 4 {
        coeffs[i] = Self.makeHighShelf(freq: freqs[i], sampleRate: sampleRate, dbGain: db)
      } else {
        coeffs[i] = Self.makePeaking(freq: freqs[i], sampleRate: sampleRate, dbGain: db, q: 0.90)
      }
    }

    // Compensación parcial de ganancia para evitar saturación dura manteniendo pegada
    let headroomDb = -max(0.0, maxBoostDb * 0.28)
    preampGain = Float(pow(10.0, headroomDb / 20.0))
  }

  func process(bufferListInOut: UnsafeMutablePointer<AudioBufferList>, frameCount: Int) {
    guard frameCount > 0 else { return }
    syncCoefficientsIfNeeded()
    guard !isBypassed, isFloat else { return }

    let abl = UnsafeMutableAudioBufferListPointer(bufferListInOut)
    let c0 = coeffs[0]
    let c1 = coeffs[1]
    let c2 = coeffs[2]
    let c3 = coeffs[3]
    let c4 = coeffs[4]
    let pre = preampGain

    if isNonInterleaved || abl.count > 1 {
      let bufCount = min(abl.count, 2)
      for ch in 0..<bufCount {
        guard let data = abl[ch].mData else { continue }
        let ptr = data.assumingMemoryBound(to: Float.self)
        var s0 = states[ch][0]
        var s1 = states[ch][1]
        var s2 = states[ch][2]
        var s3 = states[ch][3]
        var s4 = states[ch][4]

        for i in 0..<frameCount {
          var sample = ptr[i] * pre
          sample = s0.process(sample, c0)
          sample = s1.process(sample, c1)
          sample = s2.process(sample, c2)
          sample = s3.process(sample, c3)
          sample = s4.process(sample, c4)
          // Limitador suave de estudio para graves profundos sin distorsión digital
          if sample > 0.92 {
            sample = 0.92 + 0.08 * tanh((sample - 0.92) * 8.0)
          } else if sample < -0.92 {
            sample = -0.92 + 0.08 * tanh((sample + 0.92) * 8.0)
          }
          ptr[i] = sample
        }

        states[ch][0] = s0
        states[ch][1] = s1
        states[ch][2] = s2
        states[ch][3] = s3
        states[ch][4] = s4
      }
    } else if let firstBuf = abl.first, let data = firstBuf.mData {
      let chCount = max(1, min(2, Int(firstBuf.mNumberChannels)))
      let ptr = data.assumingMemoryBound(to: Float.self)
      for ch in 0..<chCount {
        var s0 = states[ch][0]
        var s1 = states[ch][1]
        var s2 = states[ch][2]
        var s3 = states[ch][3]
        var s4 = states[ch][4]

        for i in 0..<frameCount {
          let idx = i * chCount + ch
          var sample = ptr[idx] * pre
          sample = s0.process(sample, c0)
          sample = s1.process(sample, c1)
          sample = s2.process(sample, c2)
          sample = s3.process(sample, c3)
          sample = s4.process(sample, c4)
          if sample > 0.92 {
            sample = 0.92 + 0.08 * tanh((sample - 0.92) * 8.0)
          } else if sample < -0.92 {
            sample = -0.92 + 0.08 * tanh((sample + 0.92) * 8.0)
          }
          ptr[idx] = sample
        }

        states[ch][0] = s0
        states[ch][1] = s1
        states[ch][2] = s2
        states[ch][3] = s3
        states[ch][4] = s4
      }
    }
  }

  private static func makePeaking(freq: Double, sampleRate: Double, dbGain: Double, q: Double) -> BiquadCoeffs {
    if abs(dbGain) < 0.05 { return BiquadCoeffs() }
    let A = pow(10.0, dbGain / 40.0)
    let w0 = 2.0 * Double.pi * min(freq, sampleRate * 0.45) / sampleRate
    let cosw0 = cos(w0)
    let sinw0 = sin(w0)
    let alpha = sinw0 / (2.0 * q)

    let b0 = 1.0 + alpha * A
    let b1 = -2.0 * cosw0
    let b2 = 1.0 - alpha * A
    let a0 = 1.0 + alpha / A
    let a1 = -2.0 * cosw0
    let a2 = 1.0 - alpha / A

    return BiquadCoeffs(
      b0: Float(b0 / a0),
      b1: Float(b1 / a0),
      b2: Float(b2 / a0),
      a1: Float(a1 / a0),
      a2: Float(a2 / a0)
    )
  }

  private static func makeLowShelf(freq: Double, sampleRate: Double, dbGain: Double) -> BiquadCoeffs {
    if abs(dbGain) < 0.05 { return BiquadCoeffs() }
    let A = pow(10.0, dbGain / 40.0)
    let w0 = 2.0 * Double.pi * min(freq, sampleRate * 0.45) / sampleRate
    let cosw0 = cos(w0)
    let sinw0 = sin(w0)
    let alpha = sinw0 / 2.0 * sqrt(2.0)
    let twoSqrtAAlpha = 2.0 * sqrt(A) * alpha

    let b0 = A * ((A + 1.0) - (A - 1.0) * cosw0 + twoSqrtAAlpha)
    let b1 = 2.0 * A * ((A - 1.0) - (A + 1.0) * cosw0)
    let b2 = A * ((A + 1.0) - (A - 1.0) * cosw0 - twoSqrtAAlpha)
    let a0 = (A + 1.0) + (A - 1.0) * cosw0 + twoSqrtAAlpha
    let a1 = -2.0 * ((A - 1.0) + (A + 1.0) * cosw0)
    let a2 = (A + 1.0) + (A - 1.0) * cosw0 - twoSqrtAAlpha

    return BiquadCoeffs(
      b0: Float(b0 / a0),
      b1: Float(b1 / a0),
      b2: Float(b2 / a0),
      a1: Float(a1 / a0),
      a2: Float(a2 / a0)
    )
  }

  private static func makeHighShelf(freq: Double, sampleRate: Double, dbGain: Double) -> BiquadCoeffs {
    if abs(dbGain) < 0.05 { return BiquadCoeffs() }
    let A = pow(10.0, dbGain / 40.0)
    let w0 = 2.0 * Double.pi * min(freq, sampleRate * 0.45) / sampleRate
    let cosw0 = cos(w0)
    let sinw0 = sin(w0)
    let alpha = sinw0 / 2.0 * sqrt(2.0)
    let twoSqrtAAlpha = 2.0 * sqrt(A) * alpha

    let b0 = A * ((A + 1.0) + (A - 1.0) * cosw0 + twoSqrtAAlpha)
    let b1 = -2.0 * A * ((A - 1.0) + (A + 1.0) * cosw0)
    let b2 = A * ((A + 1.0) + (A - 1.0) * cosw0 - twoSqrtAAlpha)
    let a0 = (A + 1.0) - (A - 1.0) * cosw0 + twoSqrtAAlpha
    let a1 = 2.0 * ((A - 1.0) - (A + 1.0) * cosw0)
    let a2 = (A + 1.0) - (A - 1.0) * cosw0 - twoSqrtAAlpha

    return BiquadCoeffs(
      b0: Float(b0 / a0),
      b1: Float(b1 / a0),
      b2: Float(b2 / a0),
      a1: Float(a1 / a0),
      a2: Float(a2 / a0)
    )
  }
}

private let eqTapInit: MTAudioProcessingTapInitCallback = { tap, clientInfo, tapStorageOut in
  tapStorageOut.pointee = clientInfo
}

private let eqTapFinalize: MTAudioProcessingTapFinalizeCallback = { tap in
  let storage = MTAudioProcessingTapGetStorage(tap)
  Unmanaged<VibeTapContext>.fromOpaque(storage).release()
}

private let eqTapPrepare: MTAudioProcessingTapPrepareCallback = { tap, _, processingFormat in
  let storage = MTAudioProcessingTapGetStorage(tap)
  let context = Unmanaged<VibeTapContext>.fromOpaque(storage).takeUnretainedValue()
  context.prepare(format: processingFormat.pointee)
}

private let eqTapUnprepare: MTAudioProcessingTapUnprepareCallback = { _ in }

private let eqTapProcess: MTAudioProcessingTapProcessCallback = {
  tap, numberFrames, _, bufferListInOut, numberFramesOut, flagsOut in
  var timeRange = CMTimeRange.zero
  let status = MTAudioProcessingTapGetSourceAudio(
    tap,
    numberFrames,
    bufferListInOut,
    flagsOut,
    &timeRange,
    numberFramesOut
  )
  guard status == noErr else { return }
  let storage = MTAudioProcessingTapGetStorage(tap)
  let context = Unmanaged<VibeTapContext>.fromOpaque(storage).takeUnretainedValue()
  context.process(bufferListInOut: bufferListInOut, frameCount: Int(numberFramesOut.pointee))
}

final class VibeEqualizerEngine {
  static let shared = VibeEqualizerEngine()

  private let lock = NSLock()
  private var gains: [Double] = [0.5, 0.5, 0.5, 0.5, 0.5]
  private var version: Int = 1
  private let trackedItems = NSHashTable<AVPlayerItem>.weakObjects()
  private var isObserving = false

  func startObserving() {
    guard !isObserving else { return }
    isObserving = true

    NotificationCenter.default.addObserver(
      forName: .AVPlayerItemTimeJumped,
      object: nil,
      queue: .main
    ) { [weak self] note in
      if let item = note.object as? AVPlayerItem {
        self?.attachTapIfNeeded(to: item)
      }
    }

    NotificationCenter.default.addObserver(
      forName: .AVPlayerItemNewAccessLogEntry,
      object: nil,
      queue: .main
    ) { [weak self] note in
      if let item = note.object as? AVPlayerItem {
        self?.attachTapIfNeeded(to: item)
      }
    }
  }

  func updateGains(_ newGains: [Double]) {
    guard newGains.count >= 5 else { return }
    lock.lock()
    gains = Array(newGains.prefix(5))
    version &+= 1
    let items = trackedItems.allObjects
    lock.unlock()

    DispatchQueue.main.async { [weak self] in
      for item in items {
        self?.attachTapIfNeeded(to: item)
      }
    }
  }

  func snapshotGains() -> (Int, [Double]) {
    lock.lock()
    defer { lock.unlock() }
    return (version, gains)
  }

  func attachTapIfNeeded(to item: AVPlayerItem) {
    lock.lock()
    trackedItems.add(item)
    lock.unlock()

    if item.audioMix != nil {
      return
    }

    let asset = item.asset
    let applyMix: () -> Void = {
      guard item.audioMix == nil,
            let audioTrack = asset.tracks(withMediaType: .audio).first else {
        return
      }
      let context = VibeTapContext()
      var callbacks = MTAudioProcessingTapCallbacks(
        version: kMTAudioProcessingTapCallbacksVersion_0,
        clientInfo: UnsafeMutableRawPointer(Unmanaged.passRetained(context).toOpaque()),
        init: eqTapInit,
        finalize: eqTapFinalize,
        prepare: eqTapPrepare,
        unprepare: eqTapUnprepare,
        process: eqTapProcess
      )
      var tap: MTAudioProcessingTap?
      let err = MTAudioProcessingTapCreate(
        kCFAllocatorDefault,
        &callbacks,
        kMTAudioProcessingTapCreationFlag_PostEffects,
        &tap
      )
      guard err == noErr, let createdTap = tap else {
        Unmanaged.passUnretained(context).release()
        return
      }
      let params = AVMutableAudioMixInputParameters(track: audioTrack)
      params.audioTapProcessor = createdTap
      let mix = AVMutableAudioMix()
      mix.inputParameters = [params]
      item.audioMix = mix
    }

    if asset.statusOfValue(forKey: "tracks", error: nil) == .loaded {
      applyMix()
    } else {
      asset.loadValuesAsynchronously(forKeys: ["tracks"]) {
        DispatchQueue.main.async {
          applyMix()
        }
      }
    }
  }
}

