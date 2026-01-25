pub mod error {
    use thiserror::Error;

    #[derive(Debug, Error)]
    pub enum Error {
        #[error("YAML parse error: {0}")]
        Yaml(#[from] serde_yaml::Error),
        #[error("JSON parse error: {0}")]
        Json(#[from] serde_json::Error),
        #[error("Template error: {0}")]
        Template(#[from] minijinja::Error),
        #[error("Invalid state: {0}")]
        InvalidState(String),
    }
}

pub mod types {
    use serde::{Deserialize, Serialize};
    use serde_json::Value;

    #[derive(Debug, Clone, Serialize, Deserialize, Default)]
    pub struct Meta {
        pub dialect: Option<String>,
        pub version: Option<String>,
    }

    #[derive(Debug, Clone, Serialize, Deserialize)]
    pub struct Resource {
        pub name: String,
        pub command: String,
        #[serde(default)]
        pub params: Value,
    }

    #[derive(Debug, Clone, Serialize, Deserialize, Default)]
    pub struct Document {
        pub resources: Vec<Resource>,
        pub meta: Meta,
    }
}

pub mod mapping {
    use serde::{Deserialize, Serialize};
    use std::collections::HashMap;

    use crate::error::Error;

    #[derive(Debug, Clone, Serialize, Deserialize)]
    pub struct MappingEntry {
        #[serde(rename = "ansibleModule")]
        pub ansible_module: Option<String>,
        #[serde(rename = "ansiblePrimitive")]
        pub ansible_primitive: Option<String>,
        #[serde(rename = "dscCommand")]
        pub dsc_command: String,
        #[serde(default)]
        pub description: Option<String>,
        #[serde(default)]
        pub parameters: Option<HashMap<String, String>>,
        #[serde(rename = "supportsCheck", default)]
        pub supports_check: Option<bool>,
        #[serde(rename = "supportsDiff", default)]
        pub supports_diff: Option<bool>,
        #[serde(default)]
        pub backend: Option<String>,
    }

    impl MappingEntry {
        pub fn is_primitive(&self) -> bool {
            self.ansible_primitive.is_some()
        }

        pub fn label(&self) -> &str {
            if let Some(ref p) = self.ansible_primitive {
                p
            } else if let Some(ref m) = self.ansible_module {
                m
            } else {
                "unknown"
            }
        }
    }

    pub type MappingManifest = Vec<MappingEntry>;

    pub fn load_mapping_from_str(input: &str) -> Result<MappingManifest, Error> {
        let entries: MappingManifest = serde_yaml::from_str(input)?;
        Ok(entries)
    }

    pub fn load_mapping_from_reader<R: std::io::Read>(reader: R) -> Result<MappingManifest, Error> {
        let entries: MappingManifest = serde_yaml::from_reader(reader)?;
        Ok(entries)
    }
}

pub mod runtime {
    use serde::{Deserialize, Serialize};
    use serde_json::Value;

    #[derive(Debug, Clone, Serialize, Deserialize, Default)]
    pub struct DiffEntry {
        #[serde(default)]
        pub path: Option<String>,
        #[serde(default)]
        pub message: Option<String>,
        #[serde(default)]
        pub before: Option<Value>,
        #[serde(default)]
        pub after: Option<Value>,
    }

    #[derive(Debug, Clone, Serialize, Deserialize)]
    pub enum TaskKind {
        Resource { command: String, params: Value },
        Runtime(RuntimeOp),
    }

    #[derive(Debug, Clone, Serialize, Deserialize)]
    pub enum RuntimeOp {
        Register { name: String },
        SetFact { facts: Value },
        Debug { message: Option<String>, var: Option<String> },
        When { expression: String },
        Loop { items: Vec<Value>, item_var: Option<String> },
        Group { name: Option<String>, when: Option<String> },
        GroupBy { key: String, value: Value },
    }

    #[derive(Debug, Clone, Serialize, Deserialize, Default)]
    pub struct TaskMeta {
        #[serde(default)]
        pub tags: Vec<String>,
        pub origin: Option<String>,
        #[serde(default)]
        pub is_handler: bool,
    }

    #[derive(Debug, Clone, Serialize, Deserialize)]
    pub struct Task {
        pub id: String,
        pub kind: TaskKind,
        #[serde(default)]
        pub when: Option<String>,
        #[serde(default)]
        pub register: Option<String>,
        #[serde(default)]
        pub loop_items: Option<Vec<Value>>,
        #[serde(default)]
        pub loop_var: Option<String>,
        #[serde(default)]
        pub notify: Vec<String>,
        #[serde(default)]
        pub listen: Option<String>,
        #[serde(default)]
        pub changed_when: Option<String>,
        #[serde(default)]
        pub failed_when: Option<String>,
        #[serde(default)]
        pub meta: TaskMeta,
    }

    #[derive(Debug, Clone, Serialize, Deserialize)]
    pub struct TaskInstance {
        pub id: String,
        pub kind: TaskKind,
        #[serde(default)]
        pub when: Option<String>,
        #[serde(default)]
        pub register: Option<String>,
        #[serde(default)]
        pub loop_item: Option<Value>,
        #[serde(default)]
        pub notify: Vec<String>,
        #[serde(default)]
        pub listen: Option<String>,
        #[serde(default)]
        pub changed_when: Option<String>,
        #[serde(default)]
        pub failed_when: Option<String>,
        #[serde(default)]
        pub meta: TaskMeta,
    }

    #[derive(Debug, Clone, Serialize, Deserialize, Default)]
    pub struct Plan {
        pub tasks: Vec<TaskInstance>,
    }

    #[derive(Debug, Clone, Serialize, Deserialize, Default)]
    pub struct TaskResult {
        pub changed: bool,
        #[serde(default)]
        pub check: bool,
        #[serde(default)]
        pub diffs: Option<Vec<DiffEntry>>,
        #[serde(default)]
        pub data: Option<Value>,
    }

    #[derive(Debug, Clone, Serialize, Deserialize)]
    pub struct TaskOutcome {
        pub task: TaskInstance,
        pub skipped: bool,
        pub when_result: Option<bool>,
        pub error: Option<String>,
        pub result: Option<TaskResult>,
    }

    pub fn expand_loops(tasks: &[Task]) -> Plan {
        let mut expanded = Vec::new();

        for task in tasks {
            if let Some(items) = &task.loop_items {
                for (idx, item) in items.iter().enumerate() {
                    let id = format!("{}[{}]", task.id, idx);
                    expanded.push(TaskInstance {
                        id,
                        kind: task.kind.clone(),
                        when: task.when.clone(),
                        register: task.register.clone(),
                        loop_item: Some(item.clone()),
                        notify: task.notify.clone(),
                        listen: task.listen.clone(),
                        changed_when: task.changed_when.clone(),
                        failed_when: task.failed_when.clone(),
                        meta: task.meta.clone(),
                    });
                }
            } else {
                expanded.push(TaskInstance {
                    id: task.id.clone(),
                    kind: task.kind.clone(),
                    when: task.when.clone(),
                    register: task.register.clone(),
                    loop_item: None,
                    notify: task.notify.clone(),
                    listen: task.listen.clone(),
                    changed_when: task.changed_when.clone(),
                    failed_when: task.failed_when.clone(),
                    meta: task.meta.clone(),
                });
            }
        }

        Plan { tasks: expanded }
    }
}

pub mod planner {
    use serde_json::Value;

    use crate::mapping::MappingManifest;
    use crate::runtime::{expand_loops, Plan, RuntimeOp, Task, TaskKind, TaskMeta};
    use crate::types::Resource;

    fn sanitize_params(params: &Value) -> Value {
        match params {
            Value::Object(map) => {
                let mut cleaned = map.clone();
                for key in [
                    "when",
                    "loop",
                    "items",
                    "with_items",
                    "loop_var",
                    "register",
                    "notify",
                    "listen",
                    "changed_when",
                    "failed_when",
                    "tags",
                    "check",
                    "check_mode",
                ] {
                    cleaned.remove(key);
                }
                Value::Object(cleaned)
            }
            other => other.clone(),
        }
    }

    fn loop_items_from(params: &Value) -> Option<Vec<Value>> {
        match params {
            Value::Object(map) => {
                if let Some(Value::Array(items)) = map.get("loop") {
                    return Some(items.clone());
                }
                if let Some(Value::Array(items)) = map.get("items") {
                    return Some(items.clone());
                }
                if let Some(Value::Array(items)) = map.get("with_items") {
                    return Some(items.clone());
                }
                None
            }
            _ => None,
        }
    }

    fn str_field(params: &Value, key: &str) -> Option<String> {
        params
            .as_object()
            .and_then(|m| m.get(key))
            .and_then(|v| v.as_str().map(|s| s.to_string()))
    }

    fn string_list_field(params: &Value, key: &str) -> Vec<String> {
        match params.as_object().and_then(|m| m.get(key)) {
            Some(Value::String(s)) => vec![s.clone()],
            Some(Value::Array(items)) => items
                .iter()
                .filter_map(|v| v.as_str().map(|s| s.to_string()))
                .collect(),
            _ => Vec::new(),
        }
    }

    fn runtime_op_from(command: &str, params: &Value) -> Option<RuntimeOp> {
        match command {
            "dsc.vars.register" => Some(RuntimeOp::Register {
                name: str_field(params, "name").unwrap_or_else(|| "result".into()),
            }),
            "dsc.vars.set" => Some(RuntimeOp::SetFact {
                facts: sanitize_params(params),
            }),
            "dsc.vars.debug" => Some(RuntimeOp::Debug {
                message: str_field(params, "msg"),
                var: str_field(params, "var"),
            }),
            "dsc.when" => Some(RuntimeOp::When {
                expression: str_field(params, "condition").unwrap_or_default(),
            }),
            "dsc.group.tasks" => Some(RuntimeOp::Group {
                name: str_field(params, "name"),
                when: str_field(params, "when"),
            }),
            "dsc.group.by" => {
                let key = str_field(params, "key").unwrap_or_default();
                let value = params
                    .as_object()
                    .and_then(|m| m.get("value"))
                    .cloned()
                    .unwrap_or(Value::Null);
                Some(RuntimeOp::GroupBy { key, value })
            }
            "dsc.loop" => {
                let items = loop_items_from(params).unwrap_or_default();
                let item_var = str_field(params, "item_var");
                Some(RuntimeOp::Loop { items, item_var })
            }
            _ => None,
        }
    }

    pub fn plan_from_resources(resources: &[Resource], manifest: &MappingManifest) -> Plan {
        let mut tasks = Vec::new();

        for res in resources {
            let params = res.params.clone();
            let when = str_field(&params, "when");
            let register = str_field(&params, "register");
            let loop_items = loop_items_from(&params);
            let loop_var = str_field(&params, "loop_var").or_else(|| Some("item".into()));
            let sanitized_params = sanitize_params(&params);
            let notify = string_list_field(&params, "notify");
            let listen = str_field(&params, "listen");
            let changed_when = str_field(&params, "changed_when");
            let failed_when = str_field(&params, "failed_when");
            let tags = string_list_field(&params, "tags");

            let mapping = manifest
                .iter()
                .find(|m| m.dsc_command == res.command);

            let kind = if let Some(entry) = mapping {
                if entry.is_primitive() {
                    runtime_op_from(&res.command, &sanitized_params)
                        .map(TaskKind::Runtime)
                        .unwrap_or(TaskKind::Runtime(RuntimeOp::Debug {
                            message: Some(format!("unhandled primitive: {}", res.command)),
                            var: None,
                        }))
                } else {
                    TaskKind::Resource {
                        command: res.command.clone(),
                        params: sanitized_params.clone(),
                    }
                }
            } else {
                TaskKind::Resource {
                    command: res.command.clone(),
                    params: sanitized_params.clone(),
                }
            };

            tasks.push(Task {
                id: res.name.clone(),
                kind,
                when: when.clone(),
                register: register.clone(),
                loop_items: loop_items.clone(),
                loop_var: loop_var.clone(),
                notify,
                listen: listen.clone(),
                changed_when,
                failed_when,
                meta: TaskMeta {
                    tags,
                    origin: None,
                    is_handler: listen.is_some(),
                },
            });
        }

        expand_loops(&tasks)
    }
}

pub mod when {
    use minijinja::{value::Value as JValue, Environment};
    use serde_json::Value;

    pub struct WhenEvaluator;

    fn facts_to_jinja(facts: &serde_json::Map<String, Value>) -> Result<JValue, String> {
        Ok(JValue::from_serialize(facts))
    }

    impl WhenEvaluator {
        /// Evaluate a Jinja expression (no statements) with facts as context.
        /// Undefined variables will error (strict) to catch typos early.
        pub fn eval(expr: &str, facts: &serde_json::Map<String, Value>) -> Result<bool, String> {
            let env = Environment::new();
            // Default minijinja is strict for expressions; no need to change undefined behavior here.
            let compiled = env
                .compile_expression(expr)
                .map_err(|e| format!("when compile error: {e}"))?;
            let ctx = facts_to_jinja(facts)?;
            let value = compiled
                .eval(ctx)
                .map_err(|e| format!("when eval error: {e}"))?;
            Ok(value.is_true())
        }

        pub fn eval_option(
            expr: &Option<String>,
            facts: &serde_json::Map<String, Value>,
        ) -> Result<Option<bool>, String> {
            if let Some(ref e) = expr {
                Self::eval(e, facts).map(Some)
            } else {
                Ok(None)
            }
        }
    }
}

pub mod executor {
    use serde_json::Value;

    use std::collections::{HashMap, HashSet};

    use crate::runtime::{Plan, TaskInstance, TaskOutcome, TaskResult};
    use crate::when::WhenEvaluator;

    pub fn apply_when(plan: &Plan, facts: &serde_json::Map<String, Value>) -> Vec<TaskOutcome> {
        plan.tasks
            .iter()
            .map(|t| match WhenEvaluator::eval_option(&t.when, facts) {
                Ok(result_opt) => {
                    let skipped = result_opt == Some(false);
                    TaskOutcome {
                        task: t.clone(),
                        skipped,
                        when_result: result_opt,
                        error: None,
                        result: None,
                    }
                }
                Err(e) => TaskOutcome {
                    task: t.clone(),
                    skipped: true,
                    when_result: None,
                    error: Some(e),
                    result: None,
                },
            })
            .collect()
    }

    /// Apply changed_when / failed_when overrides using Jinja expressions with facts + result in scope.
    /// Returns the updated TaskResult and an optional error string when failed_when triggers.
    pub fn apply_overrides(
        task: &TaskInstance,
        base_result: TaskResult,
        facts: &serde_json::Map<String, Value>,
    ) -> Result<(TaskResult, Option<String>), String> {
        let mut merged = facts.clone();
        let result_value = serde_json::to_value(&base_result)
            .map_err(|e| format!("result serialization error: {e}"))?;
        merged.insert("result".into(), result_value);

        let mut result = base_result;
        if let Some(ref expr) = task.changed_when {
            let val = WhenEvaluator::eval(expr, &merged)?;
            result.changed = val;
        }

        let mut error = None;
        if let Some(ref expr) = task.failed_when {
            let val = WhenEvaluator::eval(expr, &merged)?;
            if val {
                error = Some("failed_when triggered".to_string());
            }
        }

        Ok((result, error))
    }

    /// Determine which handlers should run based on task outcomes and return the handler task instances in execution order.
    /// A handler is triggered when a notifying task reports changed=true, is not skipped, and has no error.
    pub fn collect_handler_tasks(plan: &Plan, outcomes: &[TaskOutcome]) -> Vec<TaskInstance> {
        // Map handler name -> first TaskInstance found
        let mut handlers: HashMap<String, TaskInstance> = HashMap::new();
        for t in &plan.tasks {
            if t.meta.is_handler {
                let name = t
                    .listen
                    .clone()
                    .unwrap_or_else(|| t.id.clone());
                handlers.entry(name).or_insert_with(|| t.clone());
            }
        }

        let mut queue: Vec<String> = Vec::new();
        let mut seen: HashSet<String> = HashSet::new();

        for outcome in outcomes {
            let changed = outcome
                .result
                .as_ref()
                .map(|r| r.changed)
                .unwrap_or(false);
            if changed && !outcome.skipped && outcome.error.is_none() {
                for n in &outcome.task.notify {
                    if seen.insert(n.clone()) {
                        queue.push(n.clone());
                    }
                }
            }
        }

        queue
            .into_iter()
            .filter_map(|name| handlers.get(&name).cloned())
            .collect()
    }
}

pub mod scenario {
    use serde::{Deserialize, Serialize};
    use serde_json::{Map, Value};

    use crate::error::Error;

    #[derive(Debug, Clone, Serialize, Deserialize, Default)]
    pub struct MatrixSpec {
        #[serde(default)]
        pub hosts: Vec<String>,
        #[serde(default)]
        pub vars: Map<String, Value>,
    }

    #[derive(Debug, Clone, Serialize, Deserialize, Default)]
    pub struct PhaseStep {
        pub kind: String, // "apply" | "command" | "assert"
        #[serde(default)]
        pub apply: Option<String>,
        #[serde(default)]
        pub command: Option<String>,
        #[serde(default)]
        pub assert: Option<Value>,
        #[serde(default)]
        pub check: Option<bool>,
    }

    #[derive(Debug, Clone, Serialize, Deserialize, Default)]
    pub struct PhaseSpec {
        #[serde(default)]
        pub prepare: Vec<PhaseStep>,
        #[serde(default)]
        pub converge: Vec<PhaseStep>,
        #[serde(default)]
        pub verify: Vec<PhaseStep>,
        #[serde(default)]
        pub destroy: Vec<PhaseStep>,
    }

    #[derive(Debug, Clone, Serialize, Deserialize, Default)]
    pub struct ReportSpec {
        #[serde(default)]
        pub template: Option<String>,
        #[serde(default)]
        pub format: Vec<String>,
        #[serde(default)]
        pub artifacts: Vec<Value>,
    }

    #[derive(Debug, Clone, Serialize, Deserialize, Default)]
    pub struct ScenarioSpec {
        pub name: String,
        #[serde(default)]
        pub matrix: MatrixSpec,
        #[serde(default)]
        pub phases: PhaseSpec,
        #[serde(default)]
        pub asserts: Vec<Value>,
        #[serde(default)]
        pub report: ReportSpec,
    }

    #[derive(Debug, Clone, Serialize, Deserialize, Default)]
    pub struct ScenarioInstance {
        pub id: String,
        pub host: Option<String>,
        pub vars: Map<String, Value>,
        pub phases: PhaseSpec,
    }

    #[derive(Debug, Clone, Serialize, Deserialize, Default)]
    pub struct PhaseResultSummary {
        pub name: String,
        pub status: String, // ok | failed | skipped
        #[serde(default)]
        pub duration_ms: Option<u64>,
        #[serde(default)]
        pub details: Option<String>,
    }

    #[derive(Debug, Clone, Serialize, Deserialize, Default)]
    pub struct AssertResult {
        pub name: String,
        pub status: String, // pass | fail | skip
        #[serde(default)]
        pub message: Option<String>,
    }

    #[derive(Debug, Clone, Serialize, Deserialize, Default)]
    pub struct ScenarioInstanceReport {
        pub id: String,
        pub host: Option<String>,
        pub vars: Map<String, Value>,
        #[serde(default)]
        pub phases: Vec<PhaseResultSummary>,
        #[serde(default)]
        pub asserts: Vec<AssertResult>,
        #[serde(default)]
        pub tasks: Vec<Value>, // placeholder for task-level outcomes
    }

    #[derive(Debug, Clone, Serialize, Deserialize, Default)]
    pub struct ScenarioReport {
        pub name: String,
        #[serde(default)]
        pub instances: Vec<ScenarioInstanceReport>,
        #[serde(default)]
        pub summary: Value,
    }

    fn expand_var_space(vars: &Map<String, Value>) -> Vec<Map<String, Value>> {
        let mut acc: Vec<Map<String, Value>> = vec![Map::new()];

        for (key, value) in vars.iter() {
            let choices: Vec<Value> = match value {
                Value::Array(items) => items.clone(),
                v => vec![v.clone()],
            };

            let mut next = Vec::new();
            for base in acc.into_iter() {
                for choice in &choices {
                    let mut new_map = base.clone();
                    new_map.insert(key.clone(), choice.clone());
                    next.push(new_map);
                }
            }
            acc = next;
        }

        acc
    }

    pub fn expand_scenario(spec: &ScenarioSpec) -> Result<Vec<ScenarioInstance>, Error> {
        let hosts = if spec.matrix.hosts.is_empty() {
            vec![None]
        } else {
            spec.matrix.hosts.iter().cloned().map(Some).collect()
        };

        let var_space = expand_var_space(&spec.matrix.vars);

        let mut instances = Vec::new();
        for (h_idx, host) in hosts.iter().enumerate() {
            for (v_idx, vars) in var_space.iter().enumerate() {
                let id = if hosts.len() > 1 || var_space.len() > 1 {
                    format!("{}-h{}-v{}", spec.name, h_idx, v_idx)
                } else {
                    spec.name.clone()
                };

                instances.push(ScenarioInstance {
                    id,
                    host: host.clone(),
                    vars: vars.clone(),
                    phases: spec.phases.clone(),
                });
            }
        }

        Ok(instances)
    }
}

pub mod report {
        use minijinja::Environment;

        use crate::error::Error;
        use crate::scenario::ScenarioReport;

        fn builtin_template(name: &str, format: &str) -> Option<&'static str> {
                match (name, format) {
                        ("builtin:markdown/basic", "markdown") => Some(r#"## Scenario Report: {{ name }}

Summary:
- Instances: {{ instances|length }}

{% for inst in instances %}
### Instance {{ inst.id }}{% if inst.host %} (host: {{ inst.host }}){% endif %}
    - Vars: {{ inst.vars }}
- Phases:
{% for ph in inst.phases %}
    - {{ ph.name }}: {{ ph.status }}{% if ph.duration_ms %} ({{ ph.duration_ms }} ms){% endif %}{% if ph.details %} — {{ ph.details }}{% endif %}
{% endfor %}
- Asserts:
{% for a in inst.asserts %}
    - {{ a.name }}: {{ a.status }}{% if a.message %} — {{ a.message }}{% endif %}
{% endfor %}

{% endfor %}
"#),
                        ("builtin:html/basic", "html") => Some(r#"<h2>Scenario Report: {{ name }}</h2>
<p>Instances: {{ instances|length }}</p>
{% for inst in instances %}
<h3>Instance {{ inst.id }}{% if inst.host %} (host: {{ inst.host }}){% endif %}</h3>
<p><strong>Vars:</strong> <code>{{ inst.vars }}</code></p>
<h4>Phases</h4>
<ul>
{% for ph in inst.phases %}
    <li>{{ ph.name }}: {{ ph.status }}{% if ph.duration_ms %} ({{ ph.duration_ms }} ms){% endif %}{% if ph.details %} — {{ ph.details }}{% endif %}</li>
{% endfor %}
</ul>
<h4>Asserts</h4>
<ul>
{% for a in inst.asserts %}
    <li>{{ a.name }}: {{ a.status }}{% if a.message %} — {{ a.message }}{% endif %}</li>
{% endfor %}
</ul>
{% endfor %}
"#),
                        _ => None,
                }
        }

        pub fn render_scenario_report(
                report: &ScenarioReport,
                template: Option<&str>,
                format: &str,
        ) -> Result<String, Error> {
                let tpl_name = template.unwrap_or("builtin:markdown/basic");
                let tpl_source = if let Some(src) = builtin_template(tpl_name, format) {
                        src.to_string()
                } else {
                        tpl_name.to_string()
                };

                let env = Environment::new();
                let tpl = env.template_from_str(&tpl_source)?;
                let rendered = tpl.render(report)?;
                Ok(rendered)
        }
}

pub mod template {
    use minijinja::{Environment, UndefinedBehavior};
    use serde_json::Value;
    use sha2::{Digest, Sha256};

    use crate::error::Error;

    #[derive(Debug, Clone, PartialEq, Eq)]
    pub struct TemplateResult {
        pub rendered: String,
        pub checksum_sha256: String,
    }

    pub fn render_template(source: &str, vars: &Value, strict: bool) -> Result<TemplateResult, Error> {
        let mut env = Environment::new();
        env.set_undefined_behavior(if strict {
            UndefinedBehavior::Strict
        } else {
            UndefinedBehavior::Lenient
        });

        let template = env.template_from_str(source)?;
        let rendered = template.render(vars)?;

        let mut hasher = Sha256::new();
        hasher.update(rendered.as_bytes());
        let checksum_sha256 = hex::encode(hasher.finalize());

        Ok(TemplateResult {
            rendered,
            checksum_sha256,
        })
    }
}

pub use error::Error;
pub use mapping::{load_mapping_from_reader, load_mapping_from_str, MappingEntry, MappingManifest};
pub use planner::plan_from_resources;
pub use runtime::{expand_loops, DiffEntry, Plan, RuntimeOp, Task, TaskInstance, TaskKind, TaskMeta, TaskOutcome, TaskResult};
pub use executor::{apply_overrides, apply_when, collect_handler_tasks};
pub use scenario::{
    expand_scenario,
    AssertResult,
    MatrixSpec,
    PhaseResultSummary,
    PhaseSpec,
    PhaseStep,
    ReportSpec,
    ScenarioInstance,
    ScenarioInstanceReport,
    ScenarioReport,
    ScenarioSpec,
};
pub use report::render_scenario_report;
pub use template::{render_template, TemplateResult};
pub use types::{Document, Meta, Resource};

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn renders_template_and_checksum() {
        let vars = json!({"name": "world"});
        let result = render_template("Hello {{ name }}!", &vars, true).expect("rendered");
        assert_eq!(result.rendered, "Hello world!");
        assert_eq!(result.checksum_sha256.len(), 64);
    }

        #[test]
        fn loads_mapping_entries() {
                let yaml = "- ansibleModule: \"ansible.builtin.package\"\n  dscCommand: \"dsc.install\"\n  description: \"Example mapping\"\n  supportsCheck: true\n  supportsDiff: false\n- ansiblePrimitive: \"register\"\n  dscCommand: \"dsc.vars.register\"\n  description: \"primitive mapping\"\n";
                let entries = load_mapping_from_str(yaml).expect("parsed");
                assert_eq!(entries.len(), 2);
                let first = &entries[0];
                assert_eq!(first.ansible_module.as_deref(), Some("ansible.builtin.package"));
                assert_eq!(first.dsc_command, "dsc.install");
                assert_eq!(first.supports_check, Some(true));

                let second = &entries[1];
                assert_eq!(second.ansible_primitive.as_deref(), Some("register"));
                assert!(second.is_primitive());
        }

        #[test]
        fn expands_loops_into_instances() {
                let task = Task {
                        id: "t1".into(),
                        kind: TaskKind::Runtime(RuntimeOp::Debug {
                                message: Some("hello".into()),
                                var: None,
                        }),
                        when: None,
                        register: None,
                        loop_items: Some(vec![json!(1), json!(2)]),
                        loop_var: Some("item".into()),
                    notify: Vec::new(),
                    listen: None,
                    changed_when: None,
                    failed_when: None,
                        meta: Default::default(),
                };

                let plan = expand_loops(&[task]);
                assert_eq!(plan.tasks.len(), 2);
                assert_eq!(plan.tasks[0].id, "t1[0]");
                assert_eq!(plan.tasks[1].loop_item, Some(json!(2)));
        }

            #[test]
            fn plans_resources_and_runtime_tasks() {
                let manifest = load_mapping_from_str(
                    "- ansibleModule: ansible.builtin.package\n  dscCommand: dsc.install\n- ansiblePrimitive: register\n  dscCommand: dsc.vars.register\n",
                )
                .expect("manifest");

                let resources = vec![
                    Resource {
                        name: "reg1".into(),
                        command: "dsc.vars.register".into(),
                        params: json!({"name": "result1"}),
                    },
                    Resource {
                        name: "pkg1".into(),
                        command: "dsc.install".into(),
                        params: json!({
                            "packages": ["git"],
                            "loop": ["a", "b"],
                            "register": "pkg_out",
                            "when": "true == true"
                        }),
                    },
                ];

                let plan = plan_from_resources(&resources, &manifest);
                assert_eq!(plan.tasks.len(), 3); // reg1 + pkg1 loop expanded to 2
                assert!(matches!(plan.tasks[0].kind, TaskKind::Runtime(_)));
                assert!(matches!(plan.tasks[1].kind, TaskKind::Resource { .. }));
                assert_eq!(plan.tasks[2].loop_item, Some(json!("b")));
            }

            #[test]
            fn applies_when_conditions() {
                use serde_json::json;
                let tasks = vec![TaskInstance {
                    id: "t1".into(),
                    kind: TaskKind::Runtime(RuntimeOp::Debug {
                        message: None,
                        var: None,
                    }),
                    when: Some("flag == true".into()),
                    register: None,
                    loop_item: None,
                    notify: Vec::new(),
                    listen: None,
                    changed_when: None,
                    failed_when: None,
                    meta: Default::default(),
                }];

                let plan = Plan { tasks };
                let facts = json!({"flag": true}).as_object().cloned().unwrap();
                let decisions = apply_when(&plan, &facts);
                assert_eq!(decisions.len(), 1);
                assert_eq!(decisions[0].skipped, false);
                assert_eq!(decisions[0].when_result, Some(true));
            }

            #[test]
            fn applies_changed_and_failed_overrides() {
                use serde_json::json;
                let task = TaskInstance {
                    id: "t1".into(),
                    kind: TaskKind::Resource {
                        command: "dsc.file".into(),
                        params: json!({"path": "x"}),
                    },
                    when: None,
                    register: None,
                    loop_item: None,
                    notify: Vec::new(),
                    listen: None,
                    changed_when: Some("result.changed == false".into()),
                    failed_when: Some("result.changed == true".into()),
                    meta: Default::default(),
                };

                let facts = json!({}).as_object().cloned().unwrap();
                let base = TaskResult {
                    changed: true,
                    check: false,
                    diffs: None,
                    data: None,
                };

                let (res, err) = apply_overrides(&task, base, &facts).expect("overrides applied");
                assert_eq!(res.changed, false);
                assert_eq!(err, Some("failed_when triggered".to_string()));
            }

            #[test]
            fn collects_handlers_from_changed_tasks() {
                use serde_json::json;
                let mut plan = Plan { tasks: vec![] };

                // regular task that notifies handler
                plan.tasks.push(TaskInstance {
                    id: "t1".into(),
                    kind: TaskKind::Resource {
                        command: "dsc.file".into(),
                        params: json!({"path": "x"}),
                    },
                    when: None,
                    register: None,
                    loop_item: None,
                    notify: vec!["restart service".into()],
                    listen: None,
                    changed_when: None,
                    failed_when: None,
                    meta: Default::default(),
                });

                // handler task listening for the name
                plan.tasks.push(TaskInstance {
                    id: "handler1".into(),
                    kind: TaskKind::Resource {
                        command: "dsc.service.restart".into(),
                        params: json!({"name": "svc"}),
                    },
                    when: None,
                    register: None,
                    loop_item: None,
                    notify: Vec::new(),
                    listen: Some("restart service".into()),
                    changed_when: None,
                    failed_when: None,
                    meta: TaskMeta {
                        tags: Vec::new(),
                        origin: None,
                        is_handler: true,
                    },
                });

                let outcomes = vec![TaskOutcome {
                    task: plan.tasks[0].clone(),
                    skipped: false,
                    when_result: Some(true),
                    error: None,
                    result: Some(TaskResult {
                        changed: true,
                        check: false,
                        diffs: None,
                        data: None,
                    }),
                }];

                let handlers = collect_handler_tasks(&plan, &outcomes);
                assert_eq!(handlers.len(), 1);
                assert_eq!(handlers[0].id, "handler1");
            }

            #[test]
            fn expands_scenario_matrix() {
                use serde_json::json;
                let spec = ScenarioSpec {
                    name: "web".into(),
                    matrix: MatrixSpec {
                        hosts: vec!["h1".into(), "h2".into()],
                        vars: json!({"port": [80, 8080]}).as_object().cloned().unwrap(),
                    },
                    phases: PhaseSpec::default(),
                    asserts: Vec::new(),
                    report: ReportSpec::default(),
                };

                let instances = expand_scenario(&spec).expect("expanded");
                assert_eq!(instances.len(), 4); // 2 hosts x 2 ports
                assert!(instances.iter().any(|i| i.vars.get("port") == Some(&json!(80))));
                assert!(instances.iter().any(|i| i.host.as_deref() == Some("h1")));
            }

            #[test]
            fn renders_builtin_markdown_report() {
                use serde_json::json;
                let report = ScenarioReport {
                    name: "demo".into(),
                    instances: vec![ScenarioInstanceReport {
                        id: "demo-0".into(),
                        host: Some("h1".into()),
                        vars: json!({"port": 80}).as_object().cloned().unwrap(),
                        phases: vec![PhaseResultSummary {
                            name: "converge".into(),
                            status: "ok".into(),
                            duration_ms: Some(10),
                            details: None,
                        }],
                        asserts: vec![AssertResult {
                            name: "http".into(),
                            status: "pass".into(),
                            message: Some("200 OK".into()),
                        }],
                        tasks: Vec::new(),
                    }],
                    summary: json!({}),
                };

                let rendered = render_scenario_report(&report, None, "markdown").expect("rendered");
                assert!(rendered.contains("Scenario Report: demo"));
                assert!(rendered.contains("demo-0"));
                assert!(rendered.contains("pass"));
            }
}
