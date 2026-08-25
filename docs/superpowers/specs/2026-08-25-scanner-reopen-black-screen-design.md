# Scanner Reopen Black Screen Design

## Problem

After a scan returns from `ScannerPage`, opening the scanner again can show a
black preview. `SpreadsheetPage` starts a new `MobileScanner` immediately after
the previous scanner route is popped. In `mobile_scanner 3.5.7`, the widget
provides `startDelay` specifically for starting another scanner instance right
after disposing the first one; the current page leaves it disabled.

## Selected Approach

Set `startDelay: true` on the existing `MobileScanner` in
`lib/scanner_page.dart`. This uses the plugin's lifecycle guard at the point
where the new scanner instance is created, without adding business-level delays
or changing the existing controller stop and navigation flow.

## Data Flow

1. `SpreadsheetPage._scanRow` pushes `ScannerPage`.
2. `ScannerPage` starts its scanner with the plugin-managed startup delay.
3. The first valid barcode calls `_finish`, which stops the controller and pops
   the route with the scanned value.
4. `SpreadsheetPage._scanRow` matches the returned value and opens the existing
   `DeviceEditPage`.
5. A later scan creates a fresh `ScannerPage`; its scanner again uses the same
   startup guard.

## Error Handling

No new error path is required. Existing startup error rendering, stop failure
handling, startup timeout, and single-completion protection remain unchanged.

## Testing

Add a widget regression assertion that the scanner is configured with
`startDelay: true`. Keep the existing scan result, stop ordering, startup
timeout, permission error, and spreadsheet navigation tests. Run the focused
scanner/spreadsheet tests and the full Flutter test suite.
