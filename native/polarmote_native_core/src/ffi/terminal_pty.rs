use crate::pty;
use serde_json::json;
use std::os::raw::c_char;

use super::{into_c_string, ptr_to_string};

#[no_mangle]
pub extern "C" fn Polarmote_pty_is_supported() -> i32 {
    if pty::is_supported() {
        1
    } else {
        0
    }
}

#[no_mangle]
pub extern "C" fn Polarmote_pty_spawn(config_json: *const c_char) -> u64 {
    let Ok(config_text) = ptr_to_string(config_json) else {
        return 0;
    };
    match pty::spawn(&config_text) {
        Ok(session_id) => session_id,
        Err(_) => 0,
    }
}

#[no_mangle]
pub extern "C" fn Polarmote_pty_write(session_id: u64, data: *const u8, len: usize) -> i32 {
    if data.is_null() && len > 0 {
        return -2;
    }
    let bytes = if len == 0 {
        &[][..]
    } else {
        unsafe { std::slice::from_raw_parts(data, len) }
    };
    match pty::write(session_id, bytes) {
        Ok(()) => 0,
        Err(_) => -1,
    }
}

#[no_mangle]
pub extern "C" fn Polarmote_pty_resize(session_id: u64, cols: u16, rows: u16) -> i32 {
    match pty::resize(session_id, cols, rows) {
        Ok(()) => 0,
        Err(_) => -1,
    }
}

#[no_mangle]
pub extern "C" fn Polarmote_pty_poll(session_id: u64) -> *mut c_char {
    let payload = match pty::poll(session_id) {
        Ok(value) => serde_json::to_string(&value).unwrap_or_else(|_| "{}".to_owned()),
        Err(error) => json!({
            "chunks": [],
            "closed": true,
            "exit_code": null,
            "error": error.to_string(),
        })
        .to_string(),
    };
    into_c_string(payload)
}

#[no_mangle]
pub extern "C" fn Polarmote_pty_close(session_id: u64) -> i32 {
    match pty::close(session_id) {
        Ok(()) => 0,
        Err(_) => -1,
    }
}
