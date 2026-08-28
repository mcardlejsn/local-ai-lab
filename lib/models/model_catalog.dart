/// The curated, in-APK list of models offered for in-app download.
///
/// This is a pinned catalog, not a Hugging Face browser. An entry appears here
/// only after that exact artifact has been downloaded through the app and run
/// successfully on device. The list is compiled into the APK: the app makes no
/// network call to discover it, and no network call at all until the user taps
/// Download on a specific entry.
///
/// v1 constraints, deliberate:
///
///   * GGUF only. Gemini Nano is provided by Android through AICore and is not
///     a downloadable model artifact.
///   * Ungated only. Nothing here requires a Hugging Face login or a license
///     click-through. Gated models wait on a separate auth feature.
///   * `Q4_K_M` only, so download size and quality are comparable across
///     entries. The app's own scanner still accepts any `.gguf` a user
///     sideloads themselves — this restriction is on the catalog, not the app.
///
/// There is deliberately no prompt-format field. `resolvePromptFormat` in
/// `model_manager_service.dart` derives the format from the filename, and a
/// second copy of that answer here would be trusted the moment it drifted.
/// A model whose filename that resolver cannot classify does not belong in the
/// catalog until the resolver is taught to classify it.
library;

class CatalogModel {
  const CatalogModel({
    required this.id,
    required this.displayName,
    required this.fileName,
    required this.url,
    required this.sizeBytes,
    required this.sha256,
    required this.license,
    required this.sourcePage,
  });

  /// Stable key for this entry. Not the file path — the scanner assigns those.
  final String id;

  /// Name shown in the catalog list.
  final String displayName;

  /// Final on-disk name, written into `models/` once the checksum passes.
  /// Must keep its real extension and must contain a substring
  /// `resolvePromptFormat` recognizes.
  final String fileName;

  /// Commit-pinned download URL. Pinned rather than `main` so the bytes behind
  /// it cannot change out from under [sha256].
  final String url;

  /// Exact size of the finished file. Display only — the downloader uses the
  /// server's `Content-Length` and the checksum to decide correctness.
  final int sizeBytes;

  /// sha256 of the complete file, lowercase hex.
  final String sha256;

  /// SPDX-style identifier, shown before download.
  final String license;

  /// Repository page, so a user can read the model card and license terms.
  final String sourcePage;

  Uri get uri => Uri.parse(url);

  /// e.g. "1.12 GB". Decimal GB, matching how the source repo states sizes.
  String get sizeLabel {
    const int gb = 1000 * 1000 * 1000;
    const int mb = 1000 * 1000;
    if (sizeBytes >= gb) {
      return '${(sizeBytes / gb).toStringAsFixed(2)} GB';
    }
    return '${(sizeBytes / mb).toStringAsFixed(0)} MB';
  }
}

/// Every model offered for download, in display order.
const List<CatalogModel> kModelCatalog = <CatalogModel>[
  CatalogModel(
    id: 'qwen2.5-1.5b-instruct-q4_k_m',
    displayName: 'Qwen2.5 1.5B Instruct (Q4_K_M)',
    // Lowercase 'qwen' is what resolvePromptFormat matches to select ChatML.
    fileName: 'qwen2.5-1.5b-instruct-q4_k_m.gguf',
    url: 'https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/'
        'dd26da440ef0330c47919d1ecae0966d24022222/'
        'qwen2.5-1.5b-instruct-q4_k_m.gguf',
    sizeBytes: 1117320736,
    sha256: '6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e',
    license: 'Apache-2.0',
    sourcePage: 'https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF',
  ),
  CatalogModel(
    id: 'qwen2.5-0.5b-instruct-q4_k_m',
    displayName: 'Qwen2.5 0.5B Instruct (Q4_K_M)',
    fileName: 'qwen2.5-0.5b-instruct-q4_k_m.gguf',
    url: 'https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/'
        '9217f5db79a29953eb74d5343926648285ec7e67/'
        'qwen2.5-0.5b-instruct-q4_k_m.gguf',
    sizeBytes: 491400032,
    sha256: '74a4da8c9fdbcd15bd1f6d01d621410d31c6fc00986f5eb687824e7b93d7a9db',
    license: 'Apache-2.0',
    sourcePage: 'https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF',
  ),
  CatalogModel(
    id: 'falcon-h1-0.5b-instruct-q4_k_m',
    displayName: 'Falcon-H1 0.5B Instruct (Q4_K_M)',
    fileName: 'Falcon-H1-0.5B-Instruct-Q4_K_M.gguf',
    url: 'https://huggingface.co/tiiuae/Falcon-H1-0.5B-Instruct-GGUF/'
        'resolve/9bf0c2d4391cf4850aa62bfee1d8fe71afba8be2/'
        'Falcon-H1-0.5B-Instruct-Q4_K_M.gguf',
    sizeBytes: 314806560,
    sha256: '138a37a94b9e313af4e22d4af46b8119b76a31afdd61cabbeae7010ae45d2ac6',
    license: 'Falcon-LLM License',
    sourcePage: 'https://huggingface.co/tiiuae/Falcon-H1-0.5B-Instruct-GGUF',
  ),
];
