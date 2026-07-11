import 'package:flutter/material.dart';

import '../../models/file_node.dart';

@immutable
class FileIconStyle {
  const FileIconStyle({
    required this.icon,
    required this.color,
    this.svgAssetPath,
  });

  final IconData icon;
  final Color color;
  final String? svgAssetPath;
}

class FileIconResolver {
  static const int _execPermissionMask = 0x49; // 0o111
  static const String _assetBase = 'assets/icons/vscode/';

  static const FileIconStyle _directoryStyle = FileIconStyle(
    icon: Icons.folder,
    color: Color(0xFFB7791F),
    svgAssetPath: '${_assetBase}default_folder.svg',
  );
  static const FileIconStyle _defaultStyle = FileIconStyle(
    icon: Icons.insert_drive_file,
    color: Color(0xFF607D8B),
    svgAssetPath: '${_assetBase}default_file.svg',
  );

  static const FileIconStyle _imageStyle = FileIconStyle(
    icon: Icons.image,
    color: Color(0xFF2F80ED),
    svgAssetPath: '${_assetBase}file_type_image.svg',
  );
  static const FileIconStyle _videoStyle = FileIconStyle(
    icon: Icons.movie,
    color: Color(0xFF9B51E0),
    svgAssetPath: '${_assetBase}file_type_video.svg',
  );
  static const FileIconStyle _audioStyle = FileIconStyle(
    icon: Icons.audiotrack,
    color: Color(0xFF27AE60),
    svgAssetPath: '${_assetBase}file_type_audio.svg',
  );
  static const FileIconStyle _archiveStyle = FileIconStyle(
    icon: Icons.archive,
    color: Color(0xFF8D6E63),
    svgAssetPath: '${_assetBase}file_type_zip.svg',
  );

  static const FileIconStyle _pdfStyle = FileIconStyle(
    icon: Icons.picture_as_pdf,
    color: Color(0xFFD32F2F),
    svgAssetPath: '${_assetBase}file_type_pdf.svg',
  );
  static const FileIconStyle _wordStyle = FileIconStyle(
    icon: Icons.article,
    color: Color(0xFF1565C0),
    svgAssetPath: '${_assetBase}file_type_word.svg',
  );
  static const FileIconStyle _excelStyle = FileIconStyle(
    icon: Icons.table_chart,
    color: Color(0xFF2E7D32),
    svgAssetPath: '${_assetBase}file_type_excel.svg',
  );
  static const FileIconStyle _pptStyle = FileIconStyle(
    icon: Icons.slideshow,
    color: Color(0xFFEF6C00),
    svgAssetPath: '${_assetBase}file_type_powerpoint.svg',
  );
  static const FileIconStyle _markdownStyle = FileIconStyle(
    icon: Icons.notes,
    color: Color(0xFF546E7A),
    svgAssetPath: '${_assetBase}file_type_markdown.svg',
  );
  static const FileIconStyle _textStyle = FileIconStyle(
    icon: Icons.subject,
    color: Color(0xFF607D8B),
  );

  static const FileIconStyle _dartStyle = FileIconStyle(
    icon: Icons.flutter_dash,
    color: Color(0xFF42A5F5),
    svgAssetPath: '${_assetBase}file_type_dartlang.svg',
  );
  static const FileIconStyle _rustStyle = FileIconStyle(
    icon: Icons.precision_manufacturing,
    color: Color(0xFF8D6E63),
    svgAssetPath: '${_assetBase}file_type_rust.svg',
  );
  static const FileIconStyle _pythonStyle = FileIconStyle(
    icon: Icons.smart_toy,
    color: Color(0xFF3776AB),
    svgAssetPath: '${_assetBase}file_type_python.svg',
  );
  static const FileIconStyle _javascriptStyle = FileIconStyle(
    icon: Icons.data_object,
    color: Color(0xFFF1E05A),
    svgAssetPath: '${_assetBase}file_type_js_official.svg',
  );
  static const FileIconStyle _typescriptStyle = FileIconStyle(
    icon: Icons.data_object,
    color: Color(0xFF3178C6),
    svgAssetPath: '${_assetBase}file_type_typescript_official.svg',
  );
  static const FileIconStyle _javaStyle = FileIconStyle(
    icon: Icons.coffee,
    color: Color(0xFFE57373),
    svgAssetPath: '${_assetBase}file_type_java.svg',
  );
  static const FileIconStyle _kotlinStyle = FileIconStyle(
    icon: Icons.coffee,
    color: Color(0xFF7E57C2),
    svgAssetPath: '${_assetBase}file_type_kotlin.svg',
  );
  static const FileIconStyle _goStyle = FileIconStyle(
    icon: Icons.bolt,
    color: Color(0xFF00ACC1),
    svgAssetPath: '${_assetBase}file_type_go.svg',
  );
  static const FileIconStyle _cStyle = FileIconStyle(
    icon: Icons.memory,
    color: Color(0xFF5C6BC0),
    svgAssetPath: '${_assetBase}file_type_c.svg',
  );
  static const FileIconStyle _cppStyle = FileIconStyle(
    icon: Icons.memory,
    color: Color(0xFF3F51B5),
    svgAssetPath: '${_assetBase}file_type_cpp.svg',
  );
  static const FileIconStyle _codeStyle = FileIconStyle(
    icon: Icons.code,
    color: Color(0xFF2F80ED),
  );

  static const FileIconStyle _htmlStyle = FileIconStyle(
    icon: Icons.web,
    color: Color(0xFFE34F26),
    svgAssetPath: '${_assetBase}file_type_html.svg',
  );
  static const FileIconStyle _cssStyle = FileIconStyle(
    icon: Icons.style,
    color: Color(0xFF1572B6),
    svgAssetPath: '${_assetBase}file_type_css.svg',
  );
  static const FileIconStyle _scssStyle = FileIconStyle(
    icon: Icons.palette,
    color: Color(0xFFCC6699),
    svgAssetPath: '${_assetBase}file_type_scss.svg',
  );
  static const FileIconStyle _vueStyle = FileIconStyle(
    icon: Icons.web_asset,
    color: Color(0xFF41B883),
    svgAssetPath: '${_assetBase}file_type_vue.svg',
  );

  static const FileIconStyle _jsonStyle = FileIconStyle(
    icon: Icons.data_object,
    color: Color(0xFFF0DB4F),
    svgAssetPath: '${_assetBase}file_type_json_official.svg',
  );
  static const FileIconStyle _yamlStyle = FileIconStyle(
    icon: Icons.segment,
    color: Color(0xFFCB4B16),
    svgAssetPath: '${_assetBase}file_type_yaml_official.svg',
  );
  static const FileIconStyle _tomlStyle = FileIconStyle(
    icon: Icons.tune,
    color: Color(0xFF7F8C8D),
    svgAssetPath: '${_assetBase}file_type_toml.svg',
  );
  static const FileIconStyle _xmlStyle = FileIconStyle(
    icon: Icons.code,
    color: Color(0xFF8D99AE),
    svgAssetPath: '${_assetBase}file_type_xml.svg',
  );
  static const FileIconStyle _configStyle = FileIconStyle(
    icon: Icons.tune,
    color: Color(0xFF78909C),
    svgAssetPath: '${_assetBase}file_type_config.svg',
  );

  static const FileIconStyle _databaseStyle = FileIconStyle(
    icon: Icons.storage,
    color: Color(0xFF16A085),
    svgAssetPath: '${_assetBase}file_type_sql.svg',
  );
  static const FileIconStyle _scriptStyle = FileIconStyle(
    icon: Icons.terminal,
    color: Color(0xFF34495E),
    svgAssetPath: '${_assetBase}file_type_shell.svg',
  );
  static const FileIconStyle _powershellStyle = FileIconStyle(
    icon: Icons.terminal,
    color: Color(0xFF0288D1),
    svgAssetPath: '${_assetBase}file_type_powershell.svg',
  );
  static const FileIconStyle _dockerStyle = FileIconStyle(
    icon: Icons.inventory_2,
    color: Color(0xFF2496ED),
    svgAssetPath: '${_assetBase}file_type_docker.svg',
  );
  static const FileIconStyle _gitStyle = FileIconStyle(
    icon: Icons.source,
    color: Color(0xFFF1502F),
    svgAssetPath: '${_assetBase}file_type_git.svg',
  );
  static const FileIconStyle _lockStyle = FileIconStyle(
    icon: Icons.lock,
    color: Color(0xFF546E7A),
    svgAssetPath: '${_assetBase}file_type_key.svg',
  );
  static const FileIconStyle _keyStyle = FileIconStyle(
    icon: Icons.key,
    color: Color(0xFF6D4C41),
    svgAssetPath: '${_assetBase}file_type_key.svg',
  );
  static const FileIconStyle _certificateStyle = FileIconStyle(
    icon: Icons.verified,
    color: Color(0xFF00897B),
    svgAssetPath: '${_assetBase}file_type_cert.svg',
  );
  static const FileIconStyle _fontStyle = FileIconStyle(
    icon: Icons.font_download,
    color: Color(0xFF455A64),
    svgAssetPath: '${_assetBase}file_type_font.svg',
  );
  static const FileIconStyle _logStyle = FileIconStyle(
    icon: Icons.receipt_long,
    color: Color(0xFF6D4C41),
    svgAssetPath: '${_assetBase}file_type_log.svg',
  );
  static const FileIconStyle _binaryStyle = FileIconStyle(
    icon: Icons.data_array,
    color: Color(0xFF455A64),
    svgAssetPath: '${_assetBase}file_type_binary.svg',
  );
  static const FileIconStyle _buildStyle = FileIconStyle(
    icon: Icons.build,
    color: Color(0xFF6D4C41),
  );
  static const FileIconStyle _settingsStyle = FileIconStyle(
    icon: Icons.settings,
    color: Color(0xFF5D6D7E),
    svgAssetPath: '${_assetBase}file_type_editorconfig.svg',
  );

  static const Set<String> _execExt = {
    'exe',
    'msi',
    'appimage',
    'com',
    'bin',
    'out',
  };

  static const Map<String, FileIconStyle> _styleByExtension = {
    'jpg': _imageStyle,
    'jpeg': _imageStyle,
    'png': _imageStyle,
    'gif': _imageStyle,
    'bmp': _imageStyle,
    'webp': _imageStyle,
    'svg': _imageStyle,
    'ico': _imageStyle,
    'heic': _imageStyle,
    'heif': _imageStyle,

    'mp4': _videoStyle,
    'mkv': _videoStyle,
    'mov': _videoStyle,
    'avi': _videoStyle,
    'wmv': _videoStyle,
    'flv': _videoStyle,
    'webm': _videoStyle,
    'm4v': _videoStyle,

    'mp3': _audioStyle,
    'wav': _audioStyle,
    'flac': _audioStyle,
    'aac': _audioStyle,
    'ogg': _audioStyle,
    'm4a': _audioStyle,
    'wma': _audioStyle,

    'zip': _archiveStyle,
    'rar': _archiveStyle,
    '7z': _archiveStyle,
    'tar': _archiveStyle,
    'gz': _archiveStyle,
    'tgz': _archiveStyle,
    'bz2': _archiveStyle,
    'xz': _archiveStyle,
    'zst': _archiveStyle,

    'pdf': _pdfStyle,
    'doc': _wordStyle,
    'docx': _wordStyle,
    'odt': _wordStyle,
    'xls': _excelStyle,
    'xlsx': _excelStyle,
    'csv': _excelStyle,
    'ods': _excelStyle,
    'ppt': _pptStyle,
    'pptx': _pptStyle,
    'odp': _pptStyle,
    'md': _markdownStyle,
    'markdown': _markdownStyle,
    'txt': _textStyle,
    'log': _logStyle,

    'db': _databaseStyle,
    'sqlite': _databaseStyle,
    'sqlite3': _databaseStyle,
    'sql': _databaseStyle,

    'json': _jsonStyle,
    'yaml': _yamlStyle,
    'yml': _yamlStyle,
    'toml': _tomlStyle,
    'ini': _configStyle,
    'xml': _xmlStyle,
    'env': _configStyle,
    'conf': _configStyle,
    'cfg': _configStyle,

    'pem': _certificateStyle,
    'crt': _certificateStyle,
    'cer': _certificateStyle,
    'pfx': _certificateStyle,
    'p12': _certificateStyle,
    'key': _keyStyle,
    'pub': _keyStyle,
    'asc': _keyStyle,
    'sig': _lockStyle,

    'ttf': _fontStyle,
    'otf': _fontStyle,
    'woff': _fontStyle,
    'woff2': _fontStyle,

    'dart': _dartStyle,
    'rs': _rustStyle,
    'py': _pythonStyle,
    'js': _javascriptStyle,
    'jsx': _javascriptStyle,
    'ts': _typescriptStyle,
    'tsx': _typescriptStyle,
    'java': _javaStyle,
    'kt': _kotlinStyle,
    'kts': _kotlinStyle,
    'go': _goStyle,
    'c': _cStyle,
    'h': _cStyle,
    'cpp': _cppStyle,
    'hpp': _cppStyle,
    'cc': _cppStyle,
    'swift': _codeStyle,
    'php': _codeStyle,
    'rb': _codeStyle,
    'cs': _codeStyle,

    'html': _htmlStyle,
    'htm': _htmlStyle,
    'css': _cssStyle,
    'scss': _scssStyle,
    'sass': _scssStyle,
    'vue': _vueStyle,

    'sh': _scriptStyle,
    'bash': _scriptStyle,
    'zsh': _scriptStyle,
    'fish': _scriptStyle,
    'ps1': _powershellStyle,
    'bat': _powershellStyle,
    'cmd': _powershellStyle,
    'gradle': _buildStyle,
    'mk': _buildStyle,

    'bin': _binaryStyle,
    'dat': _binaryStyle,
    'dmp': _binaryStyle,
  };

  static const Set<String> _specialSettingsNames = {
    '.gitignore',
    '.gitattributes',
    '.editorconfig',
    '.env',
    '.env.local',
    '.npmrc',
    '.yarnrc',
  };

  static const Map<String, FileIconStyle> _specialFileStyles = {
    'dockerfile': _dockerStyle,
    '.dockerignore': _dockerStyle,
    '.gitignore': _gitStyle,
    '.gitattributes': _gitStyle,
    'package.json': _javascriptStyle,
    'package-lock.json': _lockStyle,
    'yarn.lock': _lockStyle,
    'pnpm-lock.yaml': _lockStyle,
    'cargo.toml': _rustStyle,
    'cargo.lock': _lockStyle,
    'pubspec.yaml': _dartStyle,
    'makefile': _buildStyle,
    'cmakelists.txt': _buildStyle,
    'build.gradle': _buildStyle,
    'build.gradle.kts': _buildStyle,
    'gradle.properties': _buildStyle,
    'poetry.lock': _lockStyle,
    'pipfile': _pythonStyle,
  };

  static FileIconStyle resolve(FileNode node) {
    if (node.isDirectory) {
      return _directoryStyle;
    }

    final name = node.name.trim();
    final lower = name.toLowerCase();
    final ext = _extension(lower);

    if (_isReadme(lower)) return _markdownStyle;

    final special = _specialFileStyles[lower];
    if (special != null) return special;

    if (_specialSettingsNames.contains(lower)) return _settingsStyle;

    final mapped = _styleByExtension[ext];
    if (mapped != null) return mapped;

    if (_isExecutable(node, ext)) return _scriptStyle;

    return _defaultStyle;
  }

  static bool _isReadme(String lower) {
    return lower == 'readme' || lower.startsWith('readme.');
  }

  static String _extension(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot <= 0 || dot == fileName.length - 1) {
      return '';
    }
    return fileName.substring(dot + 1);
  }

  static bool _isExecutable(FileNode node, String ext) {
    final permissions = node.permissions;
    if (permissions != null && (permissions & _execPermissionMask) != 0) {
      return true;
    }
    return _execExt.contains(ext);
  }
}

