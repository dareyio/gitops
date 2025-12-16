# BigBlueButton Internal Test URLs

**Port Forwarding Active:** Services are forwarded to localhost

## Port Forwarded Services

- **bbb-api:** `localhost:8090`
- **bbb-web:** `localhost:48087`
- **redis:** `localhost:6379`

---

## API Endpoints

### 1. API Version
```
http://localhost:8090/bigbluebutton/api?action=getAPIVersion
```

### 2. Get Meetings
```
http://localhost:8090/bigbluebutton/api?action=getMeetings&checksum=<checksum>
```

**Generate checksum:**
```python
import hashlib
secret = "<your-secret>"  # From kubectl get secret bbb-secrets
action = "getMeetings"
params = ""
checksum = hashlib.sha1((action + params + secret).encode()).hexdigest()
```

### 3. Create Meeting
```
http://localhost:8090/bigbluebutton/api/create?meetingID=<meetingID>&name=<name>&attendeePW=<ap>&moderatorPW=<mp>&checksum=<checksum>
```

**Example:**
```
http://localhost:8090/bigbluebutton/api/create?meetingID=test123&name=Test+Meeting&attendeePW=ap&moderatorPW=mp&checksum=<checksum>
```

**Generate checksum:**
```python
import hashlib
secret = "<your-secret>"
action = "create"
params = "meetingID=test123&name=Test+Meeting&attendeePW=ap&moderatorPW=mp"
checksum = hashlib.sha1((action + params + secret).encode()).hexdigest()
```

### 4. Get Meeting Info
```
http://localhost:8090/bigbluebutton/api/getMeetingInfo?meetingID=<meetingID>&checksum=<checksum>
```

### 5. Join Meeting (Moderator)
```
http://localhost:8090/bigbluebutton/api/join?meetingID=<meetingID>&password=<moderatorPW>&fullName=<name>&checksum=<checksum>
```

### 6. Join Meeting (Attendee)
```
http://localhost:8090/bigbluebutton/api/join?meetingID=<meetingID>&password=<attendeePW>&fullName=<name>&checksum=<checksum>
```

### 7. End Meeting
```
http://localhost:8090/bigbluebutton/api/end?meetingID=<meetingID>&password=<moderatorPW>&checksum=<checksum>
```

### 8. Get Default Config XML
```
http://localhost:8090/bigbluebutton/api/getDefaultConfigXML?checksum=<checksum>
```

---

## Web Interface

### Root Path
```
http://localhost:48087/
```

### BBB Path
```
http://localhost:48087/bbb/
```

### Learning Analytics Dashboard
```
http://localhost:48087/learning-analytics-dashboard/
```

### API Proxy (via bbb-web)
```
http://localhost:48087/bigbluebutton/api?action=getAPIVersion
```

---

## Service Health Checks

### API Health
```bash
curl http://localhost:8090/bigbluebutton/api?action=getAPIVersion
```

### Web Health
```bash
curl -I http://localhost:48087/
```

### Redis Health
```bash
redis-cli -h localhost -p 6379 ping
```

---

## Python Script for Checksum Generation

```python
#!/usr/bin/env python3
import hashlib
import subprocess
import base64

# Get secret from Kubernetes
result = subprocess.run(
    ['kubectl', 'get', 'secret', '-n', 'liveclasses', 'bbb-secrets', 
     '-o', 'jsonpath={.data.api-secret}'],
    capture_output=True, text=True
)

if result.returncode == 0:
    secret = base64.b64decode(result.stdout).decode('utf-8')
else:
    secret = "placeholder-secret-change-me"

def generate_checksum(action, params=""):
    """Generate BBB API checksum"""
    checksum_string = action + params + secret
    return hashlib.sha1(checksum_string.encode()).hexdigest()

# Example usage
action = "create"
params = "meetingID=test123&name=Test+Meeting&attendeePW=ap&moderatorPW=mp"
checksum = generate_checksum(action, params)
print(f"Checksum: {checksum}")
print(f"URL: http://localhost:8090/bigbluebutton/api/create?{params}&checksum={checksum}")
```

---

## Quick Test Commands

```bash
# Test API Version
curl 'http://localhost:8090/bigbluebutton/api?action=getAPIVersion'

# Test Web Interface
curl -I http://localhost:48087/

# Test Redis
redis-cli -h localhost -p 6379 ping

# Create a meeting (replace checksum)
curl 'http://localhost:8090/bigbluebutton/api/create?meetingID=test123&name=Test&attendeePW=ap&moderatorPW=mp&checksum=<checksum>'

# List meetings (replace checksum)
curl 'http://localhost:8090/bigbluebutton/api?action=getMeetings&checksum=<checksum>'
```

---

## Port Forward Management

### Check Active Port Forwards
```bash
ps aux | grep "kubectl port-forward" | grep -v grep
```

### Stop Port Forwards
```bash
pkill -f "kubectl port-forward"
```

### Restart Port Forwards
```bash
# bbb-api
kubectl port-forward -n liveclasses svc/bbb-api 8090:8090 &

# bbb-web
kubectl port-forward -n liveclasses svc/bbb-web 48087:80 &

# redis
kubectl port-forward -n liveclasses svc/redis 6379:6379 &
```

---

## Notes

- **Secret:** Retrieved from Kubernetes secret `bbb-secrets` in namespace `liveclasses`
- **Meeting IDs:** Must be unique, alphanumeric, and URL-safe
- **Checksums:** Required for all API calls except `getAPIVersion`
- **Timeouts:** Port forwards will close if the terminal session ends
- **Multiple Meetings:** Each meeting needs a unique meetingID

---

## Troubleshooting

### Port Already in Use
```bash
# Find process using port
lsof -i :8090
lsof -i :48087
lsof -i :6379

# Kill process
kill -9 <PID>
```

### Port Forward Not Working
```bash
# Check if pods are running
kubectl get pods -n liveclasses -l app=bbb-api
kubectl get pods -n liveclasses -l app=bbb-web

# Check service endpoints
kubectl get endpoints -n liveclasses bbb-api
kubectl get endpoints -n liveclasses bbb-web
```

### API Returns 404
- Verify the API path: `/bigbluebutton/api`
- Check if bbb-api pod is running
- Verify service is correctly configured

### Web Interface Timeout
- Check bbb-web pod logs: `kubectl logs -n liveclasses -l app=bbb-web`
- Verify nginx configuration
- Check if port 48087 is accessible

