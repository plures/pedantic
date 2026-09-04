# Pedantic local service

`@plures/pedantic-service` is the profile-scoped local host for Pedantic. It
currently provides one deliberately narrow capability: an authenticated,
Windows named-pipe `service.health` endpoint.

It is a transport boundary, not the source of Pedantic policy. The service
does not yet own configuration data, execute effects, evaluate PX procedures,
or write Chronos events. Those capabilities will be introduced behind the PX
and PluresDB boundaries defined in the refactor plan.

## Run locally

The service requires Node.js 24 or newer and a secret of at least 32 UTF-8
bytes shared with its local client.

```powershell
Set-Location services/pedantic-service
npm install
npm run build
$env:PEDANTIC_LOCAL_TOKEN = "replace-with-a-random-secret-of-at-least-32-bytes"
node dist/index.js --profile default
```

On Windows, the service listens on `\\.\pipe\pedantic-<profile>`. Clients send
one JSON request per line. The only supported request is:

```json
{
  "id": "health-1",
  "method": "service.health",
  "profileId": "default",
  "authorization": "the-shared-secret"
}
```

The endpoint confirms the host is reachable; it does not expose user data.
Requests with an invalid secret, another profile, malformed framing, or any
other method are rejected.

## Verify

```powershell
npm run typecheck
npm run lint
npm test
npm run build
```
