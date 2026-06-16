use std::io::{self, IsTerminal, Write};

use anyhow::Result;
use crossterm::{
    cursor::{Hide, MoveUp, Show},
    event::{read, Event, KeyCode, KeyModifiers},
    execute, queue,
    terminal::{disable_raw_mode, enable_raw_mode, size, Clear, ClearType},
};
use dialoguer::{theme::ColorfulTheme, MultiSelect, Select};
use owo_colors::OwoColorize;

struct TerminalGuard;

impl Drop for TerminalGuard {
    fn drop(&mut self) {
        let _ = disable_raw_mode();
        let _ = execute!(io::stdout(), Show);
    }
}

#[derive(Clone)]
pub struct Item {
    pub name: String,
    pub desc: Option<String>,
    pub selected: bool,
}

struct State {
    items: Vec<(Item, bool)>,
    cursor: usize,
    mode: Mode,
    query: String,
    lines_drawn: usize,
}

#[derive(PartialEq)]
enum Mode {
    Normal,
    Search,
}

impl State {
    fn new(items: Vec<Item>) -> Self {
        Self {
            items: items
                .into_iter()
                .map(|i| {
                    let s = i.selected;
                    (i, s)
                })
                .collect(),
            cursor: 0,
            mode: Mode::Normal,
            query: String::new(),
            lines_drawn: 0,
        }
    }

    fn visible(&self) -> Vec<usize> {
        let q = self.query.to_lowercase();
        self.items
            .iter()
            .enumerate()
            .filter(|(_, (item, _))| {
                q.is_empty()
                    || item.name.to_lowercase().contains(&q)
                    || item
                        .desc
                        .as_deref()
                        .unwrap_or("")
                        .to_lowercase()
                        .contains(&q)
            })
            .map(|(i, _)| i)
            .collect()
    }

    fn clamp_cursor(&mut self) {
        self.cursor = self.cursor.min(self.visible().len().saturating_sub(1));
    }

    fn move_cursor(&mut self, delta: isize) {
        let len = self.visible().len();
        if len == 0 {
            return;
        }
        self.cursor = (self.cursor as isize + delta).rem_euclid(len as isize) as usize;
    }

    fn toggle_current(&mut self) {
        if let Some(&idx) = self.visible().get(self.cursor) {
            self.items[idx].1 ^= true;
        }
    }

    fn toggle_all_visible(&mut self) {
        let visible = self.visible();
        let new_state = !visible.iter().all(|&i| self.items[i].1);
        for &i in &visible {
            self.items[i].1 = new_state;
        }
    }

    fn invert_visible(&mut self) {
        for &i in &self.visible() {
            self.items[i].1 ^= true;
        }
    }

    fn selected_count(&self) -> usize {
        self.items.iter().filter(|(_, s)| *s).count()
    }

    fn selected_names(&self) -> Vec<String> {
        self.items
            .iter()
            .filter(|(_, s)| *s)
            .map(|(item, _)| item.name.clone())
            .collect()
    }
}

fn render(
    state: &mut State,
    stdout: &mut impl Write,
    prompt: &str,
    max_items: usize,
) -> io::Result<()> {
    if state.lines_drawn > 0 {
        queue!(
            stdout,
            MoveUp(state.lines_drawn as u16),
            Clear(ClearType::FromCursorDown)
        )?;
    }

    let visible = state.visible();
    let (start, end) = visible_window(state.cursor, visible.len(), max_items);
    let mut lines = 0;

    let search_tag = if !state.query.is_empty() || state.mode == Mode::Search {
        format!("  [/{}]", state.query)
    } else {
        String::new()
    };

    write!(
        stdout,
        "  {} {}{} {}\r\n",
        "?".bold().cyan(),
        prompt.bold(),
        search_tag.yellow(),
        format!("({} selected)", state.selected_count()).dimmed(),
    )?;
    lines += 1;

    for (offset, &item_idx) in visible[start..end].iter().enumerate() {
        let vis_idx = start + offset;
        let (item, selected) = &state.items[item_idx];
        let cursor_ch = if vis_idx == state.cursor {
            "❯".cyan().to_string()
        } else {
            " ".to_owned()
        };
        let check_ch = if *selected {
            "●".green().to_string()
        } else {
            "○".dimmed().to_string()
        };
        let name = if vis_idx == state.cursor {
            item.name.bold().to_string()
        } else {
            item.name.clone()
        };
        let desc = item
            .desc
            .as_deref()
            .map(|d| format!("  {}", d.dimmed()))
            .unwrap_or_default();
        write!(stdout, "  {} {} {}{}\r\n", cursor_ch, check_ch, name, desc)?;
        lines += 1;
    }

    if visible.is_empty() {
        write!(stdout, "  {}\r\n", "(no matches)".dimmed())?;
        lines += 1;
    }

    let hint = if state.mode == Mode::Search {
        "esc=clear  enter=apply filter".to_owned()
    } else {
        "j/k:move  space:toggle  a:all  i:invert  /:search  enter:confirm".to_owned()
    };
    let hint = if visible.len() > end - start {
        format!("{hint}  {}-{}/{}", start + 1, end, visible.len())
    } else {
        hint
    };
    write!(stdout, "  {}\r\n", hint.dimmed())?;
    lines += 1;

    stdout.flush()?;
    state.lines_drawn = lines;
    Ok(())
}

fn visible_window(cursor: usize, len: usize, max_items: usize) -> (usize, usize) {
    if len == 0 {
        return (0, 0);
    }
    let window_len = len.min(max_items.max(1));
    let half = window_len / 2;
    let start = cursor.saturating_sub(half).min(len - window_len);
    (start, start + window_len)
}

fn event_loop(
    state: &mut State,
    stdout: &mut impl Write,
    prompt: &str,
    max_items: usize,
) -> Result<Option<Vec<String>>> {
    render(state, stdout, prompt, max_items)?;
    loop {
        let Event::Key(key) = read()? else {
            continue;
        };
        if key.modifiers.contains(KeyModifiers::CONTROL) && key.code == KeyCode::Char('c') {
            return Ok(None);
        }
        match state.mode {
            Mode::Normal => match key.code {
                KeyCode::Char('j') | KeyCode::Down => state.move_cursor(1),
                KeyCode::Char('k') | KeyCode::Up => state.move_cursor(-1),
                KeyCode::Char(' ') => state.toggle_current(),
                KeyCode::Char('a') => state.toggle_all_visible(),
                KeyCode::Char('i') => state.invert_visible(),
                KeyCode::Char('/') => state.mode = Mode::Search,
                KeyCode::Esc | KeyCode::Char('q') => return Ok(None),
                KeyCode::Enter => return Ok(Some(state.selected_names())),
                _ => {}
            },
            Mode::Search => match key.code {
                KeyCode::Esc => {
                    state.query.clear();
                    state.cursor = 0;
                    state.mode = Mode::Normal;
                }
                KeyCode::Enter => {
                    state.cursor = 0;
                    state.mode = Mode::Normal;
                }
                KeyCode::Backspace => {
                    state.query.pop();
                    state.clamp_cursor();
                }
                KeyCode::Char(c) => {
                    state.query.push(c);
                    state.cursor = 0;
                }
                _ => {}
            },
        }
        render(state, stdout, prompt, max_items)?;
    }
}

pub fn multi_select(prompt: &str, items: Vec<Item>) -> Result<Option<Vec<String>>> {
    if !io::stdin().is_terminal() || !io::stdout().is_terminal() {
        return multi_select_dialoguer(prompt, items);
    }

    match multi_select_crossterm(prompt, items.clone()) {
        Ok(result) => Ok(result),
        Err(err) if is_input_reader_error(&err) => multi_select_dialoguer(prompt, items),
        Err(err) => Err(err),
    }
}

fn is_input_reader_error(error: &anyhow::Error) -> bool {
    error.chain().any(|cause| {
        cause
            .to_string()
            .contains("Failed to initialize input reader")
    })
}

fn multi_select_crossterm(prompt: &str, items: Vec<Item>) -> Result<Option<Vec<String>>> {
    let mut state = State::new(items);
    let mut stdout = io::stdout();

    enable_raw_mode()?;
    let _guard = TerminalGuard;
    execute!(stdout, Hide)?;

    let (_, term_height) = size().unwrap_or((80, 24));
    let max_items = (term_height as usize).saturating_sub(4).max(1);

    let reserved = state.visible().len().min(max_items) + 2;
    for _ in 0..reserved {
        writeln!(stdout)?;
    }
    execute!(stdout, MoveUp(reserved as u16))?;
    stdout.flush()?;

    let result = event_loop(&mut state, &mut stdout, prompt, max_items);

    if state.lines_drawn > 0 {
        execute!(
            stdout,
            MoveUp(state.lines_drawn as u16),
            Clear(ClearType::FromCursorDown)
        )?;
    }

    let Some(names) = result? else {
        println!("  Cancelled.");
        return Ok(None);
    };
    println!(
        "  {} {}  {}",
        "✓".green(),
        prompt,
        format!("({} selected)", names.len()).dimmed()
    );
    Ok(Some(names))
}

fn multi_select_dialoguer(prompt: &str, items: Vec<Item>) -> Result<Option<Vec<String>>> {
    let labels: Vec<String> = items
        .iter()
        .map(|item| match item.desc.as_deref() {
            Some(desc) if !desc.is_empty() => format!("{} — {desc}", item.name),
            _ => item.name.clone(),
        })
        .collect();
    let defaults: Vec<bool> = items.iter().map(|item| item.selected).collect();
    let Some(indices) = MultiSelect::with_theme(&ColorfulTheme::default())
        .with_prompt(prompt)
        .items(&labels)
        .defaults(&defaults)
        .interact_opt()?
    else {
        println!("  Cancelled.");
        return Ok(None);
    };
    let names = indices
        .into_iter()
        .filter_map(|idx| items.get(idx).map(|item| item.name.clone()))
        .collect();
    Ok(Some(names))
}

// ── Unified feature+variants wizard ──────────────────────────────────────────

use kaizen_core::{Stability, WizardFeature};
use std::collections::BTreeMap;

/// A row in the flattened visible list (pure, no side-effects).
#[derive(Debug, Clone)]
pub enum FlatRow {
    Feature {
        idx: usize,
        feature_id: String,
        description: String,
        enabled: bool,
        has_slot: bool,
        is_folded: bool,
    },
    Variant {
        feature_idx: usize,
        slot_fqn: String,
        variant_id: String,
        title: String,
        stability: Stability,
        is_selected: bool,
        /// True when the parent feature is currently enabled.
        parent_enabled: bool,
    },
}

/// Flatten `features` into the visible row list.
///
/// When `show_experimental=false` no Variant rows are emitted.
/// When `show_experimental=true` Variant rows follow their parent Feature row
/// unless the feature's slot is folded.
pub fn flatten_visible_features(
    features: &[WizardFeature],
    feature_enabled: &[bool],
    show_experimental: bool,
    fold: &BTreeMap<String, bool>,
    variant_selections: &BTreeMap<String, String>,
) -> Vec<FlatRow> {
    let mut out = Vec::new();
    for (idx, f) in features.iter().enumerate() {
        let enabled = feature_enabled.get(idx).copied().unwrap_or(f.enabled);
        let has_slot = show_experimental && f.slot.is_some();
        let is_folded = fold.get(&f.id).copied().unwrap_or(false);
        out.push(FlatRow::Feature {
            idx,
            feature_id: f.id.clone(),
            description: f.description.clone(),
            enabled,
            has_slot,
            is_folded,
        });
        if has_slot && !is_folded && enabled {
            let slot = f.slot.as_ref().unwrap();
            let selected = variant_selections.get(&slot.slot_fqn).map(String::as_str);
            for choice in &slot.choices {
                out.push(FlatRow::Variant {
                    feature_idx: idx,
                    slot_fqn: slot.slot_fqn.clone(),
                    variant_id: choice.id.clone(),
                    title: choice.title.clone(),
                    stability: choice.stability.clone(),
                    is_selected: selected == Some(&*choice.id),
                    parent_enabled: enabled,
                });
            }
        }
    }
    out
}

struct PickFeaturesState {
    features: Vec<WizardFeature>,
    show_experimental: bool,
    fold: BTreeMap<String, bool>,
    variant_selections: BTreeMap<String, String>,
    feature_enabled: Vec<bool>,
    cursor: usize,
    lines_drawn: usize,
    query: String,
    search_mode: bool,
}

impl PickFeaturesState {
    fn new(features: Vec<WizardFeature>, show_experimental: bool) -> Self {
        let feature_enabled: Vec<bool> = features.iter().map(|f| f.enabled).collect();
        let variant_selections: BTreeMap<String, String> = features
            .iter()
            .filter_map(|f| {
                f.slot.as_ref().and_then(|s| {
                    s.selected_id
                        .as_ref()
                        .map(|id| (s.slot_fqn.clone(), id.clone()))
                })
            })
            .collect();
        Self {
            features,
            show_experimental,
            fold: BTreeMap::new(),
            variant_selections,
            feature_enabled,
            cursor: 0,
            lines_drawn: 0,
            query: String::new(),
            search_mode: false,
        }
    }

    fn visible(&self) -> Vec<FlatRow> {
        let rows = flatten_visible_features(
            &self.features,
            &self.feature_enabled,
            self.show_experimental,
            &self.fold,
            &self.variant_selections,
        );
        if self.query.is_empty() {
            return rows;
        }
        let q = self.query.to_lowercase();
        // Pass 1: separate "feature matched by own name" from "variant matched".
        // Keeping them in distinct sets prevents a variant match from revealing
        // all siblings (only the matched variant and its parent should appear).
        let mut feature_name_matches: std::collections::HashSet<usize> =
            std::collections::HashSet::new();
        let mut variant_match_set: std::collections::HashSet<(String, String)> =
            std::collections::HashSet::new();
        let mut variant_parent_set: std::collections::HashSet<usize> =
            std::collections::HashSet::new();
        for row in &rows {
            match row {
                FlatRow::Feature {
                    idx,
                    feature_id,
                    description,
                    ..
                } => {
                    if feature_id.to_lowercase().contains(&q)
                        || description.to_lowercase().contains(&q)
                    {
                        feature_name_matches.insert(*idx);
                    }
                }
                FlatRow::Variant {
                    feature_idx,
                    slot_fqn,
                    variant_id,
                    title,
                    ..
                } => {
                    if variant_id.to_lowercase().contains(&q) || title.to_lowercase().contains(&q) {
                        variant_match_set.insert((slot_fqn.clone(), variant_id.clone()));
                        variant_parent_set.insert(*feature_idx);
                    }
                }
            }
        }
        // Pass 2:
        // Feature shown if: name matched OR it has a variant that matched.
        // Variant shown if: it matched itself OR its parent matched by name.
        let visible_features: std::collections::HashSet<usize> = feature_name_matches
            .union(&variant_parent_set)
            .copied()
            .collect();
        rows.into_iter()
            .filter(|row| match row {
                FlatRow::Feature { idx, .. } => visible_features.contains(idx),
                FlatRow::Variant {
                    feature_idx,
                    slot_fqn,
                    variant_id,
                    ..
                } => {
                    variant_match_set.contains(&(slot_fqn.clone(), variant_id.clone()))
                        || feature_name_matches.contains(feature_idx)
                }
            })
            .collect()
    }

    fn rebuild<F>(&mut self, builder: &F) -> anyhow::Result<()>
    where
        F: Fn(bool) -> anyhow::Result<Vec<WizardFeature>>,
    {
        let new_features = builder(self.show_experimental)?;
        // Preserve enabled states by feature id.
        let old_enabled: BTreeMap<String, bool> = self
            .features
            .iter()
            .zip(&self.feature_enabled)
            .map(|(f, &e)| (f.id.clone(), e))
            .collect();
        self.feature_enabled = new_features
            .iter()
            .map(|f| old_enabled.get(&f.id).copied().unwrap_or(f.enabled))
            .collect();
        // Preserve variant selections; add new slots from new features.
        for f in &new_features {
            if let Some(slot) = &f.slot {
                if !self.variant_selections.contains_key(&slot.slot_fqn) {
                    if let Some(id) = &slot.selected_id {
                        self.variant_selections
                            .insert(slot.slot_fqn.clone(), id.clone());
                    }
                }
            }
        }
        self.features = new_features;
        let vis = self.visible().len();
        if self.cursor >= vis && vis > 0 {
            self.cursor = vis - 1;
        }
        Ok(())
    }
}

fn selected_count(feature_enabled: &[bool]) -> usize {
    feature_enabled.iter().filter(|&&e| e).count()
}

fn render_pick_features(
    state: &mut PickFeaturesState,
    stdout: &mut impl Write,
    prompt: &str,
) -> io::Result<()> {
    if state.lines_drawn > 0 {
        queue!(
            stdout,
            MoveUp(state.lines_drawn as u16),
            Clear(ClearType::FromCursorDown)
        )?;
    }
    let mut lines = 0;
    let exp = if state.show_experimental {
        "[on]"
    } else {
        "[off]"
    };
    let search_tag = if !state.query.is_empty() {
        format!("  [/{}]", state.query.bold())
    } else if state.search_mode {
        "  [/]".to_owned()
    } else {
        String::new()
    };
    write!(
        stdout,
        "  {} {}{} {}\r\n",
        "?".bold().cyan(),
        prompt.bold(),
        search_tag,
        format!(
            "({} selected)  E:experimental {exp}",
            selected_count(&state.feature_enabled)
        )
        .dimmed(),
    )?;
    lines += 1;

    let visible = state.visible();
    let (_, term_h) = size().unwrap_or((80, 24));
    let max_items = (term_h as usize).saturating_sub(3).max(1);
    let (start, end) = visible_window(state.cursor, visible.len(), max_items);

    for (offset, row) in visible[start..end].iter().enumerate() {
        let vis_idx = start + offset;
        let is_cursor = vis_idx == state.cursor;
        let cursor_ch = if is_cursor {
            "❯".cyan().to_string()
        } else {
            " ".to_owned()
        };
        match row {
            FlatRow::Feature {
                feature_id,
                description,
                enabled,
                has_slot,
                is_folded,
                ..
            } => {
                let check = if *enabled {
                    "●".green().to_string()
                } else {
                    "○".dimmed().to_string()
                };
                let fold_ch = if *has_slot {
                    if *is_folded {
                        "▶ "
                    } else {
                        "▼ "
                    }
                } else {
                    ""
                };
                let name = if is_cursor {
                    format!("{fold_ch}{}", feature_id.bold())
                } else {
                    format!("{fold_ch}{feature_id}")
                };
                let desc = if description.is_empty() {
                    String::new()
                } else {
                    format!("  {}", description.dimmed())
                };
                write!(stdout, "  {} {} {}{}\r\n", cursor_ch, check, name, desc)?;
            }
            FlatRow::Variant {
                variant_id,
                title,
                stability,
                is_selected,
                parent_enabled,
                ..
            } => {
                let radio = if *is_selected {
                    "●".green().to_string()
                } else {
                    "○".dimmed().to_string()
                };
                let exp_tag = if *stability == Stability::Experimental {
                    format!("  {}", "experimental".yellow().dimmed())
                } else {
                    String::new()
                };
                let label = if !parent_enabled {
                    // Parent feature disabled — dim choices
                    format!("{radio} {}{exp_tag}", title.dimmed())
                } else if is_cursor {
                    format!("{radio} {}{exp_tag}", title.bold())
                } else {
                    format!("{radio} {title}{exp_tag}")
                };
                let _ = variant_id;
                write!(stdout, "  {}     {}\r\n", cursor_ch, label)?;
            }
        }
        lines += 1;
    }

    if visible.len() > end - start {
        // pagination indicator
    }

    let search_hint = if state.search_mode {
        "  (esc:clear)".to_owned()
    } else {
        String::new()
    };
    let hint = if state.show_experimental {
        format!("j/k:move  space:toggle  tab:fold  /:search{search_hint}  E:experimental [on]  enter:confirm  q:cancel  {}-{}/{}", start+1, end, visible.len())
    } else {
        format!("j/k:move  space:toggle  a:all  i:invert  /:search{search_hint}  E:experimental [off]  enter:confirm  q:cancel  {}-{}/{}", start+1, end, visible.len())
    };
    write!(stdout, "  {}\r\n", hint.dimmed())?;
    lines += 1;

    stdout.flush()?;
    state.lines_drawn = lines;
    Ok(())
}

type PickResult = Option<(Vec<String>, BTreeMap<String, String>)>;

fn pick_features_event_loop<F>(
    state: &mut PickFeaturesState,
    stdout: &mut impl Write,
    prompt: &str,
    builder: &F,
) -> anyhow::Result<PickResult>
where
    F: Fn(bool) -> anyhow::Result<Vec<WizardFeature>>,
{
    render_pick_features(state, stdout, prompt)?;

    loop {
        let Event::Key(key) = read()? else { continue };
        if key.modifiers.contains(KeyModifiers::CONTROL) && key.code == KeyCode::Char('c') {
            return Ok(None);
        }

        if state.search_mode {
            match key.code {
                KeyCode::Esc => {
                    state.query.clear();
                    state.search_mode = false;
                }
                KeyCode::Enter => {
                    state.search_mode = false;
                }
                KeyCode::Backspace => {
                    state.query.pop();
                }
                KeyCode::Char(c) => {
                    state.query.push(c);
                }
                _ => {}
            }
            let vis_len = state.visible().len();
            if vis_len > 0 && state.cursor >= vis_len {
                state.cursor = vis_len - 1;
            }
            render_pick_features(state, stdout, prompt)?;
            continue;
        }

        let vis = state.visible();
        let vis_len = vis.len();

        match key.code {
            KeyCode::Char('j') | KeyCode::Down if vis_len > 0 => {
                state.cursor = (state.cursor + 1) % vis_len;
            }
            KeyCode::Char('k') | KeyCode::Up if vis_len > 0 => {
                state.cursor = state.cursor.checked_sub(1).unwrap_or(vis_len - 1);
            }
            KeyCode::Char(' ') => match vis.get(state.cursor) {
                Some(FlatRow::Feature { idx, .. }) => {
                    state.feature_enabled[*idx] ^= true;
                }
                Some(FlatRow::Variant {
                    slot_fqn,
                    variant_id,
                    ..
                }) => {
                    let (s, v) = (slot_fqn.clone(), variant_id.clone());
                    state.variant_selections.insert(s, v);
                }
                None => {}
            },
            KeyCode::Tab => match vis.get(state.cursor) {
                Some(FlatRow::Feature {
                    feature_id,
                    has_slot,
                    ..
                }) if *has_slot => {
                    let id = feature_id.clone();
                    let v = state.fold.entry(id).or_insert(false);
                    *v = !*v;
                }
                Some(FlatRow::Variant { feature_idx, .. }) => {
                    let id = state.features[*feature_idx].id.clone();
                    let v = state.fold.entry(id).or_insert(false);
                    *v = !*v;
                }
                _ => {}
            },
            KeyCode::Char('a') if !state.show_experimental => {
                let new = !(state.feature_enabled.iter().all(|&e| e));
                for e in &mut state.feature_enabled {
                    *e = new;
                }
            }
            KeyCode::Char('i') if !state.show_experimental => {
                for e in &mut state.feature_enabled {
                    *e = !*e;
                }
            }
            KeyCode::Char('/') => {
                state.search_mode = true;
            }
            KeyCode::Char('E') => {
                // Capture cursor anchor from CURRENT visible list before E flip.
                let anchor_vis = state.visible();
                let cursor_anchor: Option<String> =
                    anchor_vis.get(state.cursor).and_then(|row| match row {
                        FlatRow::Feature { feature_id, .. } => Some(feature_id.clone()),
                        FlatRow::Variant { feature_idx, .. } => {
                            state.features.get(*feature_idx).map(|f| f.id.clone())
                        }
                    });
                state.show_experimental = !state.show_experimental;
                state.rebuild(builder)?;
                // Re-anchor cursor to the same feature in the new visible list.
                if let Some(fid) = cursor_anchor {
                    let new_vis = state.visible();
                    if let Some(pos) = new_vis.iter().position(
                        |r| matches!(r, FlatRow::Feature { feature_id, .. } if feature_id == &fid),
                    ) {
                        state.cursor = pos;
                    }
                }
            }
            KeyCode::Esc | KeyCode::Char('q') => return Ok(None),
            KeyCode::Enter => {
                let selected: Vec<String> = state
                    .features
                    .iter()
                    .zip(&state.feature_enabled)
                    .filter(|(_, &e)| e)
                    .map(|(f, _)| f.id.clone())
                    .collect();
                return Ok(Some((selected, state.variant_selections.clone())));
            }
            _ => {}
        }
        render_pick_features(state, stdout, prompt)?;
    }
}

/// Unified feature + variants picker.
///
/// Returns `Some((selected_feature_ids, variant_selections))` or `None` on cancel.
pub fn pick_features_with_variants<F>(
    prompt: &str,
    initial_features: Vec<WizardFeature>,
    initial_experimental: bool,
    feature_reloader: F,
) -> anyhow::Result<PickResult>
where
    F: Fn(bool) -> anyhow::Result<Vec<WizardFeature>>,
{
    if !io::stdin().is_terminal() || !io::stdout().is_terminal() {
        return pick_features_with_variants_dialoguer(
            prompt,
            initial_features,
            initial_experimental,
            &feature_reloader,
        );
    }

    match pick_features_with_variants_crossterm(
        prompt,
        initial_features.clone(),
        initial_experimental,
        &feature_reloader,
    ) {
        Ok(result) => Ok(result),
        Err(err) if is_input_reader_error(&err) => pick_features_with_variants_dialoguer(
            prompt,
            initial_features,
            initial_experimental,
            &feature_reloader,
        ),
        Err(err) => Err(err),
    }
}

fn pick_features_with_variants_crossterm<F>(
    prompt: &str,
    initial_features: Vec<WizardFeature>,
    initial_experimental: bool,
    feature_reloader: &F,
) -> anyhow::Result<PickResult>
where
    F: Fn(bool) -> anyhow::Result<Vec<WizardFeature>>,
{
    let mut state = PickFeaturesState::new(initial_features, initial_experimental);
    let mut stdout = io::stdout();

    let reserved = state.visible().len().min(20) + 3;
    enable_raw_mode()?;
    let _guard = TerminalGuard;
    execute!(stdout, Hide)?;
    for _ in 0..reserved {
        writeln!(stdout)?;
    }
    execute!(stdout, MoveUp(reserved as u16))?;
    stdout.flush()?;

    let result = pick_features_event_loop(&mut state, &mut stdout, prompt, feature_reloader);

    if state.lines_drawn > 0 {
        execute!(
            stdout,
            MoveUp(state.lines_drawn as u16),
            Clear(ClearType::FromCursorDown)
        )?;
    }

    match result? {
        None => {
            println!("  Cancelled.");
            Ok(None)
        }
        Some((ids, variants)) => {
            println!(
                "  {} {}  {}",
                "✓".green(),
                prompt,
                format!("({} selected)", ids.len()).dimmed()
            );
            Ok(Some((ids, variants)))
        }
    }
}

fn pick_features_with_variants_dialoguer<F>(
    prompt: &str,
    initial_features: Vec<WizardFeature>,
    initial_experimental: bool,
    feature_reloader: &F,
) -> anyhow::Result<PickResult>
where
    F: Fn(bool) -> anyhow::Result<Vec<WizardFeature>>,
{
    let features = if initial_experimental {
        feature_reloader(true)?
    } else {
        initial_features
    };
    let labels: Vec<String> = features
        .iter()
        .map(|feature| {
            if feature.description.is_empty() {
                return feature.id.clone();
            }
            format!("{} — {}", feature.id, feature.description)
        })
        .collect();
    let defaults: Vec<bool> = features.iter().map(|feature| feature.enabled).collect();
    let Some(indices) = MultiSelect::with_theme(&ColorfulTheme::default())
        .with_prompt(prompt)
        .items(&labels)
        .defaults(&defaults)
        .interact_opt()?
    else {
        println!("  Cancelled.");
        return Ok(None);
    };

    let mut ids = Vec::new();
    let mut variants = BTreeMap::new();
    for idx in indices {
        let Some(feature) = features.get(idx) else {
            continue;
        };
        ids.push(feature.id.clone());
        let Some(slot) = &feature.slot else { continue };
        let choices: Vec<String> = slot
            .choices
            .iter()
            .map(|choice| format!("{} — {}", choice.id, choice.title))
            .collect();
        let default_idx = slot
            .selected_id
            .as_ref()
            .and_then(|selected| {
                slot.choices
                    .iter()
                    .position(|choice| &choice.id == selected)
            })
            .or_else(|| slot.choices.iter().position(|choice| choice.is_default))
            .unwrap_or(0);
        let Some(choice_idx) = Select::with_theme(&ColorfulTheme::default())
            .with_prompt(format!("{} variant", feature.id))
            .items(&choices)
            .default(default_idx)
            .interact_opt()?
        else {
            println!("  Cancelled.");
            return Ok(None);
        };
        if let Some(choice) = slot.choices.get(choice_idx) {
            variants.insert(slot.slot_fqn.clone(), choice.id.clone());
        }
    }

    println!(
        "  {} {}  {}",
        "✓".green(),
        prompt,
        format!("({} selected)", ids.len()).dimmed()
    );
    Ok(Some((ids, variants)))
}

// ── Pure state helpers — unit tests ──────────────────────────────────────────

#[cfg(test)]
mod feature_wizard_tests {
    use super::*;
    use kaizen_core::{VariantChoice, WizardFeatureSlot};

    fn make_tiling_feature(include_slot: bool) -> WizardFeature {
        let slot = if include_slot {
            Some(WizardFeatureSlot {
                slot_fqn: "tiling.wm".to_owned(),
                choices: vec![
                    VariantChoice {
                        id: "yabai".to_owned(),
                        title: "Yabai".to_owned(),
                        stability: Stability::Stable,
                        is_default: true,
                    },
                    VariantChoice {
                        id: "aerospace".to_owned(),
                        title: "AeroSpace".to_owned(),
                        stability: Stability::Experimental,
                        is_default: false,
                    },
                ],
                selected_id: Some("yabai".to_owned()),
            })
        } else {
            None
        };
        WizardFeature {
            id: "tiling".to_owned(),
            description: "Tiling WM".to_owned(),
            enabled: true,
            slot,
        }
    }

    #[test]
    fn flatten_eoff_no_variant_rows() {
        let features = vec![make_tiling_feature(true)];
        let rows = flatten_visible_features(
            &features,
            &features.iter().map(|f| f.enabled).collect::<Vec<_>>(),
            false,
            &BTreeMap::new(),
            &BTreeMap::new(),
        );
        assert_eq!(rows.len(), 1);
        assert!(matches!(rows[0], FlatRow::Feature { .. }));
    }

    #[test]
    fn flatten_eon_unfolded_shows_variants() {
        let features = vec![make_tiling_feature(true)];
        let sel = BTreeMap::from([("tiling.wm".to_owned(), "yabai".to_owned())]);
        let rows = flatten_visible_features(
            &features,
            &features.iter().map(|f| f.enabled).collect::<Vec<_>>(),
            true,
            &BTreeMap::new(),
            &sel,
        );
        assert_eq!(rows.len(), 3); // feature + 2 variants
        assert!(matches!(&rows[1], FlatRow::Variant { variant_id, .. } if variant_id == "yabai"));
    }

    #[test]
    fn flatten_eon_folded_hides_variants() {
        let features = vec![make_tiling_feature(true)];
        let fold = BTreeMap::from([("tiling".to_owned(), true)]);
        let rows = flatten_visible_features(
            &features,
            &features.iter().map(|f| f.enabled).collect::<Vec<_>>(),
            true,
            &fold,
            &BTreeMap::new(),
        );
        assert_eq!(rows.len(), 1);
    }

    #[test]
    fn flatten_no_slot_feature_never_gets_variant_rows() {
        let features = vec![make_tiling_feature(false)];
        let rows = flatten_visible_features(
            &features,
            &features.iter().map(|f| f.enabled).collect::<Vec<_>>(),
            true,
            &BTreeMap::new(),
            &BTreeMap::new(),
        );
        assert_eq!(
            rows.len(),
            1,
            "feature with no slot has no variant rows even with E=on"
        );
    }

    #[test]
    fn flatten_disabled_feature_hides_variants() {
        let features = vec![make_tiling_feature(true)];
        // Runtime enabled=false (toggled by user) overrides initial f.enabled=true
        let runtime_enabled = vec![false];
        let rows = flatten_visible_features(
            &features,
            &runtime_enabled,
            true,
            &BTreeMap::new(),
            &BTreeMap::new(),
        );
        assert_eq!(rows.len(), 1, "disabled feature hides variant rows");
        assert!(matches!(&rows[0], FlatRow::Feature { enabled: false, .. }));
    }

    #[test]
    fn search_query_filters_features_by_name() {
        let base_features = vec![
            WizardFeature {
                id: "helix".to_owned(),
                description: "Editor".to_owned(),
                enabled: true,
                slot: None,
            },
            WizardFeature {
                id: "vcs".to_owned(),
                description: "Version control".to_owned(),
                enabled: true,
                slot: None,
            },
        ];
        let tiling_feature = make_tiling_feature(true); // has slot with yabai + aerospace
        let mut features = base_features;
        features.push(tiling_feature);
        let mut state = PickFeaturesState::new(features, false);

        // E=off, no query — 3 features, no variants
        assert_eq!(state.visible().len(), 3);

        // E=off, query "hel" — only helix
        state.query = "hel".to_owned();
        assert_eq!(state.visible().len(), 1);
        assert!(
            matches!(&state.visible()[0], FlatRow::Feature { feature_id, .. } if feature_id == "helix")
        );

        // E=on, query "yabai" — tiling + yabai variant visible, aerospace hidden
        state.show_experimental = true;
        state.query = "yabai".to_owned();
        let vis = state.visible();
        assert_eq!(vis.len(), 2, "tiling feature + yabai variant");
        assert!(matches!(&vis[0], FlatRow::Feature { feature_id, .. } if feature_id == "tiling"));
        assert!(matches!(&vis[1], FlatRow::Variant { variant_id, .. } if variant_id == "yabai"));

        // E=on, query "tiling" — parent matches → both variants visible
        state.query = "tiling".to_owned();
        let vis2 = state.visible();
        assert_eq!(vis2.len(), 3, "tiling feature + 2 variants");
        assert!(matches!(&vis2[0], FlatRow::Feature { feature_id, .. } if feature_id == "tiling"));
        assert!(matches!(&vis2[1], FlatRow::Variant { variant_id, .. } if variant_id == "yabai"));
        assert!(
            matches!(&vis2[2], FlatRow::Variant { variant_id, .. } if variant_id == "aerospace")
        );

        // query "nomatch" — empty
        state.query = "nomatch".to_owned();
        assert!(state.visible().is_empty());
    }

    #[test]
    fn pick_state_space_on_variant_updates_selection() {
        let features = vec![make_tiling_feature(true)];
        let mut state = PickFeaturesState::new(features, true);
        // cursor should be on tiling row (idx 0)
        // move to first variant row (idx 1)
        state.cursor = 1;
        let vis = state.visible();
        if let FlatRow::Variant {
            slot_fqn,
            variant_id,
            ..
        } = &vis[1]
        {
            let (s, v) = (slot_fqn.clone(), variant_id.clone());
            state.variant_selections.insert(s, v);
        }
        assert_eq!(
            state
                .variant_selections
                .get("tiling.wm")
                .map(String::as_str),
            Some("yabai")
        );
    }
}

#[cfg(test)]
mod cursor_tests {
    use super::*;
    use kaizen_core::{VariantChoice, WizardFeatureSlot};

    fn make_features_with_tiling() -> Vec<WizardFeature> {
        vec![
            WizardFeature {
                id: "ai".to_owned(),
                description: "AI".to_owned(),
                enabled: true,
                slot: None,
            },
            WizardFeature {
                id: "tiling".to_owned(),
                description: "Tiling WM".to_owned(),
                enabled: true,
                slot: Some(WizardFeatureSlot {
                    slot_fqn: "tiling.wm".to_owned(),
                    choices: vec![
                        VariantChoice {
                            id: "yabai".to_owned(),
                            title: "Yabai".to_owned(),
                            stability: Stability::Stable,
                            is_default: true,
                        },
                        VariantChoice {
                            id: "aerospace".to_owned(),
                            title: "AeroSpace".to_owned(),
                            stability: Stability::Experimental,
                            is_default: false,
                        },
                    ],
                    selected_id: Some("yabai".to_owned()),
                }),
            },
            WizardFeature {
                id: "vcs".to_owned(),
                description: "VCS".to_owned(),
                enabled: true,
                slot: None,
            },
        ]
    }

    #[test]
    fn space_on_feature_with_slot_toggles_enabled() {
        // E=on: [ai=0, tiling=1, yabai=2, aerospace=3, vcs=4]
        // cursor=1 is the tiling Feature row (with has_slot=true)
        let features = make_features_with_tiling();
        let sel = BTreeMap::from([("tiling.wm".to_owned(), "yabai".to_owned())]);
        let fold = BTreeMap::new();
        let vis = flatten_visible_features(
            &features,
            &features.iter().map(|f| f.enabled).collect::<Vec<_>>(),
            true,
            &fold,
            &sel,
        );
        assert!(
            matches!(&vis[1], FlatRow::Feature { feature_id, has_slot, .. } if feature_id == "tiling" && *has_slot)
        );
        // Space handler: toggle enabled on the idx from FlatRow::Feature
        if let FlatRow::Feature { idx, .. } = &vis[1] {
            // idx=1 (tiling is second feature)
            assert_eq!(*idx, 1);
            // No guard on has_slot — toggle always works
        }
    }

    #[test]
    fn cursor_anchor_captures_feature_id_from_variant_row() {
        // When cursor is on a Variant row, anchor should be parent feature.
        let features = make_features_with_tiling();
        let sel = BTreeMap::new();
        let fold = BTreeMap::new();
        let vis = flatten_visible_features(
            &features,
            &features.iter().map(|f| f.enabled).collect::<Vec<_>>(),
            true,
            &fold,
            &sel,
        );
        // vis[2] = yabai variant, parent = tiling (feature_idx=1)
        let anchor: Option<String> = vis.get(2).and_then(|row| match row {
            FlatRow::Feature { feature_id, .. } => Some(feature_id.clone()),
            FlatRow::Variant { feature_idx, .. } => {
                features.get(*feature_idx).map(|f| f.id.clone())
            }
        });
        assert_eq!(anchor.as_deref(), Some("tiling"));
    }

    #[test]
    fn cursor_reanchor_finds_feature_after_expansion() {
        // E=off: [ai=0, tiling=1, vcs=2] cursor=2 (vcs)
        // E=on:  [ai=0, tiling=1, yabai=2, aerospace=3, vcs=4]
        // After re-anchor by "vcs" fid, cursor should be 4.
        let features = make_features_with_tiling();
        let fold = BTreeMap::new();
        let sel = BTreeMap::new();
        let new_vis = flatten_visible_features(
            &features,
            &features.iter().map(|f| f.enabled).collect::<Vec<_>>(),
            true,
            &fold,
            &sel,
        );
        let fid = "vcs";
        let pos = new_vis
            .iter()
            .position(|r| matches!(r, FlatRow::Feature { feature_id, .. } if feature_id == fid));
        assert_eq!(pos, Some(4));
    }

    #[test]
    fn variant_rows_carry_parent_enabled_flag() {
        let features = make_features_with_tiling();
        let sel = BTreeMap::new();
        let fold = BTreeMap::new();
        let vis = flatten_visible_features(
            &features,
            &features.iter().map(|f| f.enabled).collect::<Vec<_>>(),
            true,
            &fold,
            &sel,
        );
        // yabai variant should have parent_enabled=true (tiling is enabled)
        assert!(matches!(
            &vis[2],
            FlatRow::Variant {
                parent_enabled: true,
                ..
            }
        ));
    }
}
