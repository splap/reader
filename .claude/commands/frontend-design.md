---
name: frontend-design
description: iOS-native design guidance. Use when improving UI/UX. Goal is invisible design that feels like part of the operating system.
---

# iOS-Native Design Philosophy

The goal is **invisible design** - UI so aligned with iOS conventions that users forget it's not part of the operating system. No brand identity, no distinctive flair. Just native.

## Reference Apps

- **iMessage** - Primary reference for chat UI
- **Apple Books** - Reference for reader and library
- **Settings app** - Reference for forms and lists
- **Files app** - Reference for document management

## Context-Specific Guidelines

**Library View**: 100% iOS system default. Collection views, navigation bars, search - all standard UIKit patterns.

**Reader View**: Mostly iOS default. Clean, distraction-free reading. Standard controls when they appear.

**Chat View**: iMessage-like. Blue bubbles for user, gray for assistant. Standard iOS keyboard handling, input fields.

## Principles

1. **Use system components** - UIKit defaults over custom implementations
2. **Respect platform conventions** - Navigation patterns, gestures, spacing from HIG
3. **System colors** - `.systemBackground`, `.label`, `.secondaryLabel`, `.systemBlue`
4. **System fonts** - SF Pro via `.preferredFont(forTextStyle:)` with Dynamic Type support
5. **Standard spacing** - 16pt margins, 8pt increments
6. **No custom flourishes** - No gradients, shadows, or decorative elements unless iOS does it

## When Reviewing UI

Ask:
- Does this look like it could ship in an Apple app?
- Would a user notice this isn't a system screen?
- Am I adding anything that iOS doesn't do?

If the answer to the last question is "yes" - remove it unless there's a strong functional reason.
