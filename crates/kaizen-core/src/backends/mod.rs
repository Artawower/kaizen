pub(crate) mod common;
mod nix;
mod upt;

pub mod detect;

pub use nix::NixSyncBackend;
pub use upt::UptSyncBackend;
