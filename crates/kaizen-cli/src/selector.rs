use std::io::{self, Write};

use anyhow::Result;
use crossterm::{
    cursor::{Hide, MoveUp, Show},
    event::{read, Event, KeyCode, KeyModifiers},
    execute, queue,
    terminal::{disable_raw_mode, enable_raw_mode, Clear, ClearType},
};
use owo_colors::OwoColorize;

struct TerminalGuard;

impl Drop for TerminalGuard {
    fn drop(&mut self) {
        let _ = disable_raw_mode();
        let _ = execute!(io::stdout(), Show);
    }
}

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

fn render(state: &mut State, stdout: &mut impl Write, prompt: &str) -> io::Result<()> {
    if state.lines_drawn > 0 {
        queue!(
            stdout,
            MoveUp(state.lines_drawn as u16),
            Clear(ClearType::FromCursorDown)
        )?;
    }

    let visible = state.visible();
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

    for (vis_idx, &item_idx) in visible.iter().enumerate() {
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
        "esc=clear  enter=apply filter"
    } else {
        "j/k:move  space:toggle  a:all  i:invert  /:search  enter:confirm"
    };
    write!(stdout, "  {}\r\n", hint.dimmed())?;
    lines += 1;

    stdout.flush()?;
    state.lines_drawn = lines;
    Ok(())
}

fn event_loop(
    state: &mut State,
    stdout: &mut impl Write,
    prompt: &str,
) -> Result<Option<Vec<String>>> {
    render(state, stdout, prompt)?;
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
        render(state, stdout, prompt)?;
    }
}

pub fn multi_select(prompt: &str, items: Vec<Item>) -> Result<Option<Vec<String>>> {
    let mut state = State::new(items);
    let mut stdout = io::stdout();

    enable_raw_mode()?;
    let _guard = TerminalGuard;
    execute!(stdout, Hide)?;

    let result = event_loop(&mut state, &mut stdout, prompt);

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
