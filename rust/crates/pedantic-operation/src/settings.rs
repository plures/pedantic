//! Deterministic settings composition for immutable operation plans.
//!
//! PX and capability packages supply the layers and safety requirements. This
//! module only applies the declared precedence and verifies the resulting
//! values, without making policy decisions.

use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::BTreeMap;
use thiserror::Error;

pub type Settings = BTreeMap<String, Value>;

#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SettingsLayers {
    pub built_in: Settings,
    pub general: Settings,
    pub target: Settings,
    pub plan: Settings,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CapabilitySafetyRequirement {
    pub capability: String,
    pub required_settings: Settings,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ResolvedSettings {
    pub values: Settings,
    pub sources: BTreeMap<String, SettingSource>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum SettingSource {
    BuiltIn,
    General,
    Target,
    Plan,
}

#[derive(Clone, Debug, Error, Eq, PartialEq)]
pub enum SettingsError {
    #[error("setting keys must not be empty")]
    EmptyKey,
    #[error("capability safety requirement has an empty capability")]
    EmptyCapability,
    #[error("setting {setting} violates the safety requirement for {capability}")]
    SafetyRequirement { capability: String, setting: String },
}

/// Resolves settings from lowest to highest precedence and validates capability
/// requirements against the final result.
pub fn resolve_settings(
    layers: &SettingsLayers,
    requirements: &[CapabilitySafetyRequirement],
) -> Result<ResolvedSettings, SettingsError> {
    let mut values = Settings::new();
    let mut sources = BTreeMap::new();
    for (settings, source) in [
        (&layers.built_in, SettingSource::BuiltIn),
        (&layers.general, SettingSource::General),
        (&layers.target, SettingSource::Target),
        (&layers.plan, SettingSource::Plan),
    ] {
        for (key, value) in settings {
            if key.is_empty() {
                return Err(SettingsError::EmptyKey);
            }
            values.insert(key.clone(), value.clone());
            sources.insert(key.clone(), source.clone());
        }
    }
    for requirement in requirements {
        if requirement.capability.is_empty() {
            return Err(SettingsError::EmptyCapability);
        }
        for (setting, required_value) in &requirement.required_settings {
            if setting.is_empty() {
                return Err(SettingsError::EmptyKey);
            }
            if values.get(setting) != Some(required_value) {
                return Err(SettingsError::SafetyRequirement {
                    capability: requirement.capability.clone(),
                    setting: setting.clone(),
                });
            }
        }
    }
    Ok(ResolvedSettings { values, sources })
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn resolves_settings_from_builtin_through_plan_precedence() {
        let layers = SettingsLayers {
            built_in: Settings::from([
                ("retryLimit".into(), json!(1)),
                ("transport".into(), json!("ssh")),
            ]),
            general: Settings::from([("retryLimit".into(), json!(2))]),
            target: Settings::from([("retryLimit".into(), json!(3))]),
            plan: Settings::from([("retryLimit".into(), json!(4))]),
        };

        let resolved = resolve_settings(&layers, &[]).expect("settings resolve");

        assert_eq!(resolved.values["retryLimit"], json!(4));
        assert_eq!(resolved.values["transport"], json!("ssh"));
        assert_eq!(resolved.sources["retryLimit"], SettingSource::Plan);
        assert_eq!(resolved.sources["transport"], SettingSource::BuiltIn);
    }

    #[test]
    fn rejects_a_plan_setting_that_violates_a_capability_safety_requirement() {
        let layers = SettingsLayers {
            plan: Settings::from([("rebootAllowed".into(), json!(true))]),
            ..SettingsLayers::default()
        };
        let requirements = [CapabilitySafetyRequirement {
            capability: "system.reboot/v1".into(),
            required_settings: Settings::from([("rebootAllowed".into(), json!(false))]),
        }];

        assert_eq!(
            resolve_settings(&layers, &requirements),
            Err(SettingsError::SafetyRequirement {
                capability: "system.reboot/v1".into(),
                setting: "rebootAllowed".into(),
            })
        );
    }
}
