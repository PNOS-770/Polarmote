import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

const String _newSessionIconAsset = 'assets/icons/ui_actions/new_session.svg';
const String _selectKeyIconAsset = 'assets/icons/ui_actions/select_key.svg';
const String _connectionSshIconAsset =
    'assets/icons/ui_actions/connection_ssh.svg';
const String _connectionLocalIconAsset =
    'assets/icons/ui_actions/connection_local.svg';
const String _authPasswordIconAsset =
    'assets/icons/ui_actions/auth_password.svg';
const String _authKeyIconAsset = 'assets/icons/ui_actions/auth_key.svg';
const String _shellSystemDefaultIconAsset =
    'assets/icons/ui_actions/shell_system_default.svg';
const String _shellPowerShellIconAsset =
    'assets/icons/ui_actions/shell_powershell.svg';
const String _shellPowerShellAdminIconAsset =
    'assets/icons/ui_actions/shell_powershell_admin.svg';
const String _shellCommandPromptIconAsset =
    'assets/icons/ui_actions/shell_command_prompt.svg';
const String _shellWslIconAsset = 'assets/icons/ui_actions/shell_wsl.svg';
const String _shellBashIconAsset = 'assets/icons/ui_actions/shell_bash.svg';
const String _groupFolderIconAsset = 'assets/icons/ui_actions/group_folder.svg';
const String _groupFolderOpenIconAsset =
    'assets/icons/ui_actions/group_folder_open.svg';

Widget _buildIcon(String asset, {double size = 16}) {
  return SizedBox.square(
    dimension: size,
    child: SvgPicture.asset(asset, fit: BoxFit.contain),
  );
}

Widget buildNewSessionVscodeIcon({double size = 16}) {
  return _buildIcon(_newSessionIconAsset, size: size);
}

Widget buildQuickConnectVscodeIcon({double size = 16}) {
  return Icon(Icons.bolt_rounded, size: size);
}

Widget buildSelectKeyVscodeIcon({double size = 16}) {
  return _buildIcon(_selectKeyIconAsset, size: size);
}

Widget buildConnectionSshVscodeIcon({double size = 16, Color? color}) {
  if (color != null) {
    return SizedBox.square(
      dimension: size,
      child: Icon(Icons.dns_rounded, size: size, color: color),
    );
  }
  return _buildIcon(_connectionSshIconAsset, size: size);
}

Widget buildConnectionLocalVscodeIcon({double size = 16}) {
  return _buildIcon(_connectionLocalIconAsset, size: size);
}

Widget buildAuthPasswordVscodeIcon({double size = 16}) {
  return _buildIcon(_authPasswordIconAsset, size: size);
}

Widget buildAuthKeyVscodeIcon({double size = 16}) {
  return _buildIcon(_authKeyIconAsset, size: size);
}

Widget buildLocalShellSystemDefaultVscodeIcon({double size = 16}) {
  return _buildIcon(_shellSystemDefaultIconAsset, size: size);
}

Widget buildLocalShellPowerShellVscodeIcon({double size = 16}) {
  return _buildIcon(_shellPowerShellIconAsset, size: size);
}

Widget buildLocalShellPowerShellAdminVscodeIcon({double size = 16}) {
  return _buildIcon(_shellPowerShellAdminIconAsset, size: size);
}

Widget buildLocalShellCommandPromptVscodeIcon({double size = 16}) {
  return _buildIcon(_shellCommandPromptIconAsset, size: size);
}

Widget buildLocalShellWslVscodeIcon({double size = 16}) {
  return _buildIcon(_shellWslIconAsset, size: size);
}

Widget buildLocalShellBashVscodeIcon({double size = 16}) {
  return _buildIcon(_shellBashIconAsset, size: size);
}

Widget buildGroupFolderVscodeIcon({double size = 16}) {
  return _buildIcon(_groupFolderIconAsset, size: size);
}

Widget buildGroupFolderOpenVscodeIcon({double size = 16}) {
  return _buildIcon(_groupFolderOpenIconAsset, size: size);
}
