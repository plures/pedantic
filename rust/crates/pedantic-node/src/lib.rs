use napi::bindgen_prelude::*;
use napi_derive::napi;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn to_napi_err(err: impl std::fmt::Display) -> napi::Error {
    napi::Error::new(Status::GenericFailure, format!("{err}"))
}

// ---------------------------------------------------------------------------
// Parser bindings
// ---------------------------------------------------------------------------

/// Parse a DSC v3 YAML document and return the parsed model as JSON.
#[napi]
pub fn parse_dsc_v3(yaml: String) -> Result<String> {
    let doc = pedantic_core::parse_dsc_v3(&yaml).map_err(to_napi_err)?;
    serde_json::to_string_pretty(&doc).map_err(to_napi_err)
}

/// Parse a Simple DSL YAML document and return the parsed model as JSON.
#[napi]
pub fn parse_simple_dsl(yaml: String) -> Result<String> {
    let doc = pedantic_core::parse_simple_dsl(&yaml).map_err(to_napi_err)?;
    serde_json::to_string_pretty(&doc).map_err(to_napi_err)
}

// ---------------------------------------------------------------------------
// Validator bindings
// ---------------------------------------------------------------------------

#[napi(object)]
pub struct ValidationResultJs {
    pub ok: bool,
    pub errors: Vec<String>,
}

/// Validate a DSC v3 YAML document. Returns an object with `ok` and `errors`.
#[napi]
pub fn validate_document(yaml: String) -> Result<ValidationResultJs> {
    let doc = pedantic_core::parse_dsc_v3(&yaml).map_err(to_napi_err)?;
    let report = pedantic_core::validate_document(&doc);
    Ok(ValidationResultJs {
        ok: report.is_ok(),
        errors: report.errors.iter().map(|e| e.to_string()).collect(),
    })
}

// ---------------------------------------------------------------------------
// Planner bindings
// ---------------------------------------------------------------------------

/// Plan execution order for a DSC v3 YAML document. Returns the plan as JSON.
#[napi]
pub fn plan_execution(yaml: String) -> Result<String> {
    let doc = pedantic_core::parse_dsc_v3(&yaml).map_err(to_napi_err)?;
    let plan = pedantic_core::plan_execution(&doc).map_err(to_napi_err)?;
    serde_json::to_string_pretty(&plan).map_err(to_napi_err)
}

// ---------------------------------------------------------------------------
// Export bindings
// ---------------------------------------------------------------------------

/// Validate a DSC v3 YAML document and export the validation report as JUnit XML.
#[napi]
pub fn export_junit(yaml: String, suite_name: Option<String>) -> Result<String> {
    let doc = pedantic_core::parse_dsc_v3(&yaml).map_err(to_napi_err)?;
    let report = pedantic_core::validate_document(&doc);
    let name = suite_name.as_deref().unwrap_or("pedantic");
    Ok(pedantic_core::export::export_junit(&report, name))
}

/// Validate a DSC v3 YAML document and export the validation report as SARIF JSON.
#[napi]
pub fn export_sarif(yaml: String, tool_name: Option<String>) -> Result<String> {
    let doc = pedantic_core::parse_dsc_v3(&yaml).map_err(to_napi_err)?;
    let report = pedantic_core::validate_document(&doc);
    let name = tool_name.as_deref().unwrap_or("pedantic");
    Ok(pedantic_core::export::export_sarif(&report, name))
}

/// Export a parsed DSC v3 document back to YAML (round-trip).
#[napi]
pub fn export_dsc_v3(yaml: String) -> Result<String> {
    let doc = pedantic_core::parse_dsc_v3(&yaml).map_err(to_napi_err)?;
    pedantic_core::export::export_dsc_v3(&doc).map_err(to_napi_err)
}

// ---------------------------------------------------------------------------
// Ansible mapping bindings
// ---------------------------------------------------------------------------

#[napi(object)]
pub struct MappingEntryJs {
    pub dsc_resource: String,
    pub ansible_module: String,
}

/// Load the bundled Ansible mapping and return entries.
#[napi]
pub fn load_ansible_mapping() -> Result<Vec<MappingEntryJs>> {
    let mapping = pedantic_core::load_ansible_mapping().map_err(to_napi_err)?;
    Ok(mapping
        .mappings
        .into_iter()
        .map(|e| MappingEntryJs {
            dsc_resource: e.dsc_resource,
            ansible_module: e.ansible_module,
        })
        .collect())
}

// ---------------------------------------------------------------------------
// Praxis engine bindings
// ---------------------------------------------------------------------------

/// Run the praxis engine on a DSC v3 YAML document. Returns the engine
/// outcome as JSON including fired rules, iteration count, facts, events,
/// and any constraint violations.
#[napi]
pub fn run_praxis_engine(yaml: String) -> Result<String> {
    use pedantic_core::praxis::*;

    let doc = pedantic_core::parse_dsc_v3(&yaml).map_err(to_napi_err)?;

    let engine = Engine::builder()
        .add_rule(Box::new(ParseAndValidate))
        .add_rule(Box::new(DetectDrift))
        .add_rule(Box::new(EscalateFailure))
        .add_rule(Box::new(PlanRemediation))
        .add_constraint(Box::new(NoSetWithoutTest))
        .add_constraint(Box::new(NoDeployDraft))
        .build();

    let facts = vec![Fact::ConfigDocument(doc)];
    let outcome = engine.evaluate(facts);

    serde_json::to_string_pretty(&outcome).map_err(to_napi_err)
}
