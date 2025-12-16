# Jitsi Participant Count Fix - Missing Hook for Existing Rooms

## Problem Identified

The participant count wasn't incrementing because the custom `mod_token_verification` plugin was only hooking into `muc-room-pre-create`, which fires when a **new room is created**. When a second user joins an **existing room**, this hook doesn't fire, so token verification wasn't happening for users joining existing rooms.

## Root Cause

**Missing Hook**: The plugin needed to also hook into `muc-occupant-pre-join` to verify tokens when users join existing MUC rooms.

## Solution

Added the `muc-occupant-pre-join` hook to the custom plugin:

```lua
-- Also verify when users join existing rooms
module:hook("muc-occupant-pre-join", function(event)
    local origin, room, stanza = event.origin, event.room, event.stanza;
    if DEBUG then module:log("debug", "pre join: %s to room %s", tostring(origin), tostring(room)); end
    if not verify_user(origin, stanza) then
        measure_fail(1);
        return true; -- Returning any value other than nil will halt processing of the event
    end
end, 1);
```

## What This Fixes

1. ✅ **Room Creation**: First user creates room (handled by `muc-room-pre-create`)
2. ✅ **Room Joining**: Subsequent users join existing room (now handled by `muc-occupant-pre-join`)
3. ✅ **Token Verification**: All users are verified regardless of whether they create or join
4. ✅ **Participant Count**: Users can now successfully join existing rooms, so count increments

## Testing

After this fix:
1. User 1 joins room → Creates room, count = 1
2. User 2 joins same room → Joins existing room, count = 2 ✅
3. User 3 joins same room → Joins existing room, count = 3 ✅

## Files Modified

- `prosody-plugins-configmap.yaml` - Added `muc-occupant-pre-join` hook

## Commit

`fix: Add muc-occupant-pre-join hook to verify tokens when users join existing rooms`

