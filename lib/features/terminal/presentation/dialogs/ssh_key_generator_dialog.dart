import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:safe_layout_x/safe_layout_x.dart';

import '../../../../shared/constants/app_string.dart';
import '../../../../shared/design_system/design_system.dart';
import '../../models/host_entry.dart';
import '../../state/ssh/ssh_key_deployer.dart';
import '../../state/ssh/ssh_key_generator.dart';
import '../../state/terminal_app_state.dart';
import '../common/host_tree_row.dart';
import '../common/terminal_localization.dart';
import 'terminal_dialogs.dart';

Future<void> showSshKeyGeneratorDialog(
  BuildContext context,
  TerminalAppState appState,
) async {
  var selectedAlgorithm = SshKeyAlgorithm.ed25519;
  final commentController = TextEditingController(text: '');
  final passphraseController = TextEditingController(text: '');
  final passphraseConfirmController = TextEditingController(text: '');
  var saveDir = '';
  GeneratedSshKey? generatedKey;
  var isGenerating = false;
  var copiedPublicKey = false;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setState) {
          final screenWidth = MediaQuery.of(context).size.width;
          final dialogWidth = (screenWidth - 48).clamp(420.0, 640.0);

          return AlertDialog(
            backgroundColor: AppColors.cardBackground,
            shape: RoundedRectangleBorder(
              borderRadius: AppRadius.radiusDialog,
            ),
            title: Row(
              children: [
                const Icon(Icons.vpn_key, size: 20, color: AppColors.accent),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  t(context, AppStrings.values.sshKeyGenerate),
                  style: AppTextStyles.h4,
                ),
              ],
            ),
            content: SizedBox(
              width: dialogWidth,
              child: SingleChildScrollView(
                child: generatedKey != null
                    ? _buildKeyResultView(
                        context, appState, generatedKey!, copiedPublicKey, setState, () {
                        setState(() {
                          generatedKey = null;
                          copiedPublicKey = false;
                        });
                      })
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            t(context, AppStrings.values.sshKeyType),
                            style: AppTextStyles.h5.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          _buildAlgorithmSelector(
                            context,
                            selectedAlgorithm,
                            (algo) {
                              setState(() => selectedAlgorithm = algo);
                            },
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          AppTextField(
                            label: t(context, AppStrings.values.sshKeyComment),
                            controller: commentController,
                            hint: t(context, AppStrings.values.sshKeyCommentHint),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          AppTextField(
                            label: t(context, AppStrings.values.sshKeyPassphrase),
                            controller: passphraseController,
                            obscureText: true,
                          ),
                          const SizedBox(height: AppSpacing.md),
                          AppTextField(
                            label: t(context, AppStrings.values.sshKeyPassphraseConfirm),
                            controller: passphraseConfirmController,
                            obscureText: true,
                          ),
                          if (passphraseController.text !=
                                  passphraseConfirmController.text &&
                              passphraseConfirmController.text.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                t(context, AppStrings.values.sshKeyPassphraseMismatch),
                                style: AppTextStyles.error,
                              ),
                            ),
                          const SizedBox(height: AppSpacing.lg),
                          Text(
                            t(context, AppStrings.values.sshKeySaveLocation),
                            style: AppTextStyles.h5.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Row(
                            children: [
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: AppColors.border),
                                    borderRadius: AppRadius.radiusSM,
                                  ),
                                  child: Text(
                                    saveDir.isEmpty
                                        ? t(context, AppStrings.values.noKeySelected)
                                        : saveDir,
                                    style: AppTextStyles.caption.copyWith(
                                      color: saveDir.isEmpty
                                          ? AppColors.textTertiary
                                          : AppColors.textPrimary,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              PrimaryButton(
                                onPressed: () async {
                                  final location = await getDirectoryPath();
                                  if (location != null) {
                                    setState(() => saveDir = location);
                                  }
                                },
                                label: t(context, AppStrings.values.sshKeyBrowse),
                                size: ButtonSize.small,
                              ),
                            ],
                          ),
                        ],
                      ),
              ),
            ),
            actionsPadding: const EdgeInsets.all(AppSpacing.lg),
            actions: [
              if (generatedKey != null) ...[
                SecondaryButton(
                  onPressed: () {
                    setState(() {
                      generatedKey = null;
                      copiedPublicKey = false;
                    });
                  },
                  label: t(context, AppStrings.values.back),
                  size: ButtonSize.small,
                ),
                const SizedBox(width: AppSpacing.sm),
                SecondaryButton(
                  onPressed: () async {
                    final privKeyPath = saveDir.isNotEmpty
                        ? p.join(saveDir, 'id_${_keyFilePrefix(selectedAlgorithm)}')
                        : null;
                    final result = await _showHostSelectionDialog(
                      context, appState,
                    );
                    if (result == null || !context.mounted) return;
                    if (result == _HostSelectionResult.newHost) {
                      final hostName = generatedKey!.comment.isNotEmpty
                          ? generatedKey!.comment
                          : 'key-${generatedKey!.algorithm.name}';
                      showHostDialog(
                        context,
                        appState,
                        host: HostEntry(
                          id: 'key-${DateTime.now().microsecondsSinceEpoch}',
                          name: hostName,
                          host: '',
                          port: 22,
                          username: '',
                          group: '',
                          authType: AuthType.key,
                          privateKeyPath: privKeyPath,
                        ),
                      );
                    } else {
                      final targetHost = result.host!;
                      final passphrase = passphraseController.text.trim();
                      final updated = targetHost.copyWith(
                        authType: AuthType.key,
                        privateKeyPath: privKeyPath,
                        password: null,
                        privateKeyPassphrase: passphrase.isNotEmpty ? passphrase : null,
                      );
                      appState.updateHost(updated);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            t(
                              context,
                              AppStrings.values.sshKeyAppliedToHost,
                              params: {'host': updated.name},
                            ),
                          ),
                        ),
                      );
                    }
                  },
                  label: t(context, AppStrings.values.sshKeyAddToHost),
                  size: ButtonSize.small,
                ),
                const SizedBox(width: AppSpacing.sm),
                PrimaryButton(
                  onPressed: () async {
                    final keyLine = generatedKey!.publicKeyLine;
                    final privKeyPath = saveDir.isNotEmpty
                        ? p.join(saveDir, 'id_${_keyFilePrefix(selectedAlgorithm)}')
                        : null;
await _performDeployFlow(
  context,
  appState,
  keyLine,
  privKeyPath,
  selectedAlgorithm,
  generatedKey!.comment,
  passphraseController.text.trim(),
);
                  },
                  label: t(context, AppStrings.values.sshKeyDeployToHost),
                  size: ButtonSize.small,
                ),
              ] else ...[
                AppTextButton(
                  onPressed: () => Navigator.pop(context),
                  label: t(context, AppStrings.values.cancel),
                  size: ButtonSize.small,
                ),
                PrimaryButton(
                  onPressed: saveDir.isEmpty
                      ? null
                      : (isGenerating
                          ? null
                          : () async {
                              final passphrase =
                                  passphraseController.text.trim();
                              final passphraseConfirm =
                                  passphraseConfirmController.text.trim();
                              if (passphrase != passphraseConfirm) {
                                return;
                              }
                              final comment =
                                  commentController.text.trim();
                              if (comment.isEmpty) {
                                commentController.text =
                                    '${Platform.environment['USER'] ?? Platform.environment['USERNAME'] ?? 'user'}@${Platform.environment['COMPUTERNAME'] ?? 'localhost'}';
                              }

                              setState(() => isGenerating = true);

                              try {
                                final key = await generateSshKey(
                                  algorithm: selectedAlgorithm,
                                  comment: comment.isNotEmpty
                                      ? comment
                                      : commentController.text,
                                  passphrase: passphrase.isNotEmpty
                                      ? passphrase
                                      : null,
                                );

                                final prefix =
                                    _keyFilePrefix(selectedAlgorithm);
                                final privPath = p.join(
                                  saveDir,
                                  'id_$prefix',
                                );
                                final pubPath = p.join(
                                  saveDir,
                                  'id_$prefix.pub',
                                );
                                final privFile = File(privPath);
                                await privFile.writeAsString(
                                  key.privateKeyPem,
                                );

                                final pubFile = File(pubPath);
                                await pubFile.writeAsString(
                                  '${key.publicKeyLine}\n',
                                );

                                setState(() {
                                  generatedKey = key;
                                  isGenerating = false;
                                });
                              } catch (e) {
                                setState(() => isGenerating = false);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        '${t(context, AppStrings.values.error)}$e',
                                      ),
                                    ),
                                  );
                                }
                              }
                            }),
                  label: isGenerating
                      ? t(context, AppStrings.values.sshKeyGenerating)
                      : t(context, AppStrings.values.sshKeyGenerate),
                  size: ButtonSize.medium,
                  loading: isGenerating,
                ),
              ],
            ],
          );
        },
      );
    },
  );
}

String _keyFilePrefix(SshKeyAlgorithm algo) {
  switch (algo) {
    case SshKeyAlgorithm.ed25519:
      return 'ed25519';
    case SshKeyAlgorithm.rsa2048:
    case SshKeyAlgorithm.rsa4096:
      return 'rsa';
    case SshKeyAlgorithm.ecdsaP256:
      return 'ecdsa256';
    case SshKeyAlgorithm.ecdsaP384:
      return 'ecdsa384';
    case SshKeyAlgorithm.ecdsaP521:
      return 'ecdsa521';
  }
}

Widget _buildAlgorithmSelector(
  BuildContext context,
  SshKeyAlgorithm selected,
  ValueChanged<SshKeyAlgorithm> onChanged,
) {
  final items = [
    (SshKeyAlgorithm.ed25519, AppStrings.values.sshKeyEd25519, Icons.shield),
    (SshKeyAlgorithm.rsa2048, AppStrings.values.sshKeyRsa2048, Icons.key),
    (SshKeyAlgorithm.rsa4096, AppStrings.values.sshKeyRsa4096, Icons.key),
    (SshKeyAlgorithm.ecdsaP256, AppStrings.values.sshKeyEcdsa256, Icons.lock),
    (SshKeyAlgorithm.ecdsaP384, AppStrings.values.sshKeyEcdsa384, Icons.lock),
    (SshKeyAlgorithm.ecdsaP521, AppStrings.values.sshKeyEcdsa521, Icons.lock),
  ];

  return Wrap(
    spacing: AppSpacing.sm,
    runSpacing: AppSpacing.sm,
    children: items.map((item) {
      final (algo, text, icon) = item;
      final isSelected = algo == selected;
      return InkWell(
        onTap: () => onChanged(algo),
        borderRadius: AppRadius.radiusSM,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.primaryLight.withAlpha(30)
                : AppColors.backgroundGrey,
            borderRadius: AppRadius.radiusSM,
            border: Border.all(
              color: isSelected ? AppColors.accent : AppColors.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: isSelected ? AppColors.accent : null),
              const SizedBox(width: 6),
              Text(
                t(context, text),
                style: AppTextStyles.labelSmall.copyWith(
                  color: isSelected ? AppColors.accent : AppColors.textPrimary,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    }).toList(),
  );
}

Future<void> _performDeployFlow(
  BuildContext context,
  TerminalAppState appState,
  String keyLine,
  String? privKeyPath,
  SshKeyAlgorithm algorithm,
  String keyComment,
  String passphrase,
) async {
  final selection = await _showHostSelectionDialog(context, appState);
  if (selection == null || !context.mounted) return;

  if (selection == _HostSelectionResult.newHost) {
    final hostName = keyComment.isNotEmpty
        ? keyComment
        : 'key-${algorithm.name}';
    showHostDialog(
      context,
      appState,
      host: HostEntry(
        id: 'key-${DateTime.now().microsecondsSinceEpoch}',
        name: hostName,
        host: '',
        port: 22,
        username: '',
        group: '',
        authType: AuthType.key,
        privateKeyPath: privKeyPath,
      ),
    );
    return;
  }

  final host = selection.host!;
  const maxRetries = 3;

  for (var attempt = 0; attempt < maxRetries; attempt++) {
    if (!context.mounted) return;

    var password = (host.password ?? '').trim();
    if (password.isEmpty) {
      final stored = await appState.readHostSecret(host.id);
      password = (stored?.password ?? '').trim();
    }

    if (password.isEmpty) {
      if (!context.mounted) return;
      final retryMsg = attempt > 0 ? t(context, AppStrings.values.sshKeyDeployRetry) : null;
      final pw = await _showPasswordDialog(context, host,
        errorMessage: retryMsg,
      );
      if (pw == null || !context.mounted) return;
      password = pw;
    }

    if (!context.mounted) return;
    showLoadingDialog(
      context,
      message: t(context, AppStrings.values.sshKeyDeploying),
    );

    final deployResult = await deployPublicKey(
      host: host.host,
      port: host.port,
      username: host.username,
      password: password,
      publicKeyLine: keyLine,
    );

    if (!context.mounted) {
      return;
    }
    try { Navigator.of(context, rootNavigator: true).pop(); } catch (_) {}

    if (deployResult.success) {
      final updated = host.copyWith(
        authType: AuthType.key,
        privateKeyPath: privKeyPath,
        password: null,
        privateKeyPassphrase: passphrase.isNotEmpty ? passphrase : null,
      );
      appState.updateHost(updated);
      final successMsg = t(context, AppStrings.values.sshKeyDeploySuccess, params: {'host': updated.name});
      final successTitle = t(context, AppStrings.values.done);
      BannerManager.show(
        BannerData(
          id: 'deploy-${DateTime.now().microsecondsSinceEpoch}',
          type: BannerType.success,
          title: successTitle,
          message: successMsg,
        ),
      );
      Navigator.of(context).pop();
      return;
    }

    if (context.mounted && attempt < maxRetries - 1) {
      BannerManager.show(
        BannerData(
          id: 'deploy-retry-${DateTime.now().microsecondsSinceEpoch}',
          type: BannerType.error,
          title: t(context, AppStrings.values.failed),
          message: t(context, AppStrings.values.sshKeyDeployFailed, params: {'error': deployResult.error ?? 'unknown'}),
        ),
      );
    }
  }

  if (context.mounted) {
    BannerManager.show(
      BannerData(
        id: 'deploy-exhausted-${DateTime.now().microsecondsSinceEpoch}',
        type: BannerType.error,
        title: t(context, AppStrings.values.failed),
        message: t(context, AppStrings.values.sshKeyDeployFailed, params: {'error': 'max retries exceeded'}),
      ),
    );
  }
}

Widget _buildKeyResultView(
  BuildContext context,
  TerminalAppState appState,
  GeneratedSshKey key,
  bool copiedPublicKey,
  StateSetter setState,
  VoidCallback onBack,
) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Row(
        children: [
          const Icon(Icons.check_circle, color: AppColors.success, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Text(
            '${t(context, AppStrings.values.sshKeyGenerated)} - ${key.algorithm.name}',
            style: AppTextStyles.h5,
          ),
        ],
      ),
      const SizedBox(height: AppSpacing.lg),
      Text(
        t(context, AppStrings.values.sshKeyFingerprint),
        style: AppTextStyles.h5.copyWith(fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: AppSpacing.xs),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.backgroundGrey,
          borderRadius: AppRadius.radiusSM,
        ),
        child: SelectableText(
          'SHA256:${key.fingerprint}',
          style: AppTextStyles.code.copyWith(fontSize: 12),
        ),
      ),
      const SizedBox(height: AppSpacing.md),
      Text(
        t(context, AppStrings.values.sshKeyPublicKey),
        style: AppTextStyles.h5.copyWith(fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: AppSpacing.xs),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.backgroundGrey,
          borderRadius: AppRadius.radiusSM,
        ),
        child: SelectableText(
          key.publicKeyLine,
          style: AppTextStyles.code.copyWith(fontSize: 11),
        ),
      ),
      const SizedBox(height: AppSpacing.md),
      Center(
        child: AppTextButton(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: key.publicKeyLine));
            setState(() => copiedPublicKey = true);
            Future.delayed(const Duration(seconds: 2), () {
              if (context.mounted) setState(() => copiedPublicKey = false);
            });
          },
          label: copiedPublicKey
              ? t(context, AppStrings.values.sshKeyCopied)
              : t(context, AppStrings.values.sshKeyCopyPublicKey),
          size: ButtonSize.small,
        ),
      ),
    ],
  );
}

class _HostSelectionResult {
  const _HostSelectionResult._(this.host);
  static const newHost = _HostSelectionResult._(null);
  final HostEntry? host;
}

List<TreeViewNode<HostEntry>> _buildHostTreeNodes(List<HostEntry> hosts) {
  final root = TreeViewNode<HostEntry>(key: '', label: '', children: []);
  for (final host in hosts) {
    final segments = host.group
        .split(RegExp(r'[\\/]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList(growable: false);
    var cursor = root;
    for (final segment in segments) {
      var child = cursor.children.cast<TreeViewNode<HostEntry>?>().firstWhere(
        (c) => c!.label == segment,
        orElse: () => null,
      );
      if (child == null) {
        child = TreeViewNode<HostEntry>(
          key: cursor.key.isEmpty ? segment : '${cursor.key}/$segment',
          label: segment,
          children: [],
          isExpanded: true,
        );
        cursor.children.add(child);
      }
      cursor = child;
    }
    cursor.children.add(TreeViewNode<HostEntry>(
      key: host.id,
      label: host.name,
      value: host,
    ));
  }
  return root.children;
}

void _sortHostTreeNodes(List<TreeViewNode<HostEntry>> nodes) {
  for (final node in nodes) {
    if (!node.isLeaf) {
      _sortHostTreeNodes(node.children);
      node.children.sort((a, b) {
        if (a.isLeaf == b.isLeaf) {
          return a.label.toLowerCase().compareTo(b.label.toLowerCase());
        }
        return a.isLeaf ? 1 : -1;
      });
    }
  }
}

bool _filterHostTreeNodes(List<TreeViewNode<HostEntry>> nodes, String query) {
  nodes.removeWhere((n) {
    if (!n.isLeaf) {
      _filterHostTreeNodes(n.children, query);
      return n.children.isEmpty;
    }
    final host = n.value;
    return host == null || !(
      host.name.toLowerCase().contains(query) ||
      host.host.toLowerCase().contains(query) ||
      host.username.toLowerCase().contains(query)
    );
  });
  return nodes.isNotEmpty;
}

Future<_HostSelectionResult?> _showHostSelectionDialog(
  BuildContext context,
  TerminalAppState appState,
) async {
  final sshHosts = appState.hosts
      .where((h) => h.connectionType == ConnectionType.ssh)
      .toList();
  var searchQuery = '';

  return showDialog<_HostSelectionResult>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setState) {
          var roots = _buildHostTreeNodes(sshHosts);
          _sortHostTreeNodes(roots);
          if (searchQuery.isNotEmpty) {
            _filterHostTreeNodes(roots, searchQuery.toLowerCase());
          }

          return AlertDialog(
            backgroundColor: AppColors.cardBackground,
            shape: RoundedRectangleBorder(
              borderRadius: AppRadius.radiusDialog,
            ),
            title: Text(
              t(context, AppStrings.values.sshKeySelectHost),
              style: AppTextStyles.h4,
            ),
            content: SizedBox(
              width: 400,
              height: 420,
              child: Column(
                children: [
                  AppTextField(
                    hint: t(context, AppStrings.values.search),
                    prefixIcon: const Icon(Icons.search, size: 16),
                    onChanged: (v) => setState(() => searchQuery = v),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  if (searchQuery.isEmpty)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.add_circle_outline, color: AppColors.accent),
                      title: Text(
                        t(context, AppStrings.values.sshKeyNewHost),
                        style: AppTextStyles.body.copyWith(color: AppColors.accent),
                      ),
                      onTap: () => Navigator.pop(
                        context,
                        _HostSelectionResult.newHost,
                      ),
                    ),
                  if (searchQuery.isEmpty)
                    const Divider(height: 1),
                  Expanded(
                    child: TreeView<HostEntry>(
                      roots: roots,
                      showCheckboxes: false,
                      indentWidth: 14,
                      itemBuilder: (context, node, state, depth) {
                        if (!node.isLeaf) {
                          return InkWell(
                            onTap: state.onToggleExpand,
                            child: Padding(
                              padding: EdgeInsets.only(left: depth * 14.0),
                              child: SizedBox(
                                height: 32,
                                child: Row(
                                  children: [
                                    Icon(
                                      state.isExpanded
                                          ? Icons.expand_more
                                          : Icons.chevron_right,
                                      size: 18,
                                      color: AppColors.textSecondary,
                                    ),
                                    const SizedBox(width: 4),
                                    Icon(
                                      Icons.folder_outlined,
                                      size: 16,
                                      color: AppColors.textSecondary,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      node.label,
                                      style: AppTextStyles.body.copyWith(
                                        color: AppColors.textSecondary,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }
                        final host = node.value;
                        if (host == null) return const SizedBox.shrink();
                        return HostTreeRow(
                          appState: appState,
                          host: host,
                          depth: depth,
                          lightTheme: true,
                          showStatus: false,
                          showPin: false,
                          showProbe: false,
                          readOnly: true,
                          onTap: () => Navigator.pop(
                            context,
                            _HostSelectionResult._(host),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              AppTextButton(
                onPressed: () => Navigator.pop(context),
                label: t(context, AppStrings.values.cancel),
                size: ButtonSize.small,
              ),
            ],
          );
        },
      );
    },
  );
}

Future<String?> _showPasswordDialog(
  BuildContext context,
  HostEntry host, {
  String? errorMessage,
}) async {
  final controller = TextEditingController();
  String? localError = errorMessage;

  return showDialog<String>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            backgroundColor: AppColors.cardBackground,
            shape: RoundedRectangleBorder(
              borderRadius: AppRadius.radiusDialog,
            ),
            title: Row(
              children: [
                const Icon(Icons.lock, size: 20, color: AppColors.accent),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    t(context, AppStrings.values.sshKeyDeployTitle),
                    style: AppTextStyles.h5,
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t(context, AppStrings.values.sshKeyPasswordRequired),
                  style: AppTextStyles.body,
                ),
                const SizedBox(height: AppSpacing.sm),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.backgroundGrey,
                    borderRadius: AppRadius.radiusSM,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.computer, size: 14, color: AppColors.textSecondary),
                      const SizedBox(width: 6),
                      Text(
                        '${host.username}@${host.host}:${host.port}',
                        style: AppTextStyles.label,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  controller: controller,
                  obscureText: true,
                  hint: t(context, AppStrings.values.password),
                  errorText: localError,
                  autofocus: true,
                ),
              ],
            ),
            actionsPadding: const EdgeInsets.all(AppSpacing.lg),
            actions: [
              AppTextButton(
                onPressed: () => Navigator.pop(context),
                label: t(context, AppStrings.values.cancel),
                size: ButtonSize.small,
              ),
              PrimaryButton(
                onPressed: () {
                  final pw = controller.text;
                  if (pw.isEmpty) {
                    setState(() {
                      localError = t(context, AppStrings.values.sshKeyPasswordEmpty);
                    });
                    return;
                  }
                  Navigator.pop(context, pw.trim());
                },
                label: t(context, AppStrings.values.confirm),
                size: ButtonSize.small,
              ),
            ],
          );
        },
      );
    },
  );
}

