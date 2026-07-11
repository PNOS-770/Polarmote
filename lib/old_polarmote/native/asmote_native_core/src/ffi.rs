use crate::error::{CoreError, CoreResult};
use crate::models::{SessionConfig, TransferTask};
use crate::models_v2::{RuntimeConfig, TransferGraph};
use crate::runtime::RuntimeRegistry;
use crate::session::NativeTransferCore;
use serde_json::json;
use std::ffi::{CStr, CString};
use std::os::raw::c_char;

mod terminal_pty;

pub use terminal_pty::*;

fn ptr_to_string(ptr: *const c_char) -> CoreResult<String> {
    if ptr.is_null() {
        return Err(CoreError::InvalidUtf8);
    }
    let c_str = unsafe { CStr::from_ptr(ptr) };
    let value = c_str.to_str().map_err(|_| CoreError::InvalidUtf8)?;
    Ok(value.to_owned())
}

fn into_c_string(value: String) -> *mut c_char {
    match CString::new(value) {
        Ok(cstring) => cstring.into_raw(),
        Err(_) => CString::new("{}").expect("valid empty json").into_raw(),
    }
}

fn build_info_payload() -> String {
    json!({
        "package": env!("CARGO_PKG_NAME"),
        "version": option_env!("ASMOTE_ENGINE_VERSION").unwrap_or(env!("CARGO_PKG_VERSION")),
        "build_id": option_env!("ASMOTE_BUILD_ID").unwrap_or("unknown"),
        "profile": option_env!("ASMOTE_BUILD_PROFILE").unwrap_or("unknown"),
    })
    .to_string()
}

#[no_mangle]
pub extern "C" fn asmote_create_session(config_json: *const c_char) -> u64 {
    let Ok(config_text) = ptr_to_string(config_json) else {
        return 0;
    };
    let Ok(config) = serde_json::from_str::<SessionConfig>(&config_text) else {
        return 0;
    };
    NativeTransferCore::global().create_session(config)
}

#[no_mangle]
pub extern "C" fn asmote_destroy_session(session_id: u64) -> i32 {
    match NativeTransferCore::global().destroy_session(session_id) {
        Ok(()) => 0,
        Err(_) => -1,
    }
}

#[no_mangle]
pub extern "C" fn asmote_enqueue_transfer(session_id: u64, task_json: *const c_char) -> i32 {
    let Ok(task_text) = ptr_to_string(task_json) else {
        return -2;
    };
    let Ok(task) = serde_json::from_str::<TransferTask>(&task_text) else {
        return -3;
    };
    let Ok(session) = NativeTransferCore::global().session(session_id) else {
        return -4;
    };
    match session.enqueue(task) {
        Ok(()) => 0,
        Err(_) => -5,
    }
}

#[no_mangle]
pub extern "C" fn asmote_cancel_task(session_id: u64, task_id: *const c_char) -> i32 {
    let Ok(task_id_text) = ptr_to_string(task_id) else {
        return -2;
    };
    let Ok(session) = NativeTransferCore::global().session(session_id) else {
        return -4;
    };
    match session.cancel(task_id_text) {
        Ok(()) => 0,
        Err(_) => -5,
    }
}

#[no_mangle]
pub extern "C" fn asmote_query_progress(session_id: u64, task_id: *const c_char) -> *mut c_char {
    let result = (|| -> CoreResult<String> {
        let task_id_text = ptr_to_string(task_id)?;
        let session = NativeTransferCore::global().session(session_id)?;
        let snapshot = session.query_progress(&task_id_text);
        let payload = snapshot
            .map(|value| serde_json::to_value(value).unwrap_or(json!({})))
            .unwrap_or(json!({}));
        Ok(payload.to_string())
    })();

    match result {
        Ok(payload) => into_c_string(payload),
        Err(error) => into_c_string(json!({ "error": error.to_string() }).to_string()),
    }
}

#[no_mangle]
pub extern "C" fn asmote_poll_events(session_id: u64) -> *mut c_char {
    let payload = match NativeTransferCore::global().session(session_id) {
        Ok(session) => {
            serde_json::to_string(&session.poll_events()).unwrap_or_else(|_| "[]".to_owned())
        }
        Err(_) => "[]".to_owned(),
    };
    into_c_string(payload)
}

#[no_mangle]
pub extern "C" fn asmote_build_info() -> *mut c_char {
    into_c_string(build_info_payload())
}

#[no_mangle]
pub extern "C" fn asmote_runtime_create(config_json: *const c_char) -> u64 {
    let config = if config_json.is_null() {
        RuntimeConfig::default()
    } else {
        match ptr_to_string(config_json)
            .ok()
            .and_then(|text| serde_json::from_str::<RuntimeConfig>(&text).ok())
        {
            Some(value) => value,
            None => RuntimeConfig::default(),
        }
    };
    RuntimeRegistry::global().create_runtime(config)
}

#[no_mangle]
pub extern "C" fn asmote_runtime_destroy(runtime_id: u64) -> i32 {
    match RuntimeRegistry::global().destroy_runtime(runtime_id) {
        Ok(()) => 0,
        Err(_) => -1,
    }
}

#[no_mangle]
pub extern "C" fn asmote_session_open(runtime_id: u64, config_json: *const c_char) -> u64 {
    let Ok(config_text) = ptr_to_string(config_json) else {
        return 0;
    };
    let Ok(config) = serde_json::from_str::<SessionConfig>(&config_text) else {
        return 0;
    };
    let Ok(runtime) = RuntimeRegistry::global().runtime(runtime_id) else {
        return 0;
    };
    runtime.open_session(config).unwrap_or(0)
}

#[no_mangle]
pub extern "C" fn asmote_session_close(runtime_id: u64, session_id: u64) -> i32 {
    let Ok(runtime) = RuntimeRegistry::global().runtime(runtime_id) else {
        return -1;
    };
    match runtime.close_session(session_id) {
        Ok(()) => 0,
        Err(_) => -2,
    }
}

#[no_mangle]
pub extern "C" fn asmote_session_submit_graph(
    runtime_id: u64,
    session_id: u64,
    graph_json: *const c_char,
) -> u64 {
    let Ok(graph_text) = ptr_to_string(graph_json) else {
        return 0;
    };
    let Ok(graph) = serde_json::from_str::<TransferGraph>(&graph_text) else {
        return 0;
    };
    let Ok(runtime) = RuntimeRegistry::global().runtime(runtime_id) else {
        return 0;
    };
    runtime.submit_graph(session_id, graph).unwrap_or(0)
}

#[no_mangle]
pub extern "C" fn asmote_session_cancel_graph(
    runtime_id: u64,
    session_id: u64,
    graph_id: u64,
) -> i32 {
    let Ok(runtime) = RuntimeRegistry::global().runtime(runtime_id) else {
        return -1;
    };
    match runtime.cancel_graph(session_id, graph_id) {
        Ok(()) => 0,
        Err(_) => -2,
    }
}

#[no_mangle]
pub extern "C" fn asmote_session_poll_events_cursor(
    runtime_id: u64,
    session_id: u64,
    cursor: u64,
    limit: u32,
) -> *mut c_char {
    let result = (|| -> CoreResult<String> {
        let runtime = RuntimeRegistry::global()
            .runtime(runtime_id)
            .map_err(|error| CoreError::Internal(error.to_string()))?;
        let payload = runtime
            .poll_events(session_id, cursor, limit as usize)
            .map_err(|error| CoreError::Internal(error.to_string()))?;
        Ok(serde_json::to_string(&payload)
            .unwrap_or_else(|_| "{\"events\":[],\"next_cursor\":0}".to_string()))
    })();

    match result {
        Ok(value) => into_c_string(value),
        Err(error) => into_c_string(json!({ "error": error.to_string() }).to_string()),
    }
}

#[no_mangle]
pub extern "C" fn asmote_session_query_metrics(runtime_id: u64, session_id: u64) -> *mut c_char {
    let result = (|| -> CoreResult<String> {
        let runtime = RuntimeRegistry::global()
            .runtime(runtime_id)
            .map_err(|error| CoreError::Internal(error.to_string()))?;
        let payload = runtime
            .query_metrics(session_id)
            .map_err(|error| CoreError::Internal(error.to_string()))?;
        Ok(serde_json::to_string(&payload).unwrap_or_else(|_| "{}".to_string()))
    })();

    match result {
        Ok(value) => into_c_string(value),
        Err(error) => into_c_string(json!({ "error": error.to_string() }).to_string()),
    }
}

#[no_mangle]
pub extern "C" fn asmote_free_c_string(ptr: *mut c_char) {
    if ptr.is_null() {
        return;
    }
    unsafe {
        let _ = CString::from_raw(ptr);
    }
}
