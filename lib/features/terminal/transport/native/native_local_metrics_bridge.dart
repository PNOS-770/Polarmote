import 'dart:ffi';
import 'package:ffi/ffi.dart';

/// Collects local Windows metrics via native Win32 APIs.
///
/// Uses FFI to call:
///   - CPU: NtQuerySystemInformation(SystemProcessorPerformanceInformation)
///   - Memory: GlobalMemoryStatusEx
///   - Network: GetIfTable (cumulative interface bytes)
///   - Disk: GetDiskFreeSpaceExW + NtQuerySystemInformation(SystemPerformanceInformation)
class LocalMetricsCollector {
  // ── Library handles ──
  late final DynamicLibrary _ntdll;
  late final DynamicLibrary _kernel32;
  late final DynamicLibrary _iphlpapi;

  // ── FFI function pointers ──
  late final int Function(int, Pointer<Void>, int, Pointer<Uint32>)
      _ntQuerySystemInformation;
  late final int Function(Pointer<_MEMORYSTATUSEX>) _globalMemoryStatusEx;
  late final int Function(Pointer<Void>, Pointer<Uint32>, int) _getIfTable;
  late final int Function(Pointer<Uint16>, Pointer<Uint64>, Pointer<Uint64>,
      Pointer<Uint64>) _getDiskFreeSpaceExW;

  // ── Struct sizes (computed once) ──
  static const _cpuInfoSize = 48; // SYSTEM_PROCESSOR_PERFORMANCE_INFORMATION
  static const _perfInfoSize = 24; // SYSTEM_PERFORMANCE_INFORMATION (first 3 fields)

  LocalMetricsCollector() {
    _ntdll = DynamicLibrary.open('ntdll.dll');
    _kernel32 = DynamicLibrary.open('kernel32.dll');
    _iphlpapi = DynamicLibrary.open('iphlpapi.dll');

    _ntQuerySystemInformation = _ntdll.lookupFunction<
        Int32 Function(
            Uint32, Pointer<Void>, Uint32, Pointer<Uint32>),
        int Function(
            int, Pointer<Void>, int, Pointer<Uint32>)>('NtQuerySystemInformation');

    _globalMemoryStatusEx = _kernel32.lookupFunction<
        Int32 Function(Pointer<_MEMORYSTATUSEX>),
        int Function(
            Pointer<_MEMORYSTATUSEX>)>('GlobalMemoryStatusEx');

    _getIfTable = _iphlpapi.lookupFunction<
        Uint32 Function(Pointer<Void>, Pointer<Uint32>, Int32),
        int Function(Pointer<Void>, Pointer<Uint32>,
            int)>('GetIfTable');

    _getDiskFreeSpaceExW = _kernel32.lookupFunction<
        Int32 Function(
            Pointer<Uint16>, Pointer<Uint64>, Pointer<Uint64>, Pointer<Uint64>),
        int Function(Pointer<Uint16>, Pointer<Uint64>, Pointer<Uint64>,
            Pointer<Uint64>)>('GetDiskFreeSpaceExW');
  }

  // ── Constants ──
  static const _systemProcessorPerformanceInformation = 8;
  static const _systemPerformanceInformation = 2;
  static const _statusSuccess = 0;
  // NTSTATUS 0xC0000004 as signed 32-bit int (the value NtQuerySystemInformation returns)
  static const _statusInfoLengthMismatch = -1073741820;
  static const _errorInsufficientBuffer = 122;
  static const _noError = 0;
  static const _ifTypeSoftwareLoopback = 24;

  // ── Public API ──

  /// Collects all local metrics and returns them.
  ///
  /// Returns null on total failure.
  LocalMetricsData? collect() {
    final cpu = _collectCpu();
    final mem = _collectMemory();
    final net = _collectNetwork();
    final disk = _collectDisk();
    if (cpu == null && mem == null && net == null && disk == null) {
      return null;
    }
    return LocalMetricsData(
      cpuIdle: cpu?.idle,
      cpuKernel: cpu?.kernel,
      cpuUser: cpu?.user,
      memTotal: mem?.total,
      memAvail: mem?.avail,
      netRx: net?.rx,
      netTx: net?.tx,
      diskTotal: disk?.total,
      diskFree: disk?.free,
      diskRead: disk?.read,
      diskWrite: disk?.write,
    );
  }

  // ── CPU: NtQuerySystemInformation(SystemProcessorPerformanceInformation) ──

  _CpuMetric? _collectCpu() {
    final returnLength = calloc<Uint32>();
    final bufSize = calloc<Uint32>();

    try {
      // Get required buffer size
      var status = _ntQuerySystemInformation(
        _systemProcessorPerformanceInformation,
        nullptr,
        0,
        bufSize,
      );
      if (status != _statusInfoLengthMismatch || bufSize.value == 0) {
        return null;
      }

      final size = bufSize.value;
      final buffer = calloc<Uint8>(size);
      status = _ntQuerySystemInformation(
        _systemProcessorPerformanceInformation,
        buffer.cast(),
        size,
        returnLength,
      );
      if (status != _statusSuccess) {
        calloc.free(buffer);
        return null;
      }

      final count = size ~/ _cpuInfoSize;
      var idleSum = 0;
      var kernelSum = 0;
      var userSum = 0;

      for (var i = 0; i < count; i++) {
        final offset = i * _cpuInfoSize;
        idleSum += _readInt64(buffer, offset);
        kernelSum += _readInt64(buffer, offset + 8);
        userSum += _readInt64(buffer, offset + 16);
      }

      calloc.free(buffer);
      return _CpuMetric(idleSum, kernelSum, userSum);
    } finally {
      calloc.free(returnLength);
      calloc.free(bufSize);
    }
  }

  // ── Memory: GlobalMemoryStatusEx ──

  _MemMetric? _collectMemory() {
    final mem = calloc<_MEMORYSTATUSEX>();
    try {
      mem.ref.dwLength = sizeOf<_MEMORYSTATUSEX>();
      final result = _globalMemoryStatusEx(mem);
      if (result == 0) return null;
      return _MemMetric(mem.ref.ullTotalPhys, mem.ref.ullAvailPhys);
    } finally {
      calloc.free(mem);
    }
  }

  // ── Network: GetIfTable ──

  _NetMetric? _collectNetwork() {
    final bufSize = calloc<Uint32>();

    try {
      var ret = _getIfTable(nullptr, bufSize, 0);
      if (ret != _errorInsufficientBuffer || bufSize.value == 0) {
        return null;
      }

      final size = bufSize.value;
      final buffer = calloc<Uint8>(size);
      ret = _getIfTable(buffer.cast(), bufSize, 0);
      if (ret != _noError) {
        calloc.free(buffer);
        return null;
      }

      final numEntries = buffer.cast<Uint32>().value;
      var rxTotal = 0;
      var txTotal = 0;

      for (var i = 0; i < numEntries; i++) {
        final offset = 4 + (i * _ifRowSize());
        final type_ = _readUint32(buffer, offset + 260); // offset of dwType
        if (type_ == _ifTypeSoftwareLoopback) continue;

        final inOctets = _readUint32(buffer, offset + _inOctetsOffset());
        final outOctets = _readUint32(buffer, offset + _outOctetsOffset());
        rxTotal += inOctets;
        txTotal += outOctets;
      }

      calloc.free(buffer);

      // GetIfTable returns DWORD counters, which wrap at 4GB.
      // For accuracy, cast to 64-bit (already done above).
      return _NetMetric(rxTotal, txTotal);
    } finally {
      calloc.free(bufSize);
    }
  }

  // ── Disk: GetDiskFreeSpaceExW + NtQuerySystemInformation(SystemPerformanceInformation) ──

  _DiskMetric? _collectDisk() {
    final freeAvail = calloc<Uint64>();
    final totalBytes = calloc<Uint64>();
    final totalFree = calloc<Uint64>();

    try {
      // System drive "C:\"
      final rootPath = calloc<Uint16>(4);
      rootPath[0] = 0x0043; // 'C'
      rootPath[1] = 0x003A; // ':'
      rootPath[2] = 0x005C; // '\'
      rootPath[3] = 0x0000; // null

      final ret = _getDiskFreeSpaceExW(rootPath, freeAvail, totalBytes, totalFree);
      calloc.free(rootPath);

      // Disk I/O from SystemPerformanceInformation
      final perfBuf = calloc<Uint8>(_perfInfoSize);
      final returnLength = calloc<Uint32>();
      final status = _ntQuerySystemInformation(
        _systemPerformanceInformation,
        perfBuf.cast(),
        _perfInfoSize,
        returnLength,
      );

      final readIo = status == _statusSuccess ? _readInt64(perfBuf, 8) : 0;
      final writeIo = status == _statusSuccess ? _readInt64(perfBuf, 16) : 0;

      calloc.free(perfBuf);
      calloc.free(returnLength);

      if (ret == 0) {
        return _DiskMetric(0, 0, readIo, writeIo);
      }
      return _DiskMetric(
        totalBytes.value,
        totalFree.value,
        readIo,
        writeIo,
      );
    } finally {
      calloc.free(freeAvail);
      calloc.free(totalBytes);
      calloc.free(totalFree);
    }
  }

  // ── Helpers ──

  /// Size of MIB_IFROW struct (fixed on all Windows versions).
  static int _ifRowSize() {
    // WCHAR wszName[256] = 512
    // DWORD dwIndex = 4
    // DWORD dwType = 4
    // DWORD dwMtu = 4
    // DWORD dwSpeed = 4
    // DWORD dwPhysAddrLen = 4
    // BYTE bPhysAddr[8] = 8
    // DWORD dwAdminStatus = 4
    // DWORD dwOperStatus = 4
    // DWORD dwLastChange = 4
    // DWORD dwInOctets = 4
    // DWORD dwInUcastPkts = 4
    // DWORD dwInNUcastPkts = 4
    // DWORD dwInDiscards = 4
    // DWORD dwInErrors = 4
    // DWORD dwInUnknownProtos = 4
    // DWORD dwOutOctets = 4
    // DWORD dwOutUcastPkts = 4
    // DWORD dwOutNUcastPkts = 4
    // DWORD dwOutDiscards = 4
    // DWORD dwOutErrors = 4
    // DWORD dwOutQLen = 4
    // DWORD dwDescrLen = 4
    // BYTE bDescr[256] = 256
    // Total = 512 + 4*21 + 8 + 256 = 860
    const wszName = 512; // 256 * 2
    const dwFields = 21 * 4; // 84
    const physAddr = 8;
    const bDescr = 256;
    return wszName + dwFields + physAddr + bDescr;
  }

  static int _inOctetsOffset() {
    // skip wszName[256] + dwIndex + dwType + dwMtu + dwSpeed + dwPhysAddrLen + bPhysAddr[8] + dwAdminStatus + dwOperStatus + dwLastChange
    // = 512 + 5*4 + 8 + 3*4 = 552
    return 512 + (5 * 4) + 8 + (3 * 4);
  }

  static int _outOctetsOffset() {
    // = inOctetsOffset + dwInOctets + dwInUcastPkts + dwInNUcastPkts + dwInDiscards + dwInErrors + dwInUnknownProtos
    // = 552 + 6*4 = 576
    return _inOctetsOffset() + (6 * 4);
  }

  static int _readUint32(Pointer<Uint8> buf, int offset) {
    return (buf + offset).cast<Uint32>().value;
  }

  static int _readInt64(Pointer<Uint8> buf, int offset) {
    return (buf + offset).cast<Int64>().value;
  }
}

/// Result from a single metrics collection pass.
class LocalMetricsData {
  final int? cpuIdle;
  final int? cpuKernel;
  final int? cpuUser;
  final int? memTotal;
  final int? memAvail;
  final int? netRx;
  final int? netTx;
  final int? diskTotal;
  final int? diskFree;
  final int? diskRead;
  final int? diskWrite;

  const LocalMetricsData({
    this.cpuIdle,
    this.cpuKernel,
    this.cpuUser,
    this.memTotal,
    this.memAvail,
    this.netRx,
    this.netTx,
    this.diskTotal,
    this.diskFree,
    this.diskRead,
    this.diskWrite,
  });

  bool get isEmpty =>
      cpuIdle == null && cpuKernel == null && cpuUser == null &&
      memTotal == null && netRx == null && diskTotal == null;

  double? computeCpuUsage(int prevIdle, int prevTotal) {
    if (cpuIdle == null || cpuKernel == null || cpuUser == null) return null;
    final total = cpuIdle! + cpuKernel! + cpuUser!;
    if (total <= prevTotal) return null;
    final deltaTotal = total - prevTotal;
    final deltaIdle = cpuIdle! - prevIdle;
    if (deltaTotal <= 0) return null;
    return (deltaTotal - deltaIdle) / deltaTotal;
  }
}

// ── Internal data holders ──

class _CpuMetric {
  final int idle;
  final int kernel;
  final int user;
  _CpuMetric(this.idle, this.kernel, this.user);
}

class _MemMetric {
  final int total;
  final int avail;
  _MemMetric(this.total, this.avail);
}

class _NetMetric {
  final int rx;
  final int tx;
  _NetMetric(this.rx, this.tx);
}

class _DiskMetric {
  final int total;
  final int free;
  final int read;
  final int write;
  _DiskMetric(this.total, this.free, this.read, this.write);
}

final class _MEMORYSTATUSEX extends Struct {
  @Uint32()
  external int dwLength;

  @Uint32()
  external int dwMemoryLoad;

  @Uint64()
  external int ullTotalPhys;

  @Uint64()
  external int ullAvailPhys;

  @Uint64()
  external int ullTotalPageFile;

  @Uint64()
  external int ullAvailPageFile;

  @Uint64()
  external int ullTotalVirtual;

  @Uint64()
  external int ullAvailVirtual;

  @Uint64()
  external int ullAvailExtendedVirtual;
}

