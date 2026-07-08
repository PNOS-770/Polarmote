import 'dart:io';

import 'package:dartssh2/dartssh2.dart';

enum PathErrorKind {
  permissionDenied,
  notFound,
  inUse,
  readOnly,
  restricted,
  invalidPath,
  unknown,
}

class PathErrorDiagnostic {
  const PathErrorDiagnostic({
    required this.kind,
    required this.detail,
    this.osCode,
  });

  final PathErrorKind kind;
  final String detail;
  final int? osCode;
}

PathErrorDiagnostic diagnosePathError(
  Object error, {
  String? path,
  bool preferAndroidRestricted = false,
}) {
  final normalizedText = '$error'.toLowerCase();
  int? osCode;
  String detail = '$error';

  if (error is FileSystemException) {
    osCode = error.osError?.errorCode;
    detail = error.message.trim().isEmpty ? detail : error.message.trim();
  } else if (error is OSError) {
    osCode = error.errorCode;
    detail = error.message;
  } else if (error is SftpStatusError) {
    switch (error.code) {
      case SftpStatusCode.noSuchFile:
        return const PathErrorDiagnostic(
          kind: PathErrorKind.notFound,
          detail: 'remote path not found',
        );
      case SftpStatusCode.permissionDenied:
        return const PathErrorDiagnostic(
          kind: PathErrorKind.permissionDenied,
          detail: 'remote permission denied',
        );
      case SftpStatusCode.failure:
        break;
      default:
        break;
    }
    detail = error.toString();
  }

  if (preferAndroidRestricted &&
      (osCode == 13 ||
          normalizedText.contains('permission denied') ||
          normalizedText.contains('operation not permitted'))) {
    return PathErrorDiagnostic(
      kind: PathErrorKind.restricted,
      detail: detail,
      osCode: osCode,
    );
  }

  if (osCode == 2 || osCode == 3 || normalizedText.contains('no such file')) {
    return PathErrorDiagnostic(
      kind: PathErrorKind.notFound,
      detail: detail,
      osCode: osCode,
    );
  }

  if (osCode == 13 ||
      osCode == 5 ||
      normalizedText.contains('permission denied') ||
      normalizedText.contains('access is denied')) {
    return PathErrorDiagnostic(
      kind: PathErrorKind.permissionDenied,
      detail: detail,
      osCode: osCode,
    );
  }

  if (osCode == 30 ||
      normalizedText.contains('read-only file system') ||
      normalizedText.contains('read only file system')) {
    return PathErrorDiagnostic(
      kind: PathErrorKind.readOnly,
      detail: detail,
      osCode: osCode,
    );
  }

  if (osCode == 16 ||
      osCode == 26 ||
      osCode == 32 ||
      normalizedText.contains('resource busy') ||
      normalizedText.contains('text file busy') ||
      normalizedText.contains('being used by another process') ||
      normalizedText.contains('device or resource busy')) {
    return PathErrorDiagnostic(
      kind: PathErrorKind.inUse,
      detail: detail,
      osCode: osCode,
    );
  }

  if (normalizedText.contains('invalid argument') ||
      normalizedText.contains('invalid path') ||
      normalizedText.contains('illegal byte sequence') ||
      normalizedText.contains(
        'filename, directory name, or volume label syntax',
      )) {
    return PathErrorDiagnostic(
      kind: PathErrorKind.invalidPath,
      detail: detail,
      osCode: osCode,
    );
  }

  return PathErrorDiagnostic(
    kind: PathErrorKind.unknown,
    detail: detail,
    osCode: osCode,
  );
}

String formatPathError(
  PathErrorDiagnostic diagnostic, {
  required String languageCode,
  required String operation,
  String? path,
}) {
  final isZh = languageCode == 'zh';
  final targetPath = (path ?? '').trim();
  final pathText = targetPath.isEmpty
      ? ''
      : (isZh ? '，路径: $targetPath' : ', path: $targetPath');
  String reason;
  switch (diagnostic.kind) {
    case PathErrorKind.permissionDenied:
      reason = isZh ? '权限不足' : 'permission denied';
    case PathErrorKind.notFound:
      reason = isZh ? '路径不存在' : 'path not found';
    case PathErrorKind.inUse:
      reason = isZh ? '文件或目录被占用' : 'file or directory is busy';
    case PathErrorKind.readOnly:
      reason = isZh ? '目标为只读文件系统' : 'target is read-only';
    case PathErrorKind.restricted:
      reason = isZh
          ? 'Android 系统限制目录（非 root）'
          : 'Android restricted directory (non-root)';
    case PathErrorKind.invalidPath:
      reason = isZh ? '路径格式无效' : 'invalid path format';
    case PathErrorKind.unknown:
      reason = isZh ? '未知错误' : 'unknown error';
  }
  final detail = diagnostic.detail.trim();
  final detailText = detail.isEmpty
      ? ''
      : (isZh ? '，详情: $detail' : ', detail: $detail');
  if (isZh) {
    return '$operation失败：$reason$pathText$detailText';
  }
  return '$operation failed: $reason$pathText$detailText';
}

