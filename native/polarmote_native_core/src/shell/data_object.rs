use windows::Win32::System::Com::*;
use windows::Win32::UI::Shell::*;
use windows::Win32::Foundation::*;
use windows::Win32::Storage::FileSystem::*;
use windows::core::{implement, GUID, HRESULT};
use std::sync::{Arc, Mutex};
use std::mem::{zeroed, size_of};

use super::FileDragInfo;

// Custom clipboard format IDs (lazy-init via OnceLock)
fn register_format(name: &str) -> u16 {
    unsafe { RegisterClipboardFormatW(&windows::core::HSTRING::from(name)).0 }
}

fn get_filedescriptor_format() -> u16 {
    static FMT: std::sync::OnceLock<u16> = std::sync::OnceLock::new();
    *FMT.get_or_init(|| register_format("FileGroupDescriptorW"))
}

fn get_filecontents_format() -> u16 {
    static FMT: std::sync::OnceLock<u16> = std::sync::OnceLock::new();
    *FMT.get_or_init(|| register_format("FileContents"))
}

// Standard COM error codes not provided by the windows crate
const DV_E_FORMATETC: HRESULT = HRESULT(0x80040064i32);
const DV_E_LINDEX: HRESULT = HRESULT(0x80040069i32);
const DATA_S_SAMEFORMATETC: HRESULT = HRESULT(0x00040130i32);

/// IDataObject + IAsyncOperation implementation for async drag-drop.
/// Provides FileGroupDescriptorW (file names/sizes) and FileContents (IStream)
/// to the Windows Shell.
#[implement(IDataObject, IAsyncOperation)]
pub struct AsyncFileDataObject {
    pub files: Vec<FileDragInfo>,
    pub config_json: String,
    pub cancelled: Arc<Mutex<bool>>,
    pub drop_effect: Arc<Mutex<u32>>,
}

impl AsyncFileDataObject {
    pub fn new(files: Vec<FileDragInfo>, config_json: String) -> Self {
        Self {
            files,
            config_json,
            cancelled: Arc::new(Mutex::new(false)),
            drop_effect: Arc::new(Mutex::new(0)),
        }
    }
}

impl IDataObject_Impl for AsyncFileDataObject_Impl {
    fn GetData(&self, formatetc: &FORMATETC, medium: &mut STGMEDIUM) -> HRESULT {
        let fmt = formatetc.cfFormat;
        let tymed = formatetc.tymed;
        let lindex = formatetc.lindex;

        if fmt == get_filedescriptor_format()
            && (tymed & TYMED_HGLOBAL.0) != 0
        {
            return self.get_filedescriptor(medium);
        }

        if fmt == get_filecontents_format()
            && lindex >= 0
            && (lindex as usize) < self.files.len()
            && (tymed & TYMED_ISTREAM.0) != 0
        {
            return self.get_filecontents(lindex, medium);
        }

        DV_E_FORMATETC
    }

    fn GetDataHere(&self, _formatetc: &FORMATETC, _medium: &mut STGMEDIUM) -> HRESULT {
        E_NOTIMPL
    }

    fn QueryGetData(&self, formatetc: &FORMATETC) -> HRESULT {
        let fmt = formatetc.cfFormat;
        if fmt == get_filedescriptor_format() || fmt == get_filecontents_format() {
            S_OK
        } else {
            DV_E_FORMATETC
        }
    }

    fn GetCanonicalFormatEtc(&self, _formatetc: &FORMATETC, _result: &mut FORMATETC) -> HRESULT {
        DATA_S_SAMEFORMATETC
    }

    fn SetData(&self, _formatetc: &FORMATETC, _medium: &STGMEDIUM, _release: bool) -> HRESULT {
        E_NOTIMPL
    }

    fn EnumFormatEtc(&self, _direction: u32, _enum: *mut Option<IEnumFORMATETC>) -> HRESULT {
        E_NOTIMPL
    }

    fn DAdvise(
        &self,
        _formatetc: &FORMATETC,
        _advf: u32,
        _advise_sink: &IAdviseSink,
        _conn: &mut u32,
    ) -> HRESULT {
        E_NOTIMPL
    }

    fn DUnadvise(&self, _conn: u32) -> HRESULT {
        E_NOTIMPL
    }

    fn EnumDAdvise(&self, _enum_advise: *mut Option<IEnumSTATDATA>) -> HRESULT {
        E_NOTIMPL
    }
}

impl IAsyncOperation_Impl for AsyncFileDataObject_Impl {
    fn SetAsyncMode(&self, _f_mode: bool) -> HRESULT {
        S_OK
    }

    fn GetAsyncMode(&self) -> bool {
        true
    }

    fn StartOperation(&self, _pbc: &IBindCtx) -> HRESULT {
        S_OK
    }

    fn InOperation(&self) -> bool {
        true
    }

    fn EndOperation(&self, _hresult: HRESULT, _pbc: &IBindCtx, dw_effect: u32) -> HRESULT {
        *self.drop_effect.lock().unwrap() = dw_effect;
        S_OK
    }
}

impl AsyncFileDataObject_Impl {
    fn get_filedescriptor(&self, medium: &mut STGMEDIUM) -> HRESULT {
        unsafe {
            let count = self.files.len() as u32;
            let desc_size = size_of::<FILEDESCRIPTORW>();
            let group_size = size_of::<u32>() + (count as usize) * desc_size;

            let h = CoTaskMemAlloc(group_size);
            if h.is_null() {
                return E_OUTOFMEMORY;
            }

            std::ptr::write(h as *mut u32, count);

            for i in 0..self.files.len() {
                let file = &self.files[i];
                let desc_ptr = h.add(size_of::<u32>() + i * desc_size) as *mut FILEDESCRIPTORW;

                let name_wide: Vec<u16> = file.display_name.encode_utf16().collect();
                let mut name_arr = [0u16; 260];
                let copy_len = name_wide.len().min(259);
                name_arr[..copy_len].copy_from_slice(&name_wide[..copy_len]);
                name_arr[copy_len] = 0;

                let attrs = if file.is_directory {
                    FILE_ATTRIBUTE_DIRECTORY
                } else {
                    FILE_ATTRIBUTE_NORMAL
                };

                let size_high = (file.size >> 32) as u32;
                let size_low = (file.size & 0xFFFFFFFF) as u32;

                std::ptr::write(desc_ptr, FILEDESCRIPTORW {
                    dwFlags: FD_UNICODE | FD_FILESIZE | FD_ATTRIBUTES,
                    clsid: GUID::zeroed(),
                    sizel: zeroed(),
                    pointl: zeroed(),
                    dwFileAttributes: attrs,
                    ftCreationTime: FILETIME::default(),
                    ftLastAccessTime: FILETIME::default(),
                    ftLastWriteTime: FILETIME::default(),
                    nFileSizeHigh: size_high,
                    nFileSizeLow: size_low,
                    cFileName: name_arr,
                });
            }

            medium.tymed = TYMED_HGLOBAL;
            medium.Anonymous = zeroed();
            medium.u.Anonymous.hGlobal = h;

            S_OK
        }
    }

    fn get_filecontents(&self, index: i32, medium: &mut STGMEDIUM) -> HRESULT {
        let idx = index as usize;
        if idx >= self.files.len() {
            return DV_E_LINDEX;
        }

        let file = &self.files[idx];
        if file.is_directory {
            return DV_E_FORMATETC;
        }

        let stream = super::stream::DownloadStream::new(
            file.remote_path.clone(),
            file.size,
            self.config_json.clone(),
            self.cancelled.clone(),
        );

        let com_stream: IStream = stream.into();

        medium.tymed = TYMED_ISTREAM;
        medium.Anonymous = unsafe { zeroed() };
        medium.u.Anonymous.pstm = Some(com_stream);

        S_OK
    }
}
