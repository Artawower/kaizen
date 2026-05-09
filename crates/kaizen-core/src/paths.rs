use std::path::PathBuf;

pub trait PathProvider: Send + Sync {
    fn home_dir(&self) -> Option<PathBuf>;
    fn config_dir(&self) -> Option<PathBuf>;
    fn is_tool_available(&self, tool: &str) -> bool;
}

#[cfg(test)]
pub mod test {
    use super::*;

    #[derive(Default)]
    pub struct TestPathProvider {
        pub home: Option<PathBuf>,
        pub config: Option<PathBuf>,
        pub available_tools: Vec<String>,
    }

    impl PathProvider for TestPathProvider {
        fn home_dir(&self) -> Option<PathBuf> {
            self.home.clone()
        }

        fn config_dir(&self) -> Option<PathBuf> {
            self.config.clone()
        }

        fn is_tool_available(&self, tool: &str) -> bool {
            self.available_tools.iter().any(|t| t == tool)
        }
    }
}
