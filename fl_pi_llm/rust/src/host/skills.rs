//! Skills for a Rust host: [`crate::skills`] (what a skill is, finding them,
//! the prompt) and the `skill` tool over a host's directory of them.

pub use crate::skills::*;

use super::{BoxFuture, Cancel, Tool, ToolCall, ToolDef, ToolResult};

/// The `skill` tool over [skills], offering only [offered].
pub struct SkillTool {
    pub skills: Skills,
    pub offered: Vec<Skill>,
}

impl Tool for SkillTool {
    fn def(&self) -> ToolDef {
        ToolDef {
            name: TOOL_NAME.into(),
            description: TOOL_DESCRIPTION.into(),
            parameters: tool_parameters(),
            label: Some("Skill".into()),
            sequential: false,
        }
    }

    fn execute(&self, call: ToolCall, _cancel: Cancel) -> BoxFuture<'_, Result<ToolResult, String>> {
        Box::pin(async move { self.skills.run_tool(&self.offered, &call.args).map(ToolResult::text) })
    }
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    use super::*;

    #[tokio::test]
    async fn the_tool_answers_what_skills_answer() {
        let root = std::env::temp_dir().join(format!("fl-pi-llm-host-skills-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        std::fs::create_dir_all(root.join("cleanup")).unwrap();
        std::fs::write(root.join("cleanup/SKILL.md"), "---\nname: Cleanup\ndescription: Frees space.\n---\nSteps\n").unwrap();
        let skills = Skills::new(&root);
        let tool = SkillTool { offered: skills.list(), skills };
        let call = |args| ToolCall { session_id: "s".into(), id: "c".into(), name: TOOL_NAME.into(), args };
        let res = tool.execute(call(json!({ "name": "cleanup" })), Cancel::new()).await.unwrap();
        assert!(res.content[0]["text"].as_str().unwrap().ends_with("Steps\n"));
        assert!(tool.execute(call(json!({ "name": "nope" })), Cancel::new()).await.is_err());
        std::fs::remove_dir_all(&root).unwrap();
    }
}
