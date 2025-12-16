# Jitsi Testing Guide

## Quick Test URLs

### 🌐 External URLs (via Ingress)

**Base Domain:** `https://streaming-stg.talentos.darey.io`

1. **Jitsi Web Interface:**
   ```
   https://streaming-stg.talentos.darey.io/jitsi
   ```

2. **Join a Meeting Room (example):**
   ```
   https://streaming-stg.talentos.darey.io/jitsi/TestRoom123?jwt=<token>
   ```
   ⚠️ **Note:** JWT token is required for authentication

3. **Jitsi BOSH/XMPP Endpoint:**
   ```
   https://streaming-stg.talentos.darey.io/jitsi/http-bind
   ```

### 🔧 Internal URLs (via Port Forward)

**Port Forward Command:**
```bash
kubectl port-forward -n liveclasses svc/jitsi-web 8080:80
```

1. **Jitsi Web Interface:**
   ```
   http://localhost:8080
   ```

2. **Join a Meeting Room (example):**
   ```
   http://localhost:8080/TestRoom123?jwt=<token>
   ```

3. **Health Check (if available):**
   ```
   http://localhost:8080/health
   ```

## Authentication

Jitsi requires JWT token authentication. To test:

### Option 1: Generate Test JWT Token

```bash
cd /Users/dare/Desktop/xterns/darey-new/gitops/argocd/applications/staging-workload/liveclasses
python3 generate-test-jwt.py TestRoom123 user123 "Test User"
```

This will output a JWT token. Use it in the URL:
```
https://streaming-stg.talentos.darey.io/jitsi/TestRoom123?jwt=<generated-token>
```

### Option 2: Get JWT Secret and Generate Manually

```bash
# Get JWT secret
kubectl get secret jitsi-jwt-secret -n liveclasses -o jsonpath='{.data.JITSI_JWT_SECRET}' | base64 -d
```

Then use a JWT library to generate a token with:
- `iss`: "darey-io"
- `aud`: "jitsi"
- `room`: "<room-id>"
- `moderator`: true/false

## Quick Test Commands

### Test 1: Check Jitsi Web Interface (via Port Forward)

```bash
# Start port forward
kubectl port-forward -n liveclasses svc/jitsi-web 8080:80

# In another terminal, test
curl -I http://localhost:8080
```

**Expected:** HTTP 200 OK

### Test 2: Check Jitsi Components Health

```bash
# Check all Jitsi pods are running
kubectl get pods -n liveclasses | grep -E "jitsi|prosody|jicofo|jvb"

# Check services
kubectl get svc -n liveclasses | grep -E "jitsi|prosody|jicofo|jvb"

# Check endpoints
kubectl get endpoints -n liveclasses | grep -E "jitsi|prosody|jicofo|jvb"
```

**Expected:** All pods in `Running` state, services have endpoints

### Test 3: Test External Access (via Ingress)

```bash
# Test Jitsi web interface
curl -I https://streaming-stg.talentos.darey.io/jitsi

# Test BOSH endpoint
curl -I https://streaming-stg.talentos.darey.io/jitsi/http-bind
```

**Expected:** HTTP 200 OK or 401 (authentication required, which is expected)

### Test 4: Test Meeting Join (with JWT)

```bash
# Generate JWT token first
python3 generate-test-jwt.py TestRoom123 user123 "Test User" --moderator

# Then open in browser:
# https://streaming-stg.talentos.darey.io/jitsi/TestRoom123?jwt=<token>
```

## Component Status Check

```bash
# All Jitsi components
kubectl get pods,svc,deployments -n liveclasses | grep -E "jitsi|prosody|jicofo|jvb|jibri"

# Check logs if issues
kubectl logs -n liveclasses deployment/jitsi-web --tail=50
kubectl logs -n liveclasses deployment/prosody --tail=50
kubectl logs -n liveclasses deployment/jicofo --tail=50
kubectl logs -n liveclasses deployment/jvb --tail=50
```

## Expected Behavior

### ✅ Working Jitsi:
- Web interface loads at `/jitsi` path
- Can join meeting rooms with valid JWT token
- Audio/video works for participants
- Multiple participants can join the same room

### ❌ Common Issues:
- **401 Unauthorized**: Missing or invalid JWT token
- **404 Not Found**: Ingress routing issue or service not running
- **Connection Failed**: Prosody/XMPP server not accessible
- **No Audio/Video**: JVB (Video Bridge) not working or network issues

## Multi-Participant Testing

To test multiple participants joining:

1. **Generate multiple JWT tokens:**
   ```bash
   python3 generate-test-jwt.py TestRoom123 user1 "User 1" --moderator
   python3 generate-test-jwt.py TestRoom123 user2 "User 2"
   python3 generate-test-jwt.py TestRoom123 user3 "User 3"
   ```

2. **Open multiple browser tabs/windows:**
   - Tab 1: `https://streaming-stg.talentos.darey.io/jitsi/TestRoom123?jwt=<token1>`
   - Tab 2: `https://streaming-stg.talentos.darey.io/jitsi/TestRoom123?jwt=<token2>`
   - Tab 3: `https://streaming-stg.talentos.darey.io/jitsi/TestRoom123?jwt=<token3>`

3. **Verify:**
   - All participants can see each other
   - Audio works for all
   - Video works for all
   - No connection drops when 3+ participants join

## Troubleshooting

### Check Jitsi Component Logs

```bash
# Jitsi Web
kubectl logs -n liveclasses deployment/jitsi-web --tail=100

# Prosody (XMPP)
kubectl logs -n liveclasses deployment/prosody --tail=100

# Jicofo (Conference Focus)
kubectl logs -n liveclasses deployment/jicofo --tail=100

# JVB (Video Bridge)
kubectl logs -n liveclasses deployment/jvb --tail=100
```

### Check Service Connectivity

```bash
# Test internal service connectivity
kubectl run -n liveclasses --rm -i --restart=Never test-jitsi --image=curlimages/curl -- \
  curl -s http://jitsi-web:80

kubectl run -n liveclasses --rm -i --restart=Never test-prosody --image=curlimages/curl -- \
  curl -s http://prosody:5280/http-bind
```

### Check Ingress

```bash
# Check ingress configuration
kubectl get ingress -n liveclasses liveclasses-streaming-ingress -o yaml

# Check ingress controller logs
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller --tail=50 | grep jitsi
```

