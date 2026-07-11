use std::ffi::CStr;
use std::os::raw::c_char;
use std::sync::{Mutex, OnceLock};

use windows::Win32::System::Com::*;
use windows::Win32::UI::Shell::*;
use windows::Win32::Foundation::*;
use windows::Win32::System::Threading::*;
use windows::core::{implement, HRESULT};

use super::data_object::AsyncFileDataObject;
use super::FileDragInfo;

// ── Module-level statics shared across threads ──

static FLUTTER_HWND: OnceLock<isize> = OnceLock::new();
static CUSTOM_DRAG_MSG: OnceLock<u32> = OnceLock::new();

static PENDING_DATA_OBJECT: OnceLock<Mutex<Option<IDataObject>>> = OnceLock::new();
static PENDING_DROP_SOURCE: OnceLock<Mutex<Option<IDropSource>>> = OnceLock::new();
static PENDING_EVENT: OnceLock<Mutex<Option<HANDLE>>> = OnceLock::new();

fn drag_msg() -> u32 {
    *CUSTOM_DRAG_MSG.get_or_init(|| unsafe {
        RegisterWindowMessageW(&windows::core::HSTRING::from("PolarmoteAsyncDrag"))
    })
}

fn get_pending_data() -> MutexGuard<'static, Option<IDataObject>> {
    PENDING_DATA_OBJECT.get_or_init(|| Mutex::new(None)).lock().unwrap()
}

fn get_pending_source() -> MutexGuard<'static, Option<IDropSource>> {
    PENDING_DROP_SOURCE.get_or_init(|| Mutex::new(None)).lock().unwrap()
}

fn get_pending_event() -> MutexGuard<'static, Option<HANDLE>> {
    PENDING_EVENT.get_or_init(|| Mutex::new(None)).lock().unwrap()
}

// ── Simple IDropSource ──

#[implement(IDropSource)]
struct PolarmoteDropSource;

impl IDropSource_Impl for PolarmoteDropSource_Impl {
    fn QueryContinueDrag(&self, f_escape_pressed: bool, _grf_key_state: u32) -> HRESULT {
        if f_escape_pressed {
            DRAGDROP_S_CANCEL
        } else {
            S_OK
        }
    }

    fn GiveFeedback(&self, _dw_effect: u32) -> HRESULT {
        DRAGDROP_S_USEDEFAULTCURSORS
    }
}

// ── FFI exports ──

/// Register the Flutter window HWND. Called once from C++ runner at startup.
#[no_mangle]
pub extern "C" fn Polarmote_shell_register_hwnd(hwnd: i64) -> i32 {
    match FLUTTER_HWND.set(hwnd as isize) {
        Ok(()) => 0,
        Err(_) => -1,
    }
}

/// Start an async drag-drop for the given files.
/// config_json: SessionConfig JSON
/// files_json:  [{remote_path, display_name, size, is_directory}]
/// Returns 0 on success, negative on error.
#[no_mangle]
pub extern "C" fn Polarmote_shell_drag_drop_start(
    config_json: *const c_char,
    files_json: *const c_char,
) -> i32 {
    let hwnd = match FLUTTER_HWND.get() {
        Some(h) => *h,
        None => return -1,
    };

    let config_str = match ptr_to_string(config_json) {
        Ok(s) => s,
        Err(_) => return -2,
    };
    let files_str = match ptr_to_string(files_json) {
        Ok(s) => s,
        Err(_) => return -3,
    };
    let files: Vec<FileDragInfo> = match serde_json::from_str(&files_str) {
        Ok(v) => v,
        Err(_) => return -4,
    };
    if files.is_empty() {
        return -5;
    }

    // Build COM objects
    let data_object: IDataObject = AsyncFileDataObject::new(files, config_str).into();
    let drop_source: IDropSource = PolarmoteDropSource.into();

    let event = unsafe { CreateEventW(std::ptr::null(), false, false, None) };
    if event.is_invalid() {
        return -6;
    }

    // Store in statics for main thread
    *get_pending_data() = Some(data_object);
    *get_pending_source() = Some(drop_source);
    *get_pending_event() = Some(event);

    // Post custom message to Flutter window (main thread)
    let msg = drag_msg();
    unsafe {
        PostMessageW(
            HWND(hwnd as _),
            msg,
            Some(windows::core::WPARAM(0)),
            Some(windows::core::LPARAM(0)),
        );
    }

    // Wait for main thread to complete DoDragDrop (2 min timeout)
    let wait = unsafe { WaitForSingleObject(event, 120000) };

    // Cleanup
    *get_pending_data() = None;
    *get_pending_source() = None;
    *get_pending_event() = None;
    unsafe { CloseHandle(event); }

    match wait {
        0 => 0,
        0x00000102 => -7,
        _ => -8,
    }
}

/// Called from C++ FlutterWindow::MessageHandler (main thread) to execute DoDragDrop.
/// Returns the drop effect code.
#[doc(hidden)]
pub fn execute_drag_drop_on_main_thread() -> u32 {
    let data_obj = get_pending_data().clone();
    let drop_src = get_pending_source().clone();

    let (Some(data_obj), Some(drop_src)) = (data_obj, drop_src) else {
        let evt = get_pending_event().clone();
        if let Some(e) = evt { unsafe { SetEvent(e); } }
        return 0;
    };

    let mut effect: u32 = 0;
    let hr = unsafe { DoDragDrop(&data_obj, &drop_src, DROPEFFECT_COPY, &mut effect) };

    let evt = get_pending_event().clone();
    if let Some(e) = evt { unsafe { SetEvent(e); } }

    effect
}

fn ptr_to_string(ptr: *const c_char) -> Result<String, String> {
    if ptr.is_null() { return Err("null".into()); }
    unsafe { CStr::from_ptr(ptr) }
        .to_str()
        .map(|s| s.to_owned())
        .map_err(|e| format!("utf8: {e}"))
}
