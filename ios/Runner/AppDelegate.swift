import Flutter
import UIKit
import AVFoundation
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
