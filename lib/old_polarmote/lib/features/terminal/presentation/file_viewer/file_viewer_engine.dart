import 'package:path/path.dart' as p;

enum InternalFileViewerKind { text, image, audio, video, pdf, unsupported }

class InternalFileViewerEngine {
  InternalFileViewerEngine._();

  static const Set<String> _textFileNames = {
    'dockerfile',
    '.gitignore',
    '.gitattributes',
    '.editorconfig',
    '.env',
    '.env.example',
    '.npmrc',
    '.nvmrc',
    '.yarnrc',
    '.yarnrc.yml',
    '.gitmodules',
    'makefile',
    'justfile',
    'procfile',
    'gemfile',
    'pipfile',
    'cargo.toml',
    'cargo.lock',
    'package-lock.json',
    'pnpm-lock.yaml',
    'yarn.lock',
    'gradle.properties',
    'settings.gradle',
    'settings.gradle.kts',
    'build.gradle',
    'build.gradle.kts',
    'cmakelists.txt',
    'meson.build',
    'jenkinsfile',
    'vagrantfile',
    'license',
    'readme',
    'readme.md',
  };

  static const Set<String> _textExtensions = {
    '.txt',
    '.md',
    '.markdown',
    '.log',
    '.json',
    '.jsonc',
    '.json5',
    '.jsonl',
    '.ndjson',
    '.yaml',
    '.yml',
    '.xml',
    '.xsd',
    '.xsl',
    '.csv',
    '.tsv',
    '.ini',
    '.toml',
    '.conf',
    '.cfg',
    '.env',
    '.lock',
    '.sh',
    '.bash',
    '.zsh',
    '.fish',
    '.ps1',
    '.psm1',
    '.psd1',
    '.cmd',
    '.bat',
    '.ksh',
    '.py',
    '.pyi',
    '.js',
    '.mjs',
    '.cjs',
    '.ts',
    '.dart',
    '.proto',
    '.graphql',
    '.gql',
    '.java',
    '.kt',
    '.kts',
    '.c',
    '.h',
    '.cpp',
    '.cc',
    '.hpp',
    '.cs',
    '.go',
    '.rs',
    '.swift',
    '.php',
    '.rb',
    '.pl',
    '.pm',
    '.lua',
    '.r',
    '.m',
    '.mm',
    '.scala',
    '.groovy',
    '.asm',
    '.s',
    '.sql',
    '.html',
    '.htm',
    '.shtml',
    '.css',
    '.scss',
    '.less',
    '.vue',
    '.tsx',
    '.jsx',
    '.dockerfile',
    '.gradle',
    '.properties',
    '.gitignore',
    '.gitattributes',
    '.editorconfig',
  };

  static const Set<String> _imageExtensions = {
    '.png',
    '.jpg',
    '.jpeg',
    '.jfif',
    '.gif',
    '.webp',
    '.avif',
    '.bmp',
    '.svg',
    '.ico',
    '.tif',
    '.tiff',
    '.heic',
    '.heif',
  };

  static const Set<String> _audioExtensions = {
    '.mp3',
    '.wav',
    '.flac',
    '.m4a',
    '.aac',
    '.ogg',
    '.opus',
    '.wma',
    '.aiff',
    '.amr',
    '.ape',
    '.mid',
    '.midi',
  };

  static const Set<String> _videoExtensions = {
    '.mp4',
    '.mkv',
    '.mov',
    '.avi',
    '.webm',
    '.m4v',
    '.flv',
    '.wmv',
    '.mpeg',
    '.mpg',
    '.mpe',
    '.ogv',
    '.ts',
    '.m2ts',
    '.3gp',
  };

  static const Set<String> _pdfExtensions = {'.pdf'};

  static InternalFileViewerKind detect(String pathOrName) {
    final normalizedName = p.basename(pathOrName).toLowerCase();
    if (_textFileNames.contains(normalizedName)) {
      return InternalFileViewerKind.text;
    }
    final ext = p.extension(pathOrName).toLowerCase();
    if (ext.isEmpty) return InternalFileViewerKind.unsupported;
    if (_pdfExtensions.contains(ext)) return InternalFileViewerKind.pdf;
    if (_imageExtensions.contains(ext)) return InternalFileViewerKind.image;
    if (_audioExtensions.contains(ext)) return InternalFileViewerKind.audio;
    if (_videoExtensions.contains(ext)) return InternalFileViewerKind.video;
    if (_textExtensions.contains(ext)) return InternalFileViewerKind.text;
    return InternalFileViewerKind.unsupported;
  }
}
