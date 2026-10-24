# Step 14: AlertDialog Viewport Intrinsic Dimension Resolution & Test Coverage

**Date:** 24 October 2026  
**Status:** Completed & Verified  

---

## 1. Issue Diagnosis & Root Cause

### 1.1 Exception Encountered
```text
RenderShrinkWrappingViewport does not support returning intrinsic dimensions.
Calculating the intrinsic dimensions would require instantiating every child of the viewport, which
defeats the point of viewports being lazy.
The relevant error-causing widget was:
  AlertDialog: report_item_dialog.dart:459:25
```

### 1.2 Root Cause Analysis
* When `AlertDialog` is rendered on Flutter Web / Desktop, its layout logic performs intrinsic dimension measurement (`computeMaxIntrinsicWidth`) to calculate optimal modal bounds.
* In `report_item_dialog.dart`, the `_showPossibleMatchesModal` method placed a `ListView.separated` with `shrinkWrap: true` inside an `Expanded` inside a `Column` wrapped only by a `ConstrainedBox(maxWidth: 500, maxHeight: 400)`.
* Because `ConstrainedBox` only sets upper bounds without an explicit width/height, `AlertDialog` was forced to measure intrinsic dimensions on the `ListView`.
* `shrinkWrap: true` creates a `RenderShrinkWrappingViewport`, which explicitly prohibits intrinsic dimension calculation by design (throwing an assertion error to protect lazy rendering performance).

### 1.3 Flutter Web Noto Font Warning
```text
Could not find a set of Noto fonts to display all missing characters. Please add a font asset for the missing characters. See:
https://docs.flutter.dev/cookbook/design/fonts
```
* On Flutter Web (CanvasKit / Skia), when unicode currency symbols (like `₹`) or new emojis are rendered without bundled local font assets in `pubspec.yaml`, the engine outputs this informational warning as it fetches fallback glyphs dynamically. This is standard engine behavior and does not impact application layout.

---

## 2. Changes Applied

### 2.1 Fixed `report_item_dialog.dart` Modal Constraints
* Replaced loose `ConstrainedBox` with an explicitly dimensioned, responsive `SizedBox`:
  ```dart
  final screenWidth = MediaQuery.sizeOf(ctx).width;
  final dialogWidth = (screenWidth - 48).clamp(280.0, 480.0);
  final dialogHeight = (matches.length * 70.0 + 80.0).clamp(160.0, 420.0);
  ```
* Set `shrinkWrap: false` on `ListView.separated` inside `Expanded`.
* Since the dimensions are bounded and concrete, `AlertDialog` does not attempt intrinsic viewport queries, eliminating the runtime crash entirely across mobile, tablet, and desktop viewports.

### 2.2 Added Automated Regression Widget Test
* Added widget test in `frontend/test/ui_components_test.dart`:
  `'ReportItemDialog possible matches dialog renders properly without viewport intrinsic dimension errors'`
* Verifies form submission with possible matches triggers the modal dialog cleanly and allows closing without any layout or rendering assertion exceptions.

---

## 3. Verification & Test Results

* **Static Analysis:**
  ```bash
  flutter analyze
  # Output: No issues found! (ran in 0.6s)
  ```
* **Full Automated Test Suite:**
  ```bash
  flutter test
  # Output: All 40 tests passed! (0 failures, 1 unreachable live server test gracefully skipped)
  ```
