use crate::validator::ValidationReport;

pub fn export_junit(report: &ValidationReport, suite_name: &str) -> String {
    let mut output = String::new();
    output.push_str(&format!(
        "<testsuite name=\"{}\" tests=\"{}\" failures=\"{}\">\n",
        suite_name,
        report.errors.len(),
        report.errors.len()
    ));

    if report.errors.is_empty() {
        output.push_str("  <testcase name=\"validation\"/>\n");
    } else {
        for error in &report.errors {
            output.push_str("  <testcase name=\"validation\">\n");
            output.push_str(&format!(
                "    <failure message=\"{}\"/>\n",
                xml_escape(&error.to_string())
            ));
            output.push_str("  </testcase>\n");
        }
    }

    output.push_str("</testsuite>\n");
    output
}

fn xml_escape(input: &str) -> String {
    input
        .replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
        .replace('\'', "&apos;")
}
