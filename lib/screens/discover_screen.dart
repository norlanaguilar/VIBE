import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as path;
import '../services/audio_player_service.dart';
import '../theme/app_colors.dart';

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  final GlobalKey webViewKey = GlobalKey();
  InAppWebViewController? webViewController;
  double progress = 0;
  bool isDownloading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surfaceContainer,
        title: const Text('Descubrir'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              webViewController?.reload();
            },
          ),
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () async {
              if (await webViewController?.canGoBack() ?? false) {
                webViewController?.goBack();
              }
            },
          )
        ],
      ),
      body: Stack(
        children: [
          InAppWebView(
            key: webViewKey,
            initialUrlRequest: URLRequest(
              url: WebUri('https://flvto.world/es/'),
            ),
            initialSettings: InAppWebViewSettings(
              useOnDownloadStart: true,
              javaScriptEnabled: true,
              javaScriptCanOpenWindowsAutomatically: true, // Requerido para capturar el intento de popup
              supportMultipleWindows: true, // Activamos para interceptar popups y destruirlos
              useShouldOverrideUrlLoading: true,
              mediaPlaybackRequiresUserGesture: false,
            ),
            onWebViewCreated: (controller) {
              webViewController = controller;
            },
            onCreateWindow: (controller, createWindowAction) async {
              // Devuelve falso para BLOQUEAR completamente cualquier pestaña nueva (ads/popups)
              // Esto evita que nos redirija a Google o sitios basura al dar click.
              return false; 
            },
            shouldOverrideUrlLoading: (controller, navigationAction) async {
              final uri = navigationAction.request.url;
              if (uri != null) {
                final host = uri.host.toLowerCase();
                
                // Bloquear dominios maliciosos o publicitarios conocidos que secuestran la ventana principal
                if (host.contains('google.') || host.contains('doubleclick') || host.contains('pop') || host.contains('ads')) {
                  return NavigationActionPolicy.CANCEL;
                }
                
                // Permitimos cualquier otra navegación (incluyendo CDNs de flvto.world para la descarga final).
                // Si la URL es un archivo, el WebView no la podrá renderizar y lanzará onDownloadStartRequest.
              }
              return NavigationActionPolicy.ALLOW;
            },
            onProgressChanged: (controller, p) {
              setState(() {
                progress = p / 100;
              });
            },
            onDownloadStartRequest: (controller, downloadStartRequest) async {
              _handleDownload(downloadStartRequest.url.toString(), downloadStartRequest.suggestedFilename ?? 'descarga.mp3');
            },
          ),
          if (progress < 1.0)
            LinearProgressIndicator(
              value: progress,
              color: AppColors.primary,
              backgroundColor: Colors.transparent,
            ),
          if (isDownloading)
            Container(
              color: Colors.black.withOpacity(0.6),
              child: const Center(
                child: Card(
                  color: AppColors.surfaceContainerHigh,
                  child: Padding(
                    padding: EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Descargando archivo...', style: TextStyle(color: Colors.white)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _handleDownload(String url, String fileName) async {
    setState(() {
      isDownloading = true;
    });

    try {
      Directory? targetDir;
      if (Platform.isAndroid) {
        targetDir = Directory('/storage/emulated/0/Music/Vibe');
        if (!await targetDir.exists()) {
          await targetDir.create(recursive: true);
        }
      } else {
        final docDir = await getApplicationDocumentsDirectory();
        targetDir = Directory(path.join(docDir.path, 'imported_music'));
        if (!await targetDir.exists()) {
          await targetDir.create(recursive: true);
        }
      }

      final targetPath = path.join(targetDir.path, fileName);
      
      // InAppWebView no provee una API de descarga directa que funcione sin UI, usamos HttpClient
      final request = await HttpClient().getUrl(Uri.parse(url));
      final response = await request.close();
      
      final file = File(targetPath);
      final sink = file.openWrite();
      await response.pipe(sink);
      await sink.flush();
      await sink.close();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('¡Descarga completada! Guardado en: ${targetDir.path}'),
            backgroundColor: Colors.green,
          ),
        );
        
        // Escanear la biblioteca automáticamente para incluir la nueva descarga
        final audioService = Provider.of<AudioPlayerService>(context, listen: false);
        audioService.scanLocalLibrary();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al descargar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          isDownloading = false;
        });
      }
    }
  }
}
