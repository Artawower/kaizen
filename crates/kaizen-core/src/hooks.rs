use crate::KaizenError;

pub trait HookRunner: Send + Sync {
    fn run(&self, commands: &[String]) -> Result<(), KaizenError>;
}
