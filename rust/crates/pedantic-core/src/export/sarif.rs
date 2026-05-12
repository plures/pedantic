use crate::validator::ValidationReport;
use serde_json::json;

pub fn export_sarif(report: &ValidationReport, tool_name: &str) -> String {
    let results: Vec<_> = report
        .errors
        .iter()
        .map(|error| {
            json!({
                "ruleId": "validation",
                "level": "error",
                "message": {
                    "text": error.to_string()
                }
            })
        })
        .collect();

    let sarif = json!({
        "version": "2.1.0",
        "$schema": "https://json.schemastore.org/sarif-2.1.0.json",
        "runs": [
            {
                "tool": {
                    "driver": {
                        "name": tool_name
                    }
                },
                "results": results
            }
        ]
    });

    serde_json::to_string_pretty(&sarif).unwrap_or_else(|_| "{}".to_string())
}
