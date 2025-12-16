# Jitsi Meet Multi-User Investigation - Complete Findings

## Executive Summary

**Status**: ⚠️ **BLOCKED** - Custom plugin volume mount not being applied to Prosody pods

**Root Cause**: The `prosody-custom-plugins` ConfigMap volume mount exists in GitOps but is not being applied to running pods. This prevents the patched `mod_token_verification.lua` from loading, causing persistent "app_id must not be empty" errors.

## Investigation Results

### ✅ What's Working

1. **JWT Secret Configuration**
   - ✅ Secret exists: `jitsi-jwt-secret` in `liveclasses` namespace
   - ✅ Secret length: 64 characters (correct)
   - ✅ Token generation script correctly strips newlines
   - ✅ Prosody has `JWT_APP_SECRET` environment variable set correctly
   - ✅ Prosody has `JWT_APP_ID=darey-io` set correctly

2. **ConfigMap Configuration**
   - ✅ `prosody-custom-plugins` ConfigMap exists with `mod_token_verification.lua`
   - ✅ ConfigMap data is accessible via `kubectl get configmap`
   - ✅ Plugin code is correct (uses `module` context instead of `parentCtx`)

3. **Deployment Configuration (GitOps)**
   - ✅ `prosody-deployment.yaml` has volume mount defined:
     ```yaml
     volumeMounts:
       - name: prosody-custom-plugins
         mountPath: /prosody-plugins-custom
     volumes:
       - name: prosody-custom-plugins
         configMap:
           name: prosody-custom-plugins
     ```
   - ✅ `PROSODY_PLUGINS_DIR` environment variable set to include custom plugins path

4. **Ingress Configuration**
   - ✅ `/http-bind` route exists in `liveclasses-streaming-ingress.yaml`
   - ✅ `/jitsi/http-bind` route exists
   - ✅ External OPTIONS request to `/http-bind` returns 200 OK
   - ⚠️ **Note**: POST requests timeout (may be expected for BOSH)

5. **Jitsi Web Configuration**
   - ✅ `bosh: '/http-bind'` configured correctly
   - ✅ Domain, MUC, and focus hosts configured correctly

6. **Component Health**
   - ✅ All pods running: Prosody, Jicofo, JVB, Jitsi Web
   - ✅ Jicofo authenticated to Prosody
   - ✅ In-cluster connectivity works

### ❌ Critical Issues Found

1. **Custom Plugin Not Mounted** ⚠️ **BLOCKER**
   - **Problem**: `/prosody-plugins-custom` directory exists but is empty
   - **Evidence**: 
     ```bash
     kubectl -n liveclasses exec deploy/prosody -- ls -la /prosody-plugins-custom/
     # Result: Empty directory (only . and ..)
     ```
   - **Pod Description**: Volume mount NOT listed in pod's "Mounts:" section
   - **Impact**: Patched `mod_token_verification.lua` never loads, causing:
     - `'app_id' must not be empty` errors
     - Token verification failures
     - Users cannot join rooms

2. **Deployment Sync Issue**
   - **Problem**: Deployment YAML in GitOps has volume mount, but running pods don't
   - **Evidence**: 
     ```bash
     kubectl -n liveclasses describe pod -l app=prosody | grep -A 25 "Mounts:"
     # Result: Only shows prosody-config mount, NOT prosody-custom-plugins
     ```
   - **Possible Causes**:
     - ArgoCD hasn't synced the deployment changes
     - Deployment was manually applied but ArgoCD overwrote it
     - Caching issue in Kubernetes

3. **External BOSH POST Timeout**
   - **Problem**: POST requests to `/http-bind` timeout after 20+ seconds
   - **Status**: May be expected behavior (BOSH requires specific headers/body)
   - **Note**: OPTIONS requests work (200 OK)

## Test Results

### JWT Token Generation ✅
```bash
# Generated 3 tokens for multi-user testing
Room: MultiUserTest2024
- User 1 (Moderator): Token generated ✅
- User 2: Token generated ✅  
- User 3: Token generated ✅
```

### In-Cluster Connectivity ✅
```bash
# Prosody BOSH endpoint accessible internally
curl http://prosody:5280/http-bind
# Result: HTTP 200 OK ✅
```

### External Connectivity ⚠️
```bash
# OPTIONS request works
curl -X OPTIONS https://streaming-stg.talentos.darey.io/http-bind
# Result: HTTP 200 OK ✅

# POST request times out
curl -X POST https://streaming-stg.talentos.darey.io/http-bind
# Result: Timeout after 20+ seconds ⚠️
```

### Plugin Loading ❌
```bash
# Check if plugin file exists
kubectl -n liveclasses exec deploy/prosody -- cat /prosody-plugins-custom/mod_token_verification.lua
# Result: No such file or directory ❌

# Check Prosody logs for plugin init
kubectl -n liveclasses logs deploy/prosody | grep "token_verification init"
# Result: Shows "app_id must not be empty" error ❌
```

## Root Cause Analysis

The primary blocker is that the `prosody-custom-plugins` ConfigMap volume is not being mounted into the Prosody pods, despite:
1. The ConfigMap existing and having correct data
2. The deployment YAML in GitOps having the volume mount configured
3. The deployment being applied manually

**Most Likely Cause**: ArgoCD is managing this deployment and either:
- Hasn't synced the latest changes from GitOps
- Is configured to ignore volume mount changes
- Has a sync conflict

## Recommended Next Steps

### Immediate Actions (Priority 1)

1. **Force ArgoCD Sync**
   ```bash
   # Check ArgoCD application status
   kubectl -n argocd get applications | grep liveclasses
   
   # Force sync if needed
   argocd app sync liveclasses-staging
   ```

2. **Verify Deployment in Cluster**
   ```bash
   # Check if deployment has volume mount
   kubectl -n liveclasses get deployment prosody -o yaml | grep -A 10 "prosody-custom-plugins"
   
   # If missing, check ArgoCD sync status
   ```

3. **Alternative: Use Init Container**
   If ConfigMap mounting continues to fail, consider using an init container to copy the plugin file:
   ```yaml
   initContainers:
     - name: copy-plugins
       image: busybox
       command: ['sh', '-c', 'cp /plugins/* /shared/']
       volumeMounts:
         - name: prosody-custom-plugins
           mountPath: /plugins
         - name: shared-plugins
           mountPath: /shared
   ```

### Testing Steps (After Fix)

1. **Verify Plugin Loads**
   ```bash
   kubectl -n liveclasses exec deploy/prosody -- ls -la /prosody-plugins-custom/
   # Should show: mod_token_verification.lua
   
   kubectl -n liveclasses logs deploy/prosody | grep "token_verification init"
   # Should show: "app_id=darey-io" (not empty)
   ```

2. **End-to-End Multi-User Test**
   - Generate fresh JWT tokens
   - Open 3 browser windows with different tokens
   - Verify all participants can see each other
   - Check participant count increases

3. **Browser Console Check**
   - Open browser DevTools
   - Check Network tab for BOSH requests
   - Verify no 404 errors on `/http-bind`
   - Check Console for connection errors

## Files Modified

- ✅ `prosody-deployment.yaml` - Added volume mount (in GitOps)
- ✅ `prosody-plugins-configmap.yaml` - Custom plugin (exists)
- ✅ `configmap.yaml` - Prosody config with plugin_paths
- ✅ `jitsi-web-configmap.yaml` - BOSH endpoint config
- ✅ `liveclasses-streaming-ingress.yaml` - BOSH routes
- ✅ `generate-test-jwt.py` - Token generation script

## Generated Test URLs

**Room**: `MultiUserTest2024`

1. **User 1 (Moderator)**:
   ```
   https://streaming-stg.talentos.darey.io/MultiUserTest2024?jwt=<token1>
   ```

2. **User 2**:
   ```
   https://streaming-stg.talentos.darey.io/MultiUserTest2024?jwt=<token2>
   ```

3. **User 3**:
   ```
   https://streaming-stg.talentos.darey.io/MultiUserTest2024?jwt=<token3>
   ```

**Note**: Tokens expire after 1 hour. Regenerate if needed.

## Conclusion

The investigation revealed that all configuration is correct in GitOps, but the custom plugin volume mount is not being applied to running pods. This is preventing the patched token verification module from loading, which is required for multi-user conferencing to work.

**Next Action**: Force ArgoCD sync or investigate why the volume mount isn't being applied.

