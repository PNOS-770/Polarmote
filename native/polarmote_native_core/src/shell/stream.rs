use windows::Win32::System::Com::{IStream, IStream_Impl, CoTaskMemAlloc};
use windows::Win32::Storage::FileSystem::{STGTY_STREAM, STATFLAG_DEFAULT};
use windows::Win32::Foundation::*;
use windows::core::{implement, HRESULT};
use std::sync::{Arc, Mutex};

/// Simple IStream that downloads the remote file to memory on first Read,
/// then serves from the cached buffer.
#[implement(IStream)]
pub struct DownloadStream {
    remote_path: String,
    size: u64,
    config_json: String,
    cancelled: Arc<Mutex<bool>>,
    state: Arc<Mutex<StreamState>>,
}

struct StreamState {
    buffer: Vec<u8>,
    position: u64,
    downloaded: bool,
    download_error: Option<String>,
    stat_called: bool,
}

impl DownloadStream {
    pub fn new(
        remote_path: String,
        size: u64,
        config_json: String,
        cancelled: Arc<Mutex<bool>>,
    ) -> Self {
        Self {
            remote_path,
            size,
            config_json,
            cancelled,
            state: Arc::new(Mutex::new(StreamState {
                buffer: Vec::new(),
                position: 0,
                downloaded: false,
                download_error: None,
                stat_called: false,
            })),
        }
    }

    fn ensure_downloaded(&self) -> Result<(), String> {
        let mut state = self.state.lock().map_err(|e| e.to_string())?;
        if state.downloaded {
            return state.download_error.clone().map_or(Ok(()), Err);
        }
        drop(state);

        let result = self.do_download();

        let mut state = self.state.lock().map_err(|e| e.to_string())?;
        match result {
            Ok(buf) => {
                state.buffer = buf;
                state.downloaded = true;
                Ok(())
            }
            Err(e) => {
                state.downloaded = true;
                state.download_error = Some(e.clone());
                Err(e)
            }
        }
    }

    fn do_download(&self) -> Result<Vec<u8>, String> {
        let config: crate::models::SessionConfig = serde_json::from_str(&self.config_json)
            .map_err(|e| format!("parse config: {e}"))?;

        let connection = crate::transport::sftp::SftpConnection::connect(&config)
            .map_err(|e| format!("sftp connect: {e}"))?;

        let mut remote_file = connection
            .sftp()
            .open(&self.remote_path, libssh_rs::OpenFlags::READ_ONLY, 0)
            .map_err(|e| format!("sftp open: {e}"))?;

        let cap = if self.size > 0 && self.size <= 100_000_000 {
            self.size as usize
        } else {
            64 * 1024
        };
        let mut buf = Vec::with_capacity(cap);
        let mut chunk = vec![0u8; 64 * 1024];

        loop {
            if *self.cancelled.lock().unwrap() {
                return Err("cancelled".to_string());
            }
            let n = remote_file.read(&mut chunk).map_err(|e| format!("sftp read: {e}"))?;
            if n == 0 {
                break;
            }
            buf.extend_from_slice(&chunk[..n]);
        }

        Ok(buf)
    }
}

impl IStream_Impl for DownloadStream_Impl {
    fn Read(&self, pv: &mut [u8], pcb_read: &mut u32) -> HRESULT {
        if let Err(e) = self.ensure_downloaded() {
            eprintln!("[DRAG_STREAM] Read error: {e}");
            return E_UNEXPECTED;
        }

        let mut state = match self.state.lock() {
            Ok(s) => s,
            Err(_) => return E_UNEXPECTED,
        };

        let available = state.buffer.len().saturating_sub(state.position as usize);
        let to_read = pv.len().min(available);

        if to_read > 0 {
            let src = &state.buffer[state.position as usize..state.position as usize + to_read];
            pv[..to_read].copy_from_slice(src);
            state.position += to_read as u64;
        }

        *pcb_read = to_read as u32;
        if to_read == 0 { S_FALSE } else { S_OK }
    }

    fn Write(&self, _pv: &[u8], _pcb_written: &mut u32) -> HRESULT {
        E_NOTIMPL
    }

    fn Seek(&self, dlib_move: i64, dw_origin: u32, plib_new_position: &mut u64) -> HRESULT {
        let mut state = match self.state.lock() {
            Ok(s) => s,
            Err(_) => return E_UNEXPECTED,
        };

        let len = state.buffer.len() as i64;
        let new_pos = match dw_origin {
            0 => dlib_move,               // STREAM_SEEK_SET
            1 => state.position as i64 + dlib_move, // STREAM_SEEK_CUR
            2 => len + dlib_move,          // STREAM_SEEK_END
            _ => return E_UNEXPECTED,
        };

        state.position = new_pos.max(0).min(len) as u64;
        *plib_new_position = state.position;
        S_OK
    }

    fn SetSize(&self, _lib_new_size: u64) -> HRESULT {
        E_NOTIMPL
    }

    fn CopyTo(
        &self,
        _stm: &IStream,
        _cb: u64,
        _pcb_read: &mut u64,
        _pcb_written: &mut u64,
    ) -> HRESULT {
        E_NOTIMPL
    }

    fn Commit(&self, _grf_commit_flags: u32) -> HRESULT {
        S_OK
    }

    fn Revert(&self) -> HRESULT {
        E_NOTIMPL
    }

    fn LockRegion(&self, _lib_offset: u64, _cb: u64, _dw_lock_type: u32) -> HRESULT {
        E_NOTIMPL
    }

    fn UnlockRegion(&self, _lib_offset: u64, _cb: u64, _dw_lock_type: u32) -> HRESULT {
        E_NOTIMPL
    }

    fn Stat(&self, pstatstg: &mut windows::Win32::Storage::FileSystem::STATSTG, _grf_stat_flag: u32) -> HRESULT {
        let state = match self.state.lock() {
            Ok(s) => s,
            Err(_) => return E_UNEXPECTED,
        };

        let name: Vec<u16> = self.remote_path.encode_utf16().collect();
        let name_ptr = unsafe { CoTaskMemAlloc((name.len() + 1) * 2) };
        if name_ptr.is_null() {
            return E_OUTOFMEMORY;
        }
        unsafe {
            std::ptr::copy_nonoverlapping(name.as_ptr(), name_ptr as *mut u16, name.len());
            *(name_ptr as *mut u16).add(name.len()) = 0;
        }

        *pstatstg = windows::Win32::Storage::FileSystem::STATSTG {
            pwcsName: windows::core::PWSTR(name_ptr as *mut u16),
            type_: STGTY_STREAM,
            cbSize: state.buffer.len() as u64,
            mtime: FILETIME::default(),
            ctime: FILETIME::default(),
            atime: FILETIME::default(),
            grfMode: 0,
            grfLocksSupported: 0,
            clsid: windows::core::GUID::zeroed(),
            grfStateBits: 0,
            reserved: 0,
        };
        S_OK
    }

    fn Clone(&self) -> windows::core::Result<IStream> {
        Err(E_NOTIMPL.into())
    }
}
