// Word Error Rate between a reference command and an ASR transcript.
//
// WER = (substitutions + deletions + insertions) / reference_word_count,
// computed via word-level Levenshtein distance. Used to quantify how badly
// the Whisper STT stage degraded each spoken command in the pipeline arm.

class Wer {
  /// Lowercase, strip punctuation, collapse whitespace → list of word tokens.
  static List<String> _normalize(String s) {
    final cleaned = s
        .toLowerCase()
        .replaceAll(RegExp(r"[^\w\s']"), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.isEmpty) return const [];
    return cleaned.split(' ');
  }

  /// Word-level WER of [hypothesis] against [reference]. Returns 0.0 when the
  /// normalized forms match; clamps an empty reference to 0/1 to avoid div-by-0.
  static double compute(String reference, String hypothesis) {
    final ref = _normalize(reference);
    final hyp = _normalize(hypothesis);
    if (ref.isEmpty) return hyp.isEmpty ? 0.0 : 1.0;

    // Standard edit-distance DP over words.
    final n = ref.length, m = hyp.length;
    final dp = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
    for (var i = 0; i <= n; i++) {
      dp[i][0] = i;
    }
    for (var j = 0; j <= m; j++) {
      dp[0][j] = j;
    }
    for (var i = 1; i <= n; i++) {
      for (var j = 1; j <= m; j++) {
        final cost = ref[i - 1] == hyp[j - 1] ? 0 : 1;
        dp[i][j] = [
          dp[i - 1][j] + 1, // deletion
          dp[i][j - 1] + 1, // insertion
          dp[i - 1][j - 1] + cost, // substitution / match
        ].reduce((a, b) => a < b ? a : b);
      }
    }
    return dp[n][m] / ref.length;
  }
}
