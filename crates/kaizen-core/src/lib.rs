//! Pure domain model and deterministic logic for Kaizen.
//!
//! This crate must not depend on a user interface or perform operating-system I/O.
//! It will own configuration and package models, validation, resolution, and plan
//! calculation. Applying plans belongs to the application/infrastructure layers.

pub mod config;
pub mod package;
pub mod plan;
pub mod registry;
pub mod state;
