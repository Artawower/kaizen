# TODO

## Now


## Next

- [ ] **Нам нужно обьеденить одинковые названия зависимостей..**
  - Посмотри сам: brew = ["ripgrep", "fd", "fzf", "jq", "tree", "htop", "ncdu", "sqlite", "just", "mise", "mole", "pandoc", "wget", "dtach", "dash", "kondo", "scc"]
  - dnf = ["ripgrep", "fd-find", "fzf", "jq", "tree", "htop", "ncdu", "sqlite", "just", "pandoc", "wget", "dash", "kondo"]
  - apt = ["ripgrep", "fd-find", "fzf", "jq", "tree", "htop", "ncdu", "sqlite", "pandoc", "wget", "dash", "kondo"]
  - половину можно задекларировать в похожих местах.. и только если есть разница, отдельно... правда нужно как-то убедиться что при установке нет конфликтов.. например если общий модуль fd-find.. в другом месте fd.. что если 2 мето попробует поставить не тот модуль? 🤔 как-то нужно определить это
- [ ] **Task per time PI agent.** — Is it possible to show how much time/tokens were consumed by one session? When agent stoped working in PI?

## Later


## Archive

- [x] **Emacs, Helixel, search next** — Сейчас n ищет вперед.. N не ищет назад.. потому что меняется direcation, но после его изменения n ищет вперед.. это ошибка.. нужно перед тем как исправлять придумать как управлять этим
- [x] **Skills inventory**
  - Нам нужно добавить в toml желаемые устанавливаемые skills!
  - dietrichgebert/ponytail@ponytail
  - например, при инициализации системы нужно чтобы они ставились через skills когда он доступен
