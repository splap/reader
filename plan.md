# Plan: Fix Snapback Jank in Mid-Chapter Page Navigation

## What's In Flight (branch `reader1`)

Page navigation refactor — completed and all tests passing:
- `PageNavigationResolver.swift` — pure decision function for page turns
- `SpineTransitionAnimator.swift` — contiguous slide animation for spine transitions (starts immediately, loads content in parallel)
- `WebPageViewController.swift` — simplified scroll delegate using resolver; deceleration killed before animator starts
- `PageNavigationResolverTests.swift` — 27 unit tests (all passing)
- All existing UI tests passing (`testSpineBoundaryNavigation`, `testSimpleSpineCrossing`, `testFrankensteinFirstSpineToSecond`)
- Removed SwiftLint from `scripts/lint` (wasn't pinned, was building from source every run)
- Fixed implicit `self` errors in `PageLayoutStore.swift`, `BertTokenizer.swift`, `NativePageViewController.swift`

## The Bug

When swiping mid-chapter and releasing without enough velocity to trigger a page turn, the snapback is too aggressive. Sometimes the snapback overshoots and skips forward a page. Example: user swipes right slightly (not enough velocity), releases, page snaps back left with such force it advances a page forward.

This is a **mid-chapter** issue, not a spine boundary issue. Within-spine page turns must feel native.

## Root Cause

In `scrollViewWillEndDragging`, the resolver computes `startPage` from `dragStartOffset` (where the finger initially touched down). When velocity is below threshold, it returns `.snapToPage(startPage)`. The scroll delegate then sets `targetContentOffset` to `startPage * pageWidth`.

The problem: `targetContentOffset` is the position UIScrollView will *decelerate toward*. When the user dragged partway to another page and releases, the current offset is between pages. UIScrollView decelerates from the current drag position back to `startPage * pageWidth` using its built-in physics, which can overshoot.

The old code handled the no-velocity case with `round(currentOffset / pageWidth)` — snapping to whichever page is *nearest to where the finger currently is*, not where it started.

## Fix

Add `currentPage` to `NavigationInput`, computed from the current scroll offset at finger lift (`round(currentOffset / pageWidth)`). When velocity is below threshold, snap to `currentPage` instead of `startPage`:
- Low velocity + finger near start page → snaps to start page (natural)
- Low velocity + finger dragged past halfway → snaps to next page (natural)
- No overshoot because the target is always the nearest page to the finger

## Files to Change

| File | Change |
|------|--------|
| `PageNavigationResolver.swift` | Add `currentPage` to `NavigationInput`, use it in below-threshold case |
| `PageNavigationResolverTests.swift` | Add tests for snapback: drag past halfway, drag slightly, drag backward past halfway |
| `WebPageViewController.swift` | Compute and pass `currentPage` from current scroll offset |

## Test Plan

1. Add unit tests to `PageNavigationResolverTests`
2. `./scripts/test PageNavigationResolverTests`
3. `./scripts/test` (all unit tests)
4. `./scripts/test ui:testSpineBoundaryNavigation`
5. `./scripts/test ui:testSimpleSpineCrossing`
6. `./scripts/run` for manual validation
