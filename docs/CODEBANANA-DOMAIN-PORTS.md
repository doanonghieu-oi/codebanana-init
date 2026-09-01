# CodeBanana domain/port notes

The workspace currently has CodeBanana allocation metadata for general web preview services. These mappings are not required by Desktop Commander Remote.

## Current allocation metadata

Source: `.coding-agent/domain-port-allocation.yaml` in the container.

```text
app0 -> port 8000 -> app-preview-7d7b41d923002bf1cd84b69d8f3ac662.codebanana.com
app1 -> port 8001 -> app-preview-33c1544e00896aa523f82fc277aa8604.codebanana.com
```

The metadata is runtime allocation state and should not be treated as a permanent API contract.

## Mobile ngrok domains

The environment may also expose `m-*.ngrok.app` domains for mobile/Expo development. Those are mobile development tunnels and are unrelated to Desktop Commander Remote.

Do not hard-code a mobile tunnel URL into the Desktop Commander startup scripts.

## Getting authoritative runtime mappings

CodeBanana exposes the agent-side MCP tool:

```text
get_all_domains_ports()
```

This is not a shell executable in the container. If an application needs the current public domain/port mapping, query the CodeBanana runtime tool rather than parsing or guessing a domain.

## Desktop Commander

Desktop Commander Remote uses an outbound WebSocket connection and does not require:

- port 8000 or 8001;
- port 9100 or 9101;
- an HTTP preview domain;
- an ngrok URL.

Its first authentication uses an OAuth Device Flow, so there is no local OAuth callback port to expose.
