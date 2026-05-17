# Variants research

## Summary

- Repeats across the strongest systems: a small declarative core, plus many tiny host-specific adapters that merge into one result. Home Manager, flake-parts/devenv, and system-manager all lean this way.
- The best cross-cutting themers (Stylix, Catppuccin/Base16) separate the source of truth from per-app ports. That scales better than hand-wired file trees, but it pushes complexity into autoloading and target gating.
- “One of N” is usually modelled as either explicit flags/targets or package-style variant selection. The systems that stay readable keep the choice close to the thing being rendered.

## 1. Home Manager

- Base unit: modules with options that merge into one configuration; the user-facing shape is usually programs.X.enable plus extra config and activation hooks. Docs: [Home Manager manual](https://home-manager.dev/manual/unstable/).
- Direction: host owns the configuration tree; guest modules contribute their own options, files, and services. It already has host-to-guest plumbing via osConfig and shared module args.
- Gating: ordinary booleans and platform checks, not a first-class variant system.
- Weak spot: conditional module composition is a known pain point; recursion and merge ordering show up in issues/discussion threads.

## 2. Stylix

- Base unit: a target module per app/platform, auto-loaded from a naming convention. Docs: [Adding modules](https://nix-community.github.io/stylix/modules.html), [Home Manager options](https://nix-community.github.io/stylix/options/platforms/home_manager.html).
- Direction: central theme state drives many app-specific targets. Guests do not “discover” the host; the host config enables targets and each target renders itself from shared colors.
- Gating: stylix.enable, per-target enable flags, auto-enable defaults, and release checks.
- Weak spot: the autoload / mkTarget split is powerful but easy to misuse; manual imports lose the safety rails.

## 3. Doom Emacs

- Base unit: module bundles, each grouping packages, config, and commands. Docs: [modules guide](https://github.com/doomemacs/doomemacs/blob/f2257c3f/docs/modules.org), [documentation](https://docs.doomemacs.org/latest/).
- Direction: the user’s doom! block selects modules; modules then contribute packages and keybindings to the editor host.
- Gating: module flags and submodule categories; no native “variant” concept.
- Weak spot: load order bugs are common enough to have recurring issues around broken keybindings and sync/upgrade regressions.

## 4. Spacemacs

- Base unit: layers. Each layer owns packages.el, funcs.el, config.el, and keybindings.el. Docs: [layers guide](https://develop.spacemacs.org/doc/LAYERS.html).
- Direction: layers are stacked onto the editor host; dependencies can pull other layers in and override package ownership.
- Gating: layer selection plus layer dependencies; still not a formal variant model.
- Weak spot: dependencies can mask explicit user choices, and the loading process is famously intricate.

## 5. Gentoo Portage USE flags

- Base unit: per-package compile-time flags. Docs: [USE flags](https://devmanual.gentoo.org/general-concepts/use-flags/index.html), [eclasses / EAPI](https://devmanual.gentoo.org/ebuild-writing/eapi/index.html).
- Direction: package metadata declares optional capabilities; the system/profile/user can force or mask them.
- Gating: USE flags, stable.force/mask, package.use, keywords, and profile-level policy.
- Weak spot: flag explosion and combinatorial maintenance are the classic complaint; it scales technically, but not always cognitively.

## 6. devenv / flake-parts

- Base unit: imported Nix modules inside a flake. Docs: [flake-parts](https://flake.parts/), [devenv with flake-parts](https://devenv.sh/guides/using-with-flake-parts/).
- Direction: host flake defines the composition surface; reusable modules and inputs are imported into it.
- Gating: regular module options and per-system outputs; no dedicated experimental layer.
- Weak spot: indirection grows quickly, but the pattern is much cleaner than ad-hoc flake glue.

## 7. system-manager

- Base unit: NixOS-style modules for non-NixOS Linux. Docs: [system-manager README](https://github.com/numtide/system-manager) and [reference docs](https://system-manager.net/main/).
- Direction: host-level system config owns packages, services, and root-managed files; modules are consumed by the system config.
- Gating: module options and declarative imports, similar to NixOS/Home Manager.
- Weak spot: it stays Linux-specific and still inherits the Nix module learning curve.

## 8. chezmoi

- Base unit: source state plus special directories and special files. Docs: [.chezmoiroot](https://chezmoi.io/reference/special-files/chezmoiroot/), [special directories](https://chezmoi.io/reference/special-directories/).
- Direction: the source tree is the host; rendered files are the guest emission. The model is file-centric, not semantic-module-centric.
- Gating: templates, special dirs, and source-root indirection; not a native host/guest contribution graph.
- Weak spot: excellent for deployment, weak for richer composition between features that want to contribute to the same root.

## 9. Catppuccin / Base16

- Base unit: a palette spec plus per-app ports. Docs: [Catppuccin ports](https://catppuccin.com/ports/), [port creation](https://github.com/catppuccin/catppuccin/blob/main/docs/port-creation.md), [Base16](https://github.com/chriskempson/base16/blob/main/README.md).
- Direction: one central theme identity, many distributed port repos.
- Gating: per-port enablement and contribution guidelines rather than a runtime variant selector.
- Weak spot: consistency is good, but port maintenance is dispersed and submission overhead is real.

## 10. Kustomize / LazyVim (optional extras)

- Kustomize: bases and overlays, with patches applied on top. Docs: [bases and overlays](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/), [patches](https://kubectl.docs.kubernetes.io/references/kustomize/kustomization/patches).
- LazyVim / lazy.nvim: plugin specs with enabled, dependencies, cond, and opts; config is composed from many small plugin files. Docs: [lazy.nvim spec](https://lazy.folke.io/spec), [LazyVim plugins](https://lazyvim.github.io/configuration/plugins).
- Direction: both are “host owns the base, guests overlay / extend it”, but they are still file/spec driven rather than a semantic variant registry.
- Weak spot: overlays tend to duplicate, and plugin override layers add complexity once the defaults stop being enough.

## Mapping to kaizen

| Our question                 | Closest analogue                          | What to take                                     | What not to take                           |
| ---------------------------- | ----------------------------------------- | ------------------------------------------------ | ------------------------------------------ |
| Feature / module composition | Home Manager, flake-parts, system-manager | Declarative modules that merge into one result   | Recursion-prone conditional imports        |
| Host vs guest features       | Stylix                                    | Host-owned targets with guest-specific renderers | Letting guests infer host state implicitly |
| Alternatives / variants      | Gentoo USE flags, Stylix targets          | Explicit per-target selection and defaulting     | Flag explosion and global masking rules    |
| Experimental gating          | Stylix auto-enable + Gentoo stable masks  | Opt-in defaults with release/stability flags     | Ad-hoc “experimental folder” splits        |
| Cross-cutting data           | Stylix, Catppuccin/Base16                 | One source of truth, many render ports           | Copying the same data into every consumer  |

## Antipatterns

- Recursive / conditional module trees that depend on config while defining imports. Seen in Home Manager discussions and Stylix autoload debates: [HM recursion pain](https://github.com/nix-community/home-manager/issues/1906), [Stylix mkTarget recursion](https://github.com/danth/stylix/pull/1130).
- Load-order coupling in editor module systems. Doom and Spacemacs both have recurring issues where ordering or ownership breaks keybindings: [Doom issue](https://github.com/doomemacs/doomemacs/issues/8712), [Spacemacs loading guide](https://github.com/syl20bnr/spacemacs/wiki/Loading-process-guide).
- Variant or overlay duplication. Kustomize is the clearest example of repeated complaints about copying base content across overlays: [Kustomize composition issue](https://github.com/kubernetes-sigs/kustomize/issues/1251), [overlay duplication issue](https://github.com/kubernetes-sigs/kustomize/issues/3014).
- Flag sprawl. Gentoo’s power is real, but the community’s long-running complaint is that USE flags are easy to overgrow: [Gentoo forum thread](https://forums.gentoo.org/viewtopic.php?t=832290), [blog criticism](https://coldattic.info/post/105/).
- Override fatigue in plugin-composition ecosystems. LazyVim users repeatedly ask for stronger override ergonomics once defaults stop matching their setup: [LazyVim discussion](https://github.com/LazyVim/LazyVim/discussions/22).
