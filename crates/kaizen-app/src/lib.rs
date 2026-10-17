//! Application use cases shared by Kaizen's CLI, TUI, and GUI.
//!
//! This layer coordinates `kaizen-core` with infrastructure through ports. It
//! contains no presentation code; adapters can be added once concrete I/O flows
//! are implemented.
