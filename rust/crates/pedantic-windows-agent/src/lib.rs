//! Windows-specific host facts used by the durable target agent.
//!
//! Policy and authorization stay in `pedantic-agent`; this crate only exposes
//! host-adapter facts and intentionally compiles to a harmless stub elsewhere.

use thiserror::Error;

#[derive(Debug, Error)]
pub enum WindowsAgentError {
    #[error("Windows target-agent adapters are unavailable on this platform")]
    UnsupportedPlatform,
}

/// Returns a stable boot identity suitable for detecting a reboot.
#[cfg(windows)]
pub fn boot_identity() -> Result<String, WindowsAgentError> {
    use windows_sys::Win32::System::SystemInformation::GetTickCount64;

    // The boot-relative tick count is intentionally only a process-local host
    // fact; the agent records it before and after a reboot checkpoint.
    Ok(unsafe { GetTickCount64() }.to_string())
}

#[cfg(not(windows))]
pub fn boot_identity() -> Result<String, WindowsAgentError> {
    Err(WindowsAgentError::UnsupportedPlatform)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[cfg(not(windows))]
    #[test]
    fn rejects_windows_adapter_use_off_windows() {
        assert!(matches!(
            boot_identity(),
            Err(WindowsAgentError::UnsupportedPlatform)
        ));
    }
}
