# Trust model

What plushie-ruby's role is in the wider Plushie trust model, what
it implements on its own side, and where the broader picture lives.
The authoritative trust-model doc lives in plushie-rust
(`docs/stewardship/trust-model.md`); this doc describes the host
SDK's half.

## The asymmetric model

Plushie's wire boundary is asymmetric:

- **Renderer-to-host.** Closed and typed. The renderer can only
  push the fixed enumeration of event variants and structured
  responses defined by the wire protocol. There is no opaque-blob
  path, no string-eval, no generic "run this on the host"
  instruction. The host is therefore structurally protected from
  a compromised or malicious renderer. The remote-rendering use
  case relies on this.
- **Host-to-renderer.** Broader by design. The host asks the
  renderer to load fonts and images by path, render screenshots,
  exercise effects (clipboard, file dialogs, notifications),
  spawn subprocesses through structured renderer exec args. A compromised host can
  drive the full operation set against the user's machine
  wherever the renderer runs. Bounding this is the
  capability-manifest direction in plushie-rust's roadmap, not
  current work.

plushie-ruby is on the trusted side of this boundary. The runtime,
the bridge, the DSL, and user code all run as the host. Concerns
that frame the host as adversary are out of scope under the
current model.

## What plushie-ruby implements on its side

Renderer-to-host integrity depends on the host SDK actually
holding up the closed-shape contract on the receiving end.
plushie-ruby's load-bearing pieces:

- **Typed event decoding.** `Plushie::Protocol::Decode` parses
  incoming messages against the fixed event variant set. Unknown
  variants raise rather than silently flowing through to user
  code as opaque hashes. An unsafe decoder that passed arbitrary
  shapes through would undermine the host-protection claim.
- **Effect and query response correlation.** Effect commands and
  window queries get an internal wire ID and are tracked through
  a two-way mapping (`@effect_tags`, `@effect_ids`). Responses
  route back to the originating tag only after the wire ID
  matches an outstanding request. Stale or unknown wire IDs are
  dropped. A spoofable correlation (delivering by tag without
  the wire-ID check) would let a malicious renderer drive the
  wrong handler.
- **No host-side eval surface.** The runtime never `eval`s,
  `instance_eval`s, or `send`s data sourced from the renderer.
  Symbols in event payloads come from the codec's known
  enumeration, not from arbitrary renderer-supplied strings; the
  codec does not call `to_sym` on untrusted strings on a path
  that grows the symbol table from input. Strict enums (mouse
  buttons, named keys, modifiers) parse through
  `Plushie::Protocol::Parsers` against a closed enumeration.
- **App-level hygiene is the app's choice.** An app that wires
  user-provided event content into shell-out commands or
  filesystem paths is making its own choice. The protocol cannot
  enforce app-side hygiene.

## What is not protected today

- **DoS and resource exhaustion.** A malicious renderer can flood
  typed events at the protocol rate. The runtime has frame-level
  coalescing for high-frequency event types and configurable
  per-subscription rates; a host SDK still has to handle the
  firehose gracefully (see `resilience.md`).
- **Host-to-renderer surface.** Effect dispatch, file path
  inputs, font and image loading by path, and renderer-owned child process spawn are
  full-trust today. Bounding them is the capability-manifest
  direction.
- **Same-access channels.** A user with shell access on the
  machine running the host can read its memory and files
  directly. plushie-ruby does not protect against the user
  acting on themselves.

## Channel posture

The wire protocol is byte-stream agnostic. Confidentiality and
integrity are delegated to the outer transport (OS pipe, named
pipe, SSH, TCP+TLS). The wire is not its own crypto layer, by
design. Proposals to add per-message MACs or encrypted fields to
the wire format are misframed; that responsibility belongs with
the outer transport.

The session token at the wire boundary binds a host to a
particular renderer instance. It is not a confidentiality
mechanism.

## Implications

- Work that loosens renderer-to-host integrity (an unsafe
  decoder shape, an opaque-blob delivery path, spoofable
  response correlation, a string-eval path, calling `to_sym` on
  renderer-supplied strings on a hot path) is a deliberate
  decision, not a routine refactor; default to no.
- Memory-corruption or RCE-shaped findings on either side are
  in scope today regardless of the broader capability-manifest
  direction.
- Host-to-renderer concerns (file path inputs, effect dispatch,
  spawn surface) defer to the capability-manifest roadmap in
  plushie-rust.
- Wire-level confidentiality or integrity expectations belong
  with the outer transport.
- DoS and resource-exhaustion concerns are low priority;
  configurable knobs (event rates, bounded queues) are
  preferred over aggressive defaults.
