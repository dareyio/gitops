#!/usr/bin/env python3
"""
Generate a test JWT token for Jitsi authentication in staging

Usage:
    python3 generate-test-jwt.py <room-id> [user-id] [display-name]

Example:
    python3 generate-test-jwt.py SolarRealmsPushToo
    python3 generate-test-jwt.py SolarRealmsPushToo user123 "John Doe"
"""

import jwt
import time
import sys
import base64
import subprocess

# Get JWT secret from Kubernetes secret
def get_jwt_secret():
    try:
        result = subprocess.run(
            ['kubectl', 'get', 'secret', 'jitsi-jwt-secret', '-n', 'liveclasses', 
             '-o', 'jsonpath={.data.JITSI_JWT_SECRET}'],
            capture_output=True,
            text=True,
            check=True
        )
        secret_b64 = result.stdout.strip()
        if not secret_b64:
            raise ValueError("Secret not found or empty")
        return base64.b64decode(secret_b64).decode('utf-8')
    except subprocess.CalledProcessError:
        print("❌ Error: Could not retrieve JWT secret from Kubernetes")
        print("   Make sure kubectl is configured and you have access to the liveclasses namespace")
        sys.exit(1)
    except Exception as e:
        print(f"❌ Error decoding secret: {e}")
        sys.exit(1)

def generate_jwt_token(room_id, user_id=None, display_name=None, is_moderator=False):
    """Generate a JWT token for Jitsi authentication"""
    
    # Get JWT secret from Kubernetes
    jwt_secret = get_jwt_secret()
    
    # Default values
    user_id = user_id or "test-user"
    display_name = display_name or "Test User"
    
    # Create JWT payload matching Jitsi requirements
    now = int(time.time())
    payload = {
        "iss": "darey-io",  # Issuer (must match prosody config)
        "aud": "jitsi",     # Audience (must match prosody config)
        "sub": "streaming-api.infra.darey.io",
        "room": room_id,    # Room ID
        "exp": now + (60 * 60),  # 1 hour expiration
        "iat": now,
        "nbf": now,
        "context": {
            "user": {
                "id": user_id,
                "name": display_name,
                "email": f"{user_id}@test.darey.io",
                "avatar": f"https://api.dicebear.com/7.x/initials/svg?seed={display_name}"
            },
            "features": {
                "livestreaming": is_moderator,
                "recording": is_moderator,
                "transcription": True
            }
        },
        "moderator": is_moderator
    }
    
    # Generate token
    token = jwt.encode(payload, jwt_secret, algorithm="HS256")
    return token

def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    
    room_id = sys.argv[1]
    user_id = sys.argv[2] if len(sys.argv) > 2 else None
    display_name = sys.argv[3] if len(sys.argv) > 3 else None
    is_moderator = "--moderator" in sys.argv or "-m" in sys.argv
    
    try:
        token = generate_jwt_token(room_id, user_id, display_name, is_moderator)
        
        print("\n✅ JWT Token Generated Successfully!")
        print("=" * 60)
        print(f"Room ID: {room_id}")
        print(f"User ID: {user_id or 'test-user'}")
        print(f"Display Name: {display_name or 'Test User'}")
        print(f"Moderator: {is_moderator}")
        print("=" * 60)
        print("\n🔗 Full URL with JWT token:")
        print(f"https://streaming-stg.talentos.darey.io/{room_id}?jwt={token}")
        print("\n📋 JWT Token (for manual use):")
        print(token)
        print("\n💡 Tip: Copy the full URL above and paste it into your browser")
        print("=" * 60)
        
    except Exception as e:
        print(f"❌ Error generating token: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()

