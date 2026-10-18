//! Windows-specific host facts used by the durable target agent.
//!
//! Policy and authorization stay in `pedantic-agent`; this crate only exposes
//! host-adapter facts and intentionally compiles to a harmless stub elsewhere.

use thiserror::Error;

#[derive(Debug, Error)]
pub enum WindowsAgentError {
    #[error("Windows target-agent adapters require x86-64 Windows 10 or later")]
    UnsupportedPlatform,
    #[error("Windows shared host data could not be read: {0}")]
    HostData(#[from] std::io::Error),
    #[error("Windows shared host data returned {0} bytes instead of four")]
    IncompleteHostData(usize),
}

/// Returns a stable, target-local OS boot sequence, not proof of an intended reboot.
#[cfg(all(windows, target_arch = "x86_64"))]
pub fn boot_identity() -> Result<String, WindowsAgentError> {
    use pedantic_operation::boot_identity::BootIdentity;
    use std::mem::offset_of;
    use windows_sys::Wdk::System::SystemServices::KUSER_SHARED_DATA;

    // Windows maps this read-only shared page into each x86-64 process.
    const SHARED_USER_DATA: usize = 0x7ffe0000;
    let major = read_host_u32(SHARED_USER_DATA + offset_of!(KUSER_SHARED_DATA, NtMajorVersion))?;
    if major < 10 {
        return Err(WindowsAgentError::UnsupportedPlatform);
    }
    let sequence = read_host_u32(SHARED_USER_DATA + offset_of!(KUSER_SHARED_DATA, BootId))?;
    Ok(BootIdentity::windows_boot_sequence(sequence).to_string())
}

#[cfg(all(windows, target_arch = "x86_64"))]
fn read_host_u32(address: usize) -> Result<u32, WindowsAgentError> {
    use std::{ffi::c_void, mem::size_of};
    use windows_sys::Win32::System::{
        Diagnostics::Debug::ReadProcessMemory, Threading::GetCurrentProcess,
    };

    let mut value = 0u32;
    let mut bytes_read = 0usize;
    // The OS validates the source address; the destination is exactly one live u32.
    let succeeded = unsafe {
        ReadProcessMemory(
            GetCurrentProcess(),
            address as *const c_void,
            (&mut value as *mut u32).cast(),
            size_of::<u32>(),
            &mut bytes_read,
        )
    };
    if succeeded == 0 {
        return Err(WindowsAgentError::HostData(std::io::Error::last_os_error()));
    }
    if bytes_read != size_of::<u32>() {
        return Err(WindowsAgentError::IncompleteHostData(bytes_read));
    }
    Ok(value)
}

#[cfg(not(all(windows, target_arch = "x86_64")))]
pub fn boot_identity() -> Result<String, WindowsAgentError> {
    Err(WindowsAgentError::UnsupportedPlatform)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[cfg(all(windows, target_arch = "x86_64"))]
    #[test]
    fn boot_identity_is_stable_within_one_boot() {
        let initial = boot_identity().unwrap();
        for _ in 0..3 {
            std::thread::sleep(std::time::Duration::from_millis(50));
            assert_eq!(boot_identity().unwrap(), initial);
        }
    }

    #[cfg(all(windows, target_arch = "x86_64"))]
    #[test]
    fn boot_identity_matches_parent_process() {
        const EXPECTED: &str = "PEDANTIC_TEST_EXPECTED_BOOT_IDENTITY";
        match std::env::var(EXPECTED) {
            Ok(expected) => assert_eq!(boot_identity().unwrap(), expected),
            Err(std::env::VarError::NotPresent) => {
                let expected = boot_identity().unwrap();
                for _ in 0..2 {
                    let output = std::process::Command::new(std::env::current_exe().unwrap())
                        .args(["--exact", "tests::boot_identity_matches_parent_process"])
                        .env(EXPECTED, &expected)
                        .output()
                        .unwrap();
                    assert!(
                        output.status.success(),
                        "child failed: {} {}",
                        String::from_utf8_lossy(&output.stdout),
                        String::from_utf8_lossy(&output.stderr)
                    );
                }
            }
            Err(error) => panic!("invalid child-test environment: {error}"),
        }
    }

    #[cfg(all(windows, target_arch = "x86_64"))]
    #[test]
    fn unavailable_host_data_is_an_explicit_error() {
        assert!(matches!(
            read_host_u32(0),
            Err(WindowsAgentError::HostData(_))
        ));
    }

    #[cfg(not(all(windows, target_arch = "x86_64")))]
    #[test]
    fn rejects_windows_adapter_use_off_windows() {
        assert!(matches!(
            boot_identity(),
            Err(WindowsAgentError::UnsupportedPlatform)
        ));
    }
}
