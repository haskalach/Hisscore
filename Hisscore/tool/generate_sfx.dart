// Synthesizes short retro "8-bit" sound effects as WAV files, so the
// game has real audio without depending on any external/downloaded
// asset. Run with: dart run tool/generate_sfx.dart
//
// Each effect is a simple square/sine tone (or a short sequence of
// them) written as 16-bit PCM mono WAV — the classic chiptune-blip
// sound, matching the game's CRT/arcade theme.
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

const _sampleRate = 22050;

void main() {
  Directory('assets/sfx').createSync(recursive: true);

  _write('eat', _tones([_Tone(880, 60, _Wave.square)]));
  _write(
    'bonus',
    _tones([_Tone(660, 50, _Wave.square), _Tone(990, 70, _Wave.square)]),
  );
  _write(
    'levelup',
    _tones([
      _Tone(523, 60, _Wave.square),
      _Tone(659, 60, _Wave.square),
      _Tone(784, 60, _Wave.square),
      _Tone(1047, 110, _Wave.square),
    ]),
  );
  _write(
    'gameover',
    _tones([
      _Tone(392, 100, _Wave.sine),
      _Tone(330, 100, _Wave.sine),
      _Tone(262, 220, _Wave.sine),
    ]),
  );

  stdout.writeln('Wrote assets/sfx/*.wav');
}

void _write(String name, Float32List samples) {
  File('assets/sfx/$name.wav').writeAsBytesSync(_encodeWav(samples));
}

enum _Wave { sine, square }

class _Tone {
  const _Tone(this.hz, this.ms, this.wave);
  final double hz;
  final int ms;
  final _Wave wave;
}

/// Renders a sequence of tones back-to-back into one sample buffer,
/// with a short linear fade-out on each tone to avoid audible clicks.
Float32List _tones(List<_Tone> tones) {
  final chunks = <Float32List>[];
  for (final t in tones) {
    final n = (_sampleRate * t.ms / 1000).round();
    final buf = Float32List(n);
    for (var i = 0; i < n; i++) {
      final phase = 2 * pi * t.hz * i / _sampleRate;
      final raw = switch (t.wave) {
        _Wave.sine => sin(phase),
        _Wave.square => sin(phase) >= 0 ? 1.0 : -1.0,
      };
      final fadeOut = 1.0 - (i / n) * 0.6; // gentle decay, no hard cutoff
      buf[i] = raw * 0.5 * fadeOut;
    }
    chunks.add(buf);
  }
  final total = chunks.fold<int>(0, (sum, c) => sum + c.length);
  final out = Float32List(total);
  var offset = 0;
  for (final c in chunks) {
    out.setAll(offset, c);
    offset += c.length;
  }
  return out;
}

/// Encodes mono float samples (-1..1) as a 16-bit PCM WAV file.
Uint8List _encodeWav(Float32List samples) {
  const bitsPerSample = 16;
  const numChannels = 1;
  final byteRate = _sampleRate * numChannels * bitsPerSample ~/ 8;
  final blockAlign = numChannels * bitsPerSample ~/ 8;
  final dataSize = samples.length * 2;

  final buffer = BytesBuilder();
  void writeString(String s) => buffer.add(s.codeUnits);
  void writeU32(int v) => buffer.add([
    v & 0xFF,
    (v >> 8) & 0xFF,
    (v >> 16) & 0xFF,
    (v >> 24) & 0xFF,
  ]);
  void writeU16(int v) => buffer.add([v & 0xFF, (v >> 8) & 0xFF]);

  writeString('RIFF');
  writeU32(36 + dataSize);
  writeString('WAVE');
  writeString('fmt ');
  writeU32(16);
  writeU16(1); // PCM
  writeU16(numChannels);
  writeU32(_sampleRate);
  writeU32(byteRate);
  writeU16(blockAlign);
  writeU16(bitsPerSample);
  writeString('data');
  writeU32(dataSize);
  for (final s in samples) {
    final clamped = s.clamp(-1.0, 1.0);
    final intSample = (clamped * 32767).round();
    writeU16(intSample & 0xFFFF);
  }
  return buffer.toBytes();
}
