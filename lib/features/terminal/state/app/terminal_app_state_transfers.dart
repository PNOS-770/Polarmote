import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math';

import '../../../../shared/constants/app_string.dart';
import '../../models/file_node.dart';
import '../../models/terminal_session.dart';
import '../../models/transfer_task.dart';
import '../../transfer/mobile/android_transfer_foreground_bridge.dart';
import '../../transfer/control/cancellation_token.dart';
import '../../transfer/transport/transport_factory.dart';
import '../terminal_app_state.dart';
import '../terminal_app_state_models.dart';

part 'terminal_app_state_transfers_runtime.dart';
part 'terminal_app_state_transfers_adaptive.dart';
part 'terminal_app_state_transfers_stubs.dart';

final Expando<Map<String, _SessionTransferRuntimeSet>> transferRuntimeByState = Expando<Map<String, _SessionTransferRuntimeSet>>('transfer-runtime');
final Expando<_TransferForegroundServiceState> transferForegroundServiceByState = Expando<_TransferForegroundServiceState>('transfer-foreground-service');

const TransferTransportFactory transferTransportFactory = TransferTransportFactory();


extension TerminalAppStateTransfers on TerminalAppState {}








