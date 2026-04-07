# CCC Parser And Config Design

## Goal And Scope

Define the next planning-stage contract for expanding `ccc` beyond `ccc "<Prompt>"` without implementing the parser yet.

## Planned Token Inventory

- `@alias`
- `+0` through `+4`
- `:provider:model`
- `:model`
- runner selectors: `c`, `cc`, `oc`, `k`, `rc`, `cr`, `codex`, `claude`, `opencode`, `kimi`, `roocode`, `crush`, `pi`

## Proposed Parse Slots And Allowed Token Order

Planned-only direction:

1. runner selector
2. thinking selector
3. provider/model selector
4. alias or preset selector
5. prompt

This order is not yet committed as final behavior.

## `@alias` Design Notes

- `@alias` should likely represent a named preset, not just a prompt shortcut.
- A preset may later carry runner/model/thinking defaults.
- Explicit CLI tokens should probably override alias-provided defaults, but this is not locked.

## `+0..+4` Thinking-Level Design Notes

- Planned mapping:
  - `+0`: off
  - `+1`: low
  - `+2`: medium
  - `+3`: high
  - `+4`: xhigh/max
- The external contract should stay numeric even if internal runners use different labels.

## `:provider:model` And `:model` Design Notes

- `:provider:model` is the unambiguous explicit selector.
- `:model` depends on default-provider resolution and is therefore inherently less stable until config precedence is defined.

## Runner Selector Vocabulary

- built-ins under consideration: `c`, `cc`, `oc`, `k`, `rc`, `cr`, `codex`, `claude`, `opencode`, `kimi`, `roocode`, `crush`, `pi`
- config should eventually allow custom abbreviations and custom names, but built-in collision policy still needs to be defined.

## Config-Backed Abbreviations And Defaults

Planned config responsibilities:

- custom aliases and presets
- custom runner abbreviations or names
- bundled-runner default provider/model values
- custom-name default provider/model values

## Normalization And Resolution Pipeline

Planned-only direction:

1. tokenize argv
2. detect explicit runner/thinking/provider-model/alias tokens
3. load alias expansion if present
4. apply explicit-token override rules
5. resolve default provider/model
6. build a normalized invocation spec

## Non-Goals For This Milestone

- implementing the parser
- finalizing token order
- finalizing config schema
- finalizing alias override precedence

## Open Precedence Questions

1. Are selector tokens order-sensitive, or can they appear in any order before the prompt?
2. Does `@alias` expand first and then yield to explicit CLI tokens, or does it win?
3. How does `:model` resolve if multiple providers expose the same model name?
4. How do config-defined names collide with built-in runner selectors?
5. What is the final precedence stack among explicit tokens, alias contents, runner defaults, config defaults, and implicit fallbacks?
