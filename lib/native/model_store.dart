// Resolves on-device paths for Cactus model folders.
//
// The Cactus v2.0 FFI binding has no download layer, so models are staged
// manually (download the Cactus-format folder on a PC, then:
//   adb push <model_dir>  /storage/emulated/0/Android/data/<pkg>/files/models/<id>
// ). `cactusInit` is then pointed at that folder.

import 'dart:io';

import 'package:path_provider/path_provider.dart';

class ModelStore {
  /// Base directory that holds `models/<id>/...`. Prefers the app's external
  /// files dir (adb-pushable) and falls back to app documents.
  static Future<Directory> _base() async {
    final ext = await getExternalStorageDirectory();
    if (ext != null) return ext;
    return getApplicationDocumentsDirectory();
  }

  /// Absolute path to the folder where model [id] is expected to live.
  static Future<String> modelDir(String id) async {
    final base = await _base();
    return '${base.path}/models/$id';
  }

  /// Whether model [id] appears to be staged (folder exists and is non-empty).
  static Future<bool> isStaged(String id) async {
    final dir = Directory(await modelDir(id));
    if (!await dir.exists()) return false;
    return dir.list().isEmpty.then((empty) => !empty);
  }

  /// Directory where benchmark output files (CSV/JSON/MD, transcripts,
  /// progress) are written, created on first use. Anchored to the same
  /// adb-pullable external files dir as models and clips, so a bare relative
  /// `results/` path — which has no writable CWD on Android — is never used.
  static Future<String> resultsDir() async {
    final base = await _base();
    final dir = Directory('${base.path}/results');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir.path;
  }

  /// Directory where benchmark audio clips are stored (created on first use).
  ///
  /// [condition] separates recordings for different eval conditions (e.g. the
  /// multilingual pilot's 'en' vs 'codeswitch' arms) so they don't overwrite
  /// each other. Omitted/'en' keeps the original path for backward
  /// compatibility with clips already recorded there.
  static Future<String> audioDir({String? condition}) async {
    final base = await _base();
    final suffix =
        (condition == null || condition == 'en') ? '' : '_$condition';
    final dir = Directory('${base.path}/benchmark_audio$suffix');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir.path;
  }
}
