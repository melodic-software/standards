# Visual design

## Design

- Choose typography, emphasis and separators in text people read from legibility and comprehension research, not taste. For example, use italics instead of nested parentheses.

## Design and build

- Decoration must never get in the way of reading. Keep motion minimal, put enough background behind text, and prefer realistic over cartoony. A customization must be useful, not ornament. Ambient visuals and sound barely change and default to the option easiest to live with permanently.
- Hover states never move content: use tooltips and a color shift instead. Every interactive animation runs at a smooth 60 frames per second. Tool chrome around a presented design, such as a flyout overlay, never alters the design.
- Follow the system light or dark color-scheme preference by default, and generate HTML output from one shared, rebrandable default template that honors it.
- Ground visual and audio assets in real-world sources: prefer authentic recorded assets over synthesized ones, shipped as a curated set with a default the user can change. Replicate the reference one-to-one before customizing it, build creative work step by step from storyboards, a style guide and a palette, and never lose fidelity in a change.

## Design and review

- Layout rules:
  - No forced or horizontal scrolling, and no scrollbars inside scrollbars.
  - Overflow stays inside its container, and truncated text can be read in full by hover or expansion.
  - Explain any color coding.
  - Use collapsibles and even-height panels.
  - Check each view and each input on small screens and mobile.
  - Do pixel-level cleanup passes on alignment and centering.
- For UI work, use the available design and brand guidance and prototype several directions the decider can explore. Preview the change in the real app before committing. Start interface and motion design from Emil Kowalski's published design skills ([emilkowalski/skills](https://github.com/emilkowalski/skills)).
