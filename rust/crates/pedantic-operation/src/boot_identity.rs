use std::{fmt, str::FromStr};
use thiserror::Error;

const WINDOWS_BOOT_SEQUENCE_PREFIX: &str = "windows-boot-sequence-v1:";

/// A target-local boot sequence, not a globally unique or rollback-proof identity.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct BootIdentity(u32);

#[derive(Clone, Copy, Debug, Error, Eq, PartialEq)]
#[error("boot identity is legacy, malformed or unsupported; explicit reconciliation is required")]
pub struct BootIdentityError;

impl BootIdentity {
    pub fn windows_boot_sequence(sequence: u32) -> Self {
        Self(sequence)
    }
}

impl fmt::Display for BootIdentity {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(formatter, "{WINDOWS_BOOT_SEQUENCE_PREFIX}{}", self.0)
    }
}

impl FromStr for BootIdentity {
    type Err = BootIdentityError;

    fn from_str(value: &str) -> Result<Self, Self::Err> {
        let sequence = value
            .strip_prefix(WINDOWS_BOOT_SEQUENCE_PREFIX)
            .ok_or(BootIdentityError)?
            .parse::<u32>()
            .map_err(|_| BootIdentityError)?;
        let identity = Self::windows_boot_sequence(sequence);
        if identity.to_string() != value {
            return Err(BootIdentityError);
        }
        Ok(identity)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn canonical_sequences_round_trip_and_compare() {
        for sequence in [0, 1, 42, u32::MAX] {
            let identity = BootIdentity::windows_boot_sequence(sequence);
            assert_eq!(identity.to_string().parse(), Ok(identity));
        }
        assert_ne!(
            BootIdentity::windows_boot_sequence(1),
            BootIdentity::windows_boot_sequence(2)
        );
    }

    #[test]
    fn legacy_unknown_and_noncanonical_values_require_reconciliation() {
        for value in [
            "",
            "12345",
            "boot-1",
            "windows-boot-sequence-v2:1",
            "windows-boot-sequence-v1:",
            "windows-boot-sequence-v1:-1",
            "windows-boot-sequence-v1:+1",
            "windows-boot-sequence-v1:01",
            "windows-boot-sequence-v1: 1",
            "windows-boot-sequence-v1:1 ",
            "windows-boot-sequence-v1:4294967296",
        ] {
            assert_eq!(value.parse::<BootIdentity>(), Err(BootIdentityError));
        }
    }
}
