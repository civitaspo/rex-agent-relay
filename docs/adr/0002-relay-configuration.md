---
status: accepted
date: 2026-11-02
---

# Configure the Relay window through setup

## Context

The Relay window is launched by a Rex action configured through `setup`. The `deliver` command also runs directly without that action.

## Decision

Configure the window's finder, editor, pager, and keys through `setup`. Validate the keys before registering the actions and pass the settings as arguments to the relay script. Configure the relay's inline size limit and outbox directory through environment variables, which are also available to direct `deliver` calls.

## Consequences

Users can configure window commands and keys together in Rex. Existing users of `REX_AGENT_RELAY_FUZZY_FINDER` must move that value to `setup.finder`. Moving all relay settings to `setup` requires a separate decision about how direct `deliver` calls receive configuration.
