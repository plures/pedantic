use napi::bindgen_prelude::*;
use napi_derive::napi;

fn to_napi_err(err: pedantic_core::Error) -> napi::Error {
    napi::Error::new(Status::GenericFailure, format!("{err}"))
}

#[napi(object)]
pub struct MappingEntryJs {
    pub ansible_module: Option<String>,
    pub ansible_primitive: Option<String>,
    pub dsc_command: String,
    pub description: Option<String>,
    pub supports_check: Option<bool>,
    pub supports_diff: Option<bool>,
    pub backend: Option<String>,
}

impl From<pedantic_core::MappingEntry> for MappingEntryJs {
    fn from(entry: pedantic_core::MappingEntry) -> Self {
        Self {
            ansible_module: entry.ansible_module,
            ansible_primitive: entry.ansible_primitive,
            dsc_command: entry.dsc_command,
            description: entry.description,
            supports_check: entry.supports_check,
            supports_diff: entry.supports_diff,
            backend: entry.backend,
        }
    }
}

#[napi]
pub fn render_template(source: String, vars_json: String, strict: Option<bool>) -> Result<String> {
    let vars: serde_json::Value = serde_json::from_str(&vars_json)
        .map_err(|e| napi::Error::new(Status::InvalidArg, format!("Invalid vars JSON: {e}")))?;
    let strict = strict.unwrap_or(true);
    let result = pedantic_core::render_template(&source, &vars, strict).map_err(to_napi_err)?;
    Ok(result.rendered)
}

#[napi]
pub fn render_scenario_report(report_json: String, template: Option<String>, format: Option<String>) -> Result<String> {
    let report: pedantic_core::ScenarioReport = serde_json::from_str(&report_json)
        .map_err(|e| napi::Error::new(Status::InvalidArg, format!("Invalid report JSON: {e}")))?;
    let rendered = pedantic_core::render_scenario_report(
        &report,
        template.as_deref(),
        format.as_deref().unwrap_or("markdown"),
    )
    .map_err(to_napi_err)?;
    Ok(rendered)
}

#[napi]
pub fn load_mapping_yaml(yaml: String) -> Result<Vec<MappingEntryJs>> {
    let entries = pedantic_core::load_mapping_from_str(&yaml).map_err(to_napi_err)?;
    Ok(entries.into_iter().map(MappingEntryJs::from).collect())
}

#[napi(object)]
pub struct ScenarioInstanceJs {
    pub id: String,
    pub host: Option<String>,
    pub vars_json: String,
}

#[napi]
pub fn expand_scenario_yaml(scenario_yaml: String) -> Result<Vec<ScenarioInstanceJs>> {
    let spec: pedantic_core::ScenarioSpec = serde_yaml::from_str(&scenario_yaml)
        .map_err(|e| napi::Error::new(Status::InvalidArg, format!("Invalid scenario YAML: {e}")))?;
    let instances = pedantic_core::expand_scenario(&spec).map_err(to_napi_err)?;
    instances
        .into_iter()
        .map(|i| {
            let vars_json = serde_json::to_string(&i.vars)
                .map_err(|e| napi::Error::new(Status::GenericFailure, format!("{e}")))?;
            Ok(ScenarioInstanceJs {
                id: i.id,
                host: i.host,
                vars_json,
            })
        })
        .collect()
}

#[napi(object)]
pub struct PlanTaskJs {
    pub id: String,
    pub kind: String,
    pub command: Option<String>,
    pub params_json: Option<String>,
    pub when: Option<String>,
    pub register: Option<String>,
    pub notify: Option<Vec<String>>,
    pub listen: Option<String>,
    pub changed_when: Option<String>,
    pub failed_when: Option<String>,
    pub is_handler: Option<bool>,
    pub tags: Option<Vec<String>>,
    pub loop_item_json: Option<String>,
    pub skipped: Option<bool>,
    pub when_result: Option<bool>,
    pub error: Option<String>,
    pub changed: Option<bool>,
    pub diff: Option<String>,
    pub diffs_json: Option<String>,
    pub check: Option<bool>,
    pub result_json: Option<String>,
}

fn task_instance_to_js(t: pedantic_core::TaskInstance) -> Result<PlanTaskJs> {
    let (kind, command, params_json) = match t.kind {
        pedantic_core::TaskKind::Resource { command, params } => {
            let json = serde_json::to_string(&params)
                .map_err(|e| napi::Error::new(Status::GenericFailure, format!("{e}")))?;
            ("resource".into(), Some(command), Some(json))
        }
        pedantic_core::TaskKind::Runtime(op) => {
            let json = serde_json::to_string(&op)
                .map_err(|e| napi::Error::new(Status::GenericFailure, format!("{e}")))?;
            ("runtime".into(), None, Some(json))
        }
    };

    let loop_item_json = t
        .loop_item
        .map(|v| serde_json::to_string(&v))
        .transpose()
        .map_err(|e| napi::Error::new(Status::GenericFailure, format!("{e}")))?;

    Ok(PlanTaskJs {
        id: t.id,
        kind,
        command,
        params_json,
        when: t.when,
        register: t.register,
        notify: Some(t.notify.clone()),
        listen: t.listen,
        changed_when: t.changed_when,
        failed_when: t.failed_when,
        is_handler: Some(t.meta.is_handler),
        tags: Some(t.meta.tags),
        loop_item_json,
        skipped: None,
        when_result: None,
        error: None,
        changed: None,
        diff: None,
        diffs_json: None,
        check: None,
        result_json: None,
    })
}

#[napi]
pub fn plan_from_resources(resources_json: String, manifest_yaml: String) -> Result<Vec<PlanTaskJs>> {
    let resources: Vec<pedantic_core::Resource> = serde_json::from_str(&resources_json)
        .map_err(|e| napi::Error::new(Status::InvalidArg, format!("Invalid resources JSON: {e}")))?;
    let manifest = pedantic_core::load_mapping_from_str(&manifest_yaml).map_err(to_napi_err)?;

    let plan = pedantic_core::plan_from_resources(&resources, &manifest);
    plan.tasks
        .into_iter()
        .map(task_instance_to_js)
        .collect()
}

#[napi]
pub fn plan_with_facts(
    resources_json: String,
    manifest_yaml: String,
    facts_json: String,
) -> Result<Vec<PlanTaskJs>> {
    let resources: Vec<pedantic_core::Resource> = serde_json::from_str(&resources_json)
        .map_err(|e| napi::Error::new(Status::InvalidArg, format!("Invalid resources JSON: {e}")))?;
    let manifest = pedantic_core::load_mapping_from_str(&manifest_yaml).map_err(to_napi_err)?;
    let facts_value: serde_json::Value = serde_json::from_str(&facts_json)
        .map_err(|e| napi::Error::new(Status::InvalidArg, format!("Invalid facts JSON: {e}")))?;
    let facts_map = facts_value
        .as_object()
        .cloned()
        .ok_or_else(|| napi::Error::new(Status::InvalidArg, "facts_json must be a JSON object"))?;

    let plan = pedantic_core::plan_from_resources(&resources, &manifest);
    let decisions = pedantic_core::apply_when(&plan, &facts_map);

    decisions
        .into_iter()
        .map(|d| {
            let mut t = task_instance_to_js(d.task)?;
            t.skipped = Some(d.skipped);
            t.when_result = d.when_result;
            t.error = d.error;
            if let Some(res) = d.result {
                t.changed = Some(res.changed);
                t.check = Some(res.check);
                if let Some(diffs) = res.diffs {
                    let diffs_json = serde_json::to_string(&diffs)
                        .map_err(|e| napi::Error::new(Status::GenericFailure, format!("{e}")))?;
                    t.diffs_json = Some(diffs_json.clone());
                    // keep legacy diff as stringified diffs for now
                    t.diff = Some(diffs_json);
                }
                t.result_json = res
                    .data
                    .map(|v| serde_json::to_string(&v))
                    .transpose()
                    .map_err(|e| napi::Error::new(Status::GenericFailure, format!("{e}")))?;
            }
            Ok(t)
        })
        .collect()
}
