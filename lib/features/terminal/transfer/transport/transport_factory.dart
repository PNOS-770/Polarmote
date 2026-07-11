import '../../models/host_entry.dart';
import 'native/native_transport.dart';
import 'transport_provider.dart';

class TransferRuntimeOptions {
  const TransferRuntimeOptions({
    required this.nativeMaxConcurrency,
    required this.defaultChunkSizeBytes,
    required this.enableResume,
    required this.retryMaxAttempts,
    required this.retryBaseBackoffMs,
    required this.retryMaxBackoffMs,
  });

  final int nativeMaxConcurrency;
  final int defaultChunkSizeBytes;
  final bool enableResume;
  final int retryMaxAttempts;
  final int retryBaseBackoffMs;
  final int retryMaxBackoffMs;
}

class TransferTransportFactory {
  const TransferTransportFactory();

  TransportProvider create({
    required HostEntry profile,
    required TransferRuntimeOptions options,
  }) {
    return NativeTransport(profile: profile, options: options);
  }
}

