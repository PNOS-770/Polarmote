use std::ffi::c_char;
use std::ffi::CString;

#[cfg(windows)]
mod platform {
    use serde_json::json;
    use std::ffi::c_void;
    use std::ptr;

    // ── Struct definitions matching Windows SDK ──

    #[repr(C)]
    #[allow(non_snake_case)]
    struct MEMORYSTATUSEX {
        dwLength: u32,
        dwMemoryLoad: u32,
        ullTotalPhys: u64,
        ullAvailPhys: u64,
        ullTotalPageFile: u64,
        ullAvailPageFile: u64,
        ullTotalVirtual: u64,
        ullAvailVirtual: u64,
        ullAvailExtendedVirtual: u64,
    }

    #[repr(C)]
    #[allow(non_snake_case)]
    struct SYSTEM_PROCESSOR_PERFORMANCE_INFORMATION {
        IdleTime: i64,
        KernelTime: i64,
        UserTime: i64,
        Reserved1: [i64; 2],
        Reserved2: u32,
    }

    #[repr(C)]
    #[allow(non_snake_case)]
    struct MIB_IFROW {
        wszName: [u16; 256],
        dwIndex: u32,
        dwType: u32,
        dwMtu: u32,
        dwSpeed: u32,
        dwPhysAddrLen: u32,
        bPhysAddr: [u8; 8],
        dwAdminStatus: u32,
        dwOperStatus: u32,
        dwLastChange: u32,
        dwInOctets: u32,
        dwInUcastPkts: u32,
        dwInNUcastPkts: u32,
        dwInDiscards: u32,
        dwInErrors: u32,
        dwInUnknownProtos: u32,
        dwOutOctets: u32,
        dwOutUcastPkts: u32,
        dwOutNUcastPkts: u32,
        dwOutDiscards: u32,
        dwOutErrors: u32,
        dwOutQLen: u32,
        dwDescrLen: u32,
        bDescr: [u8; 256],
    }

    #[repr(C)]
    #[allow(non_snake_case)]
    struct SYSTEM_PERFORMANCE_INFORMATION {
        IdleProcessTime: i64,
        IoReadTransferCount: i64,
        IoWriteTransferCount: i64,
        // Remaining fields not needed
    }

    // ── Native function declarations ──

    extern "system" {
        fn NtQuerySystemInformation(
            SystemInformationClass: u32,
            SystemInformation: *mut c_void,
            SystemInformationLength: u32,
            ReturnLength: *mut u32,
        ) -> i32;

        fn GlobalMemoryStatusEx(lpBuffer: *mut MEMORYSTATUSEX) -> i32;

        fn GetIfTable(
            pIfTable: *mut c_void,
            pdwSize: *mut u32,
            bOrder: i32,
        ) -> u32;

        fn GetDiskFreeSpaceExW(
            lpDirectoryName: *const u16,
            lpFreeBytesAvailable: *mut u64,
            lpTotalNumberOfBytes: *mut u64,
            lpTotalNumberOfFreeBytes: *mut u64,
        ) -> i32;
    }

    const STATUS_SUCCESS: i32 = 0;
    const STATUS_INFO_LENGTH_MISMATCH: i32 = 0xC0000004u32 as i32;
    const ERROR_INSUFFICIENT_BUFFER: u32 = 122;
    const NO_ERROR: u32 = 0;
    const IF_TYPE_SOFTWARE_LOOPBACK: u32 = 24;

    // Info classes
    const SYSTEM_PERFORMANCE_INFORMATION_CLASS: u32 = 2;
    const SYSTEM_PROCESSOR_PERFORMANCE_INFORMATION_CLASS: u32 = 8;

    fn collect_cpu() -> serde_json::Value {
        unsafe {
            let mut return_length: u32 = 0;
            // First call with null to get required size
            let status = NtQuerySystemInformation(
                SYSTEM_PROCESSOR_PERFORMANCE_INFORMATION_CLASS,
                ptr::null_mut(),
                0,
                &mut return_length,
            );
            if status != STATUS_INFO_LENGTH_MISMATCH || return_length == 0 {
                return json!(null);
            }

            let count = return_length as usize
                / std::mem::size_of::<SYSTEM_PROCESSOR_PERFORMANCE_INFORMATION>();
            let size =
                count * std::mem::size_of::<SYSTEM_PROCESSOR_PERFORMANCE_INFORMATION>();
            let mut buffer: Vec<u8> = vec![0u8; size];

            let status = NtQuerySystemInformation(
                SYSTEM_PROCESSOR_PERFORMANCE_INFORMATION_CLASS,
                buffer.as_mut_ptr() as *mut c_void,
                size as u32,
                &mut return_length,
            );
            if status != STATUS_SUCCESS {
                return json!(null);
            }

            let ptr = buffer.as_ptr() as *const SYSTEM_PROCESSOR_PERFORMANCE_INFORMATION;
            let mut total_idle: i64 = 0;
            let mut total_kernel: i64 = 0;
            let mut total_user: i64 = 0;

            for i in 0..count {
                let entry = &*ptr.add(i);
                total_idle += entry.IdleTime;
                total_kernel += entry.KernelTime;
                total_user += entry.UserTime;
            }

            json!({
                "idle": total_idle,
                "kernel": total_kernel,
                "user": total_user,
            })
        }
    }

    fn collect_memory() -> serde_json::Value {
        unsafe {
            let mut mem = MEMORYSTATUSEX {
                dwLength: std::mem::size_of::<MEMORYSTATUSEX>() as u32,
                dwMemoryLoad: 0,
                ullTotalPhys: 0,
                ullAvailPhys: 0,
                ullTotalPageFile: 0,
                ullAvailPageFile: 0,
                ullTotalVirtual: 0,
                ullAvailVirtual: 0,
                ullAvailExtendedVirtual: 0,
            };

            let result = GlobalMemoryStatusEx(&mut mem);
            if result == 0 {
                return json!(null);
            }

            json!({
                "total": mem.ullTotalPhys,
                "avail": mem.ullAvailPhys,
            })
        }
    }

    fn collect_network() -> serde_json::Value {
        unsafe {
            let mut buf_size: u32 = 0;
            let ret = GetIfTable(
                ptr::null_mut(),
                &mut buf_size,
                0,
            );
            if ret != ERROR_INSUFFICIENT_BUFFER || buf_size == 0 {
                return json!(null);
            }

            let mut buffer: Vec<u8> = vec![0u8; buf_size as usize];
            let ret = GetIfTable(
                buffer.as_mut_ptr() as *mut c_void,
                &mut buf_size,
                0,
            );
            if ret != NO_ERROR {
                return json!(null);
            }

            let ifrow_size = std::mem::size_of::<MIB_IFROW>();
            let data = buffer.as_ptr();
            let num_entries = *(data as *const u32);

            let mut rx_total: u64 = 0;
            let mut tx_total: u64 = 0;

            for i in 0..num_entries {
                let offset = std::mem::size_of::<u32>() + (i as usize) * ifrow_size;
                let row = data.add(offset) as *const MIB_IFROW;
                let entry = &*row;
                // Skip loopback
                if entry.dwType == IF_TYPE_SOFTWARE_LOOPBACK {
                    continue;
                }
                rx_total += entry.dwInOctets as u64;
                tx_total += entry.dwOutOctets as u64;
            }

            json!({
                "rx": rx_total,
                "tx": tx_total,
            })
        }
    }

    fn collect_disk() -> serde_json::Value {
        unsafe {
            // Capacity for system drive
            let mut free_bytes_avail: u64 = 0;
            let mut total_bytes: u64 = 0;
            let mut total_free_bytes: u64 = 0;

            // Use system drive "C:\"
            let root: [u16; 5] = [67u16, 58u16, 92u16, 0u16, 0u16]; // "C:\0"

            let ret = GetDiskFreeSpaceExW(
                root.as_ptr(),
                &mut free_bytes_avail,
                &mut total_bytes,
                &mut total_free_bytes,
            );

            // Disk I/O from SystemPerformanceInformation
            let mut perf_info = SYSTEM_PERFORMANCE_INFORMATION {
                IdleProcessTime: 0,
                IoReadTransferCount: 0,
                IoWriteTransferCount: 0,
            };
            let mut return_length: u32 = 0;
            let status = NtQuerySystemInformation(
                SYSTEM_PERFORMANCE_INFORMATION_CLASS,
                &mut perf_info as *mut _ as *mut c_void,
                std::mem::size_of::<SYSTEM_PERFORMANCE_INFORMATION>() as u32,
                &mut return_length,
            );

            let (read_io, write_io) = if status == STATUS_SUCCESS {
                (perf_info.IoReadTransferCount, perf_info.IoWriteTransferCount)
            } else {
                (0i64, 0i64)
            };

            if ret == 0 {
                return json!({
                    "total": 0,
                    "free": 0,
                    "read": read_io,
                    "write": write_io,
                });
            }

            json!({
                "total": total_bytes,
                "free": total_free_bytes,
                "read": read_io,
                "write": write_io,
            })
        }
    }

    pub fn collect_all() -> serde_json::Value {
        json!({
            "cpu": collect_cpu(),
            "mem": collect_memory(),
            "net": collect_network(),
            "disk": collect_disk(),
        })
    }
}

#[cfg(not(windows))]
mod platform {
    pub fn collect_all() -> serde_json::Value {
        serde_json::Value::Null
    }
}

#[no_mangle]
pub extern "C" fn Polarmote_collect_local_metrics() -> *mut c_char {
    let result = platform::collect_all();
    let json_str = result.to_string();
    match CString::new(json_str) {
        Ok(cstring) => cstring.into_raw(),
        Err(_) => CString::new("{}")
            .expect("valid empty json")
            .into_raw(),
    }
}
