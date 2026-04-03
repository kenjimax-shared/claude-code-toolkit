#!/usr/bin/env bash
# Hook: Passthrough for agent-browser.
#
# The wrapper handles everything transparently:
#   - Re-open same session → navigates existing browser (no new Chrome)
#   - Cross-terminal open → creates isolated derivative
#   - Fresh session → opens normally
#
# No blocking needed. Agents never see errors, so they never invent new names.
exit 0
