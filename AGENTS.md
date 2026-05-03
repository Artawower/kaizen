# About project

Kaizen is a developer's Swiss Army knife for workflow optimization. It curates the gold standard of software, configurations, and shortcuts driven by objective metrics. By providing battle-tested dotfiles for diverse use cases, Kaizen eliminates choice fatigue and lets you focus on building.


# External deps
- https://github.com/ripytide/metapac - package manager worked between diffent OS
- https://www.chezmoi.io/ - dot filex generator
- https://github.com/Artawower/dotfiles - my dotfiles (we will use most ot the features from there, but we will rewrite them in a more modular way, and we will add some new features as well)


# Core rules
- Avoid comments. Code should be self-explanatory. If you find yourself writing a comment, consider refactoring the code to make it clearer instead.
- Avoid `else` statements. Use guard clauses and early returns to simplify control flow and reduce nesting.
- use `SOLID` principles where applicable, but do not over-engineer. The simplest solution that works is usually best.
- Follow the DRY (Don't Repeat Yourself) principle. If you find yourself copying and pasting code, consider extracting it into a reusable function or module.

