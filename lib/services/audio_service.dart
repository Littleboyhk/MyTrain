import 'dart:math' as math;
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import '../data/app_settings_controller.dart';
import '../utils/haptics.dart';

/// Audio service for playing synthesized alarm tones and preview sounds.
class AudioService {
  AudioService._();
  static final AudioService instance = AudioService._();

  final AudioPlayer _player = AudioPlayer();

  /// Cache generated WAV bytes for instant replay.
  final Map<AlarmTone, Uint8List> _waveCache = {};

  /// Play preview sound for the specified alarm tone.
  Future<void> playTone(AlarmTone tone) async {
    Haptics.selection();
    if (tone == AlarmTone.vibrateOnly) {
      await stop();
      return;
    }

    try {
      final wavBytes = _getOrCreateWav(tone);
      await _player.stop();
      await _player.play(BytesSource(wavBytes));
    } catch (e, st) {
      debugPrint('[AudioService] Error playing tone $tone: $e\n$st');
    }
  }

  /// Stop active playback.
  Future<void> stop() async {
    try {
      await _player.stop();
    } catch (e) {
      debugPrint('[AudioService] Error stopping audio: $e');
    }
  }

  Uint8List _getOrCreateWav(AlarmTone tone) {
    if (_waveCache.containsKey(tone)) {
      return _waveCache[tone]!;
    }
    final bytes = ToneSynthesizer.generateWav(tone);
    _waveCache[tone] = bytes;
    return bytes;
  }
}

/// Synthesizes pure PCM WAV audio data for each [AlarmTone] in Dart.
class ToneSynthesizer {
  ToneSynthesizer._();

  static const int sampleRate = 22050;

  static Uint8List generateWav(AlarmTone tone) {
    late final List<double> samples;

    switch (tone) {
      case AlarmTone.classicBell:
        samples = _generateBell();
        break;
      case AlarmTone.stationChime:
        samples = _generateStationChime();
        break;
      case AlarmTone.hornShort:
        samples = _generateHorn();
        break;
      case AlarmTone.gentleRise:
        samples = _generateGentleRise();
        break;
      case AlarmTone.vibrateOnly:
        samples = [];
        break;
    }

    return _buildWavHeaderAndData(samples);
  }

  /// Classic Bell: 880 Hz with exponential decay envelope.
  static List<double> _generateBell() {
    const durationSec = 1.2;
    final totalSamples = (sampleRate * durationSec).toInt();
    final result = List<double>.filled(totalSamples, 0.0);

    for (int i = 0; i < totalSamples; i++) {
      final t = i / sampleRate;
      final decay = math.exp(-3.5 * t);
      // Fundamental 880Hz + overtone 1760Hz
      final wave = 0.7 * math.sin(2 * math.pi * 880 * t) +
          0.3 * math.sin(2 * math.pi * 1760 * t);
      result[i] = (wave * decay).clamp(-1.0, 1.0);
    }
    return result;
  }

  /// Station Chime: 3-note ascending chime (523Hz, 659Hz, 784Hz).
  static List<double> _generateStationChime() {
    const durationSec = 1.4;
    final totalSamples = (sampleRate * durationSec).toInt();
    final result = List<double>.filled(totalSamples, 0.0);

    final freqs = [523.25, 659.25, 783.99]; // C5, E5, G5
    final noteTimes = [0.0, 0.4, 0.8];

    for (int i = 0; i < totalSamples; i++) {
      final t = i / sampleRate;
      double sampleVal = 0.0;

      for (int n = 0; n < freqs.length; n++) {
        final noteStart = noteTimes[n];
        if (t >= noteStart) {
          final elapsed = t - noteStart;
          final decay = math.exp(-4.0 * elapsed);
          sampleVal += 0.5 * math.sin(2 * math.pi * freqs[n] * elapsed) * decay;
        }
      }
      result[i] = sampleVal.clamp(-1.0, 1.0);
    }
    return result;
  }

  /// Train Horn: Dual pitch tone (311Hz + 370Hz).
  static List<double> _generateHorn() {
    const durationSec = 0.75;
    final totalSamples = (sampleRate * durationSec).toInt();
    final result = List<double>.filled(totalSamples, 0.0);

    for (int i = 0; i < totalSamples; i++) {
      final t = i / sampleRate;
      // Envelope with quick attack and release
      double envelope = 1.0;
      if (t < 0.05) {
        envelope = t / 0.05;
      } else if (t > 0.65) {
        envelope = (0.75 - t) / 0.10;
      }
      envelope = envelope.clamp(0.0, 1.0);

      // Dual tone (Eb4 + F#4 train horn interval)
      final wave = 0.5 * math.sin(2 * math.pi * 311.13 * t) +
          0.5 * math.sin(2 * math.pi * 369.99 * t);
      result[i] = (wave * envelope).clamp(-1.0, 1.0);
    }
    return result;
  }

  /// Gentle Rise: Pitch sweep from 440Hz to 700Hz.
  static List<double> _generateGentleRise() {
    const durationSec = 1.2;
    final totalSamples = (sampleRate * durationSec).toInt();
    final result = List<double>.filled(totalSamples, 0.0);

    for (int i = 0; i < totalSamples; i++) {
      final t = i / sampleRate;
      final progress = t / durationSec;

      // Smooth sine wave with soft fade in/out
      final fade = math.sin(math.pi * progress);
      final phase = 2 * math.pi * (440.0 * t + (130.0 * t * t / durationSec));
      result[i] = (0.8 * math.sin(phase) * fade).clamp(-1.0, 1.0);
    }
    return result;
  }

  /// Builds valid 16-bit PCM WAV container byte array.
  static Uint8List _buildWavHeaderAndData(List<double> samples) {
    final numSamples = samples.length;
    final subchunk2Size = numSamples * 2; // 16-bit mono = 2 bytes per sample
    final chunkSize = 36 + subchunk2Size;

    final buffer = ByteData(44 + subchunk2Size);

    // RIFF header
    _writeString(buffer, 0, 'RIFF');
    buffer.setUint32(4, chunkSize, Endian.little);
    _writeString(buffer, 8, 'WAVE');

    // fmt subchunk
    _writeString(buffer, 12, 'fmt ');
    buffer.setUint32(16, 16, Endian.little); // Subchunk1Size (16 for PCM)
    buffer.setUint16(20, 1, Endian.little); // AudioFormat (1 for PCM)
    buffer.setUint16(22, 1, Endian.little); // NumChannels (1 = Mono)
    buffer.setUint32(24, sampleRate, Endian.little);
    buffer.setUint32(28, sampleRate * 2, Endian.little); // ByteRate
    buffer.setUint16(32, 2, Endian.little); // BlockAlign
    buffer.setUint16(34, 16, Endian.little); // BitsPerSample

    // data subchunk
    _writeString(buffer, 36, 'data');
    buffer.setUint32(40, subchunk2Size, Endian.little);

    // PCM samples
    int offset = 44;
    for (int i = 0; i < numSamples; i++) {
      final intSample = (samples[i] * 32767.0).floor().clamp(-32768, 32767);
      buffer.setInt16(offset, intSample, Endian.little);
      offset += 2;
    }

    return buffer.buffer.asUint8List();
  }

  static void _writeString(ByteData buffer, int offset, String text) {
    for (int i = 0; i < text.length; i++) {
      buffer.setUint8(offset + i, text.codeUnitAt(i));
    }
  }
}
