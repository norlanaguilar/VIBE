const express = require('express');
const cors = require('cors');
const { spawn } = require('child_process');
const path = require('path');
const fs = require('fs');

const app = express();
const PORT = 3000;
const HOST = '0.0.0.0'; // Escuchar en todas las interfaces de red para permitir conexiones desde emulador (10.0.2.2) y dispositivos de red

app.use(cors());
app.use(express.json());

// Endpoint POST /download
app.post('/download', (req, res) => {
  const { url } = req.body;

  if (!url) {
    return res.status(400).json({ error: 'URL de YouTube requerida' });
  }

  console.log(`[+] Procesando descarga para URL: ${url}`);

  const tempFile = path.join(__dirname, `temp_${Date.now()}.mp3`);

  // Ejecutar yt-dlp con ffmpeg para extraer audio MP3
  const ytdlp = spawn('yt-dlp', [
    '-x',
    '--audio-format', 'mp3',
    '--audio-quality', '0',
    '-o', tempFile,
    url
  ]);

  ytdlp.stdout.on('data', (data) => {
    console.log(`[yt-dlp]: ${data.toString().trim()}`);
  });

  ytdlp.stderr.on('data', (data) => {
    console.error(`[yt-dlp err]: ${data.toString().trim()}`);
  });

  ytdlp.on('close', (code) => {
    if (code === 0 && fs.existsSync(tempFile)) {
      console.log(`[+] Descarga completada con éxito. Enviando MP3 a la app...`);
      res.setHeader('Content-Type', 'audio/mpeg');
      res.setHeader('Content-Disposition', 'attachment; filename="audio.mp3"');

      const readStream = fs.createReadStream(tempFile);
      readStream.pipe(res);

      readStream.on('end', () => {
        // Eliminar archivo temporal después de enviar
        fs.unlink(tempFile, (err) => {
          if (err) console.error('Error eliminando temp:', err);
        });
      });
    } else {
      console.error(`[-] Error en yt-dlp con código de salida: ${code}`);
      res.status(500).json({ error: 'Error al convertir o descargar el vídeo con yt-dlp.' });
    }
  });
});

app.listen(PORT, HOST, () => {
  console.log(`====================================================`);
  console.log(`🚀 Servidor local VibeBackend corriendo en http://${HOST}:${PORT}`);
  console.log(`Endpoint activo: POST http://localhost:${PORT}/download`);
  console.log(`Para emulador Android: POST http://10.0.2.2:${PORT}/download`);
  console.log(`====================================================`);
});
