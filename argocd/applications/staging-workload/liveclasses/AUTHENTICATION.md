# Liveclasses Streaming Authentication Guide

## Overview

The liveclasses streaming service uses **JWT token authentication** for security. Direct access to rooms without a valid JWT token will result in an authentication error.

## Authentication Method

- **Type**: JWT (JSON Web Token)
- **Issuer**: `darey-io`
- **Audience**: `jitsi`
- **Required**: Yes (`allow_empty_token = false`)

## How Authentication Works

1. **Production Flow** (via Darey.io platform):
   - User accesses a live class session through the Darey.io platform
   - Platform calls Supabase Edge Function: `/functions/v1/jitsi-auth`
   - Function generates JWT token with user info and room ID
   - Token is passed to Jitsi via URL parameter: `?jwt=<token>`
   - Jitsi validates token with Prosody XMPP server

2. **Direct URL Access** (testing):
   - Requires a valid JWT token in the URL
   - Format: `https://streaming-stg.talentos.darey.io/<room-id>?jwt=<token>`

## Generating Test JWT Tokens

### Using the Python Script

A helper script is provided to generate test JWT tokens:

```bash
# Basic usage (room ID only)
python3 generate-test-jwt.py SolarRealmsPushToo

# With user ID
python3 generate-test-jwt.py SolarRealmsPushToo user123

# With user ID and display name
python3 generate-test-jwt.py SolarRealmsPushToo user123 "John Doe"

# As moderator (with recording/livestreaming permissions)
python3 generate-test-jwt.py SolarRealmsPushToo user123 "John Doe" --moderator
```

### Manual Token Generation

If you need to generate tokens manually, use the JWT secret from Kubernetes:

```bash
# Get the JWT secret
kubectl get secret jitsi-jwt-secret -n liveclasses -o jsonpath='{.data.JITSI_JWT_SECRET}' | base64 -d

# Use this secret to sign a JWT with the following payload structure:
{
  "iss": "darey-io",
  "aud": "jitsi",
  "sub": "streaming-api.infra.darey.io",
  "room": "<room-id>",
  "exp": <timestamp + 3600>,
  "iat": <current_timestamp>,
  "nbf": <current_timestamp>,
  "context": {
    "user": {
      "id": "<user-id>",
      "name": "<display-name>",
      "email": "<email>"
    },
    "features": {
      "livestreaming": <true/false>,
      "recording": <true/false>,
      "transcription": true
    }
  },
  "moderator": <true/false>
}
```

## Why You See "Authentication Required" Dialog

If you access a room URL directly without a JWT token (e.g., `https://streaming-stg.talentos.darey.io/SolarRealmsPushToo`), you'll see a browser authentication dialog. This is expected behavior because:

1. Prosody is configured with `allow_empty_token = false`
2. No JWT token is present in the URL
3. Prosody rejects the connection
4. Browser shows basic auth dialog as fallback

**Solution**: Always include a valid JWT token in the URL when accessing directly.

## Troubleshooting

### Token Validation Errors

If you get authentication errors, check:

1. **Token Format**: Must be a valid JWT (3 parts separated by dots)
2. **Token Expiration**: Tokens expire after 1 hour
3. **Issuer/Audience**: Must match Prosody config (`iss: "darey-io"`, `aud: "jitsi"`)
4. **Secret Match**: JWT secret must match between:
   - Kubernetes secret: `jitsi-jwt-secret`
   - Supabase Edge Function: `JITSI_JWT_SECRET` env var
   - Prosody: `JWT_APP_SECRET` env var

### Checking Token Validity

You can decode a JWT token (without verification) to check its contents:

```bash
# Using jwt-cli (install: npm install -g @tsndr/cloudflare-worker-jwt)
echo "<your-token>" | jwt decode

# Or use online tools like jwt.io (decode only, don't verify)
```

### Common Issues

1. **"Invalid token"**: Secret mismatch between token generation and Prosody
2. **"Token expired"**: Generate a new token (tokens expire after 1 hour)
3. **"Missing room"**: Ensure `room` field in JWT payload matches the URL room ID
4. **"Unauthorized"**: Check that `iss` and `aud` match Prosody configuration

## Configuration Files

- **Prosody Config**: `configmap.yaml` (defines JWT requirements)
- **JWT Secret**: `external-secret.yaml` (syncs from AWS Secrets Manager)
- **Jitsi Web Config**: `jitsi-web-configmap.yaml` (client-side configuration)

## Security Notes

- JWT tokens should never be logged or exposed in client-side code
- Tokens expire after 1 hour for security
- Each token is room-specific (cannot be reused across rooms)
- Moderator tokens grant additional permissions (recording, livestreaming)

