#!/usr/bin/env python3
"""
Generate a test JWT token for Jitsi authentication in staging

Usage:
    python3 generate-test-jwt.py <room-id> [user-id] [display-name] [--moderator|-m]
    python3 generate-test-jwt.py <room-id> --multi-user [--count N] [--moderator-first]

Examples:
    # Single user
    python3 generate-test-jwt.py SolarRealmsPushToo
    python3 generate-test-jwt.py SolarRealmsPushToo user123 "John Doe"
    python3 generate-test-jwt.py SolarRealmsPushToo user123 "John Doe" --moderator
    
    # Multiple users (for testing multi-user scenarios)
    python3 generate-test-jwt.py MultiUserTest --multi-user
    python3 generate-test-jwt.py MultiUserTest --multi-user --count 5
    python3 generate-test-jwt.py MultiUserTest --multi-user --count 3 --moderator-first
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
        secret = base64.b64decode(secret_b64).decode('utf-8')
        # Strip any trailing whitespace/newlines that might cause signature mismatches
        return secret.strip()
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

def generate_multiple_tokens(room_id, count=3, moderator_first=False):
    """Generate multiple JWT tokens for multi-user testing"""
    tokens = []
    
    for i in range(1, count + 1):
        user_id = f"user{i}"
        display_name = f"User {i}"
        is_moderator = (i == 1) if moderator_first else False
        
        if i == 1 and moderator_first:
            display_name = f"User {i} (Moderator)"
        
        token = generate_jwt_token(room_id, user_id, display_name, is_moderator)
        tokens.append({
            "user_id": user_id,
            "display_name": display_name,
            "is_moderator": is_moderator,
            "token": token,
            "url": f"https://streaming-stg.talentos.darey.io/{room_id}?jwt={token}"
        })
    
    return tokens

def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    
    room_id = sys.argv[1]
    
    # Check for multi-user mode
    if "--multi-user" in sys.argv or "-mu" in sys.argv:
        # Parse count
        count = 3  # default
        if "--count" in sys.argv:
            try:
                count_idx = sys.argv.index("--count")
                count = int(sys.argv[count_idx + 1])
            except (ValueError, IndexError):
                print("❌ Error: --count requires a number")
                sys.exit(1)
        
        moderator_first = "--moderator-first" in sys.argv or "--mf" in sys.argv
        
        try:
            tokens = generate_multiple_tokens(room_id, count, moderator_first)
            
            print("\n✅ Generated JWT Tokens for Multi-User Testing!")
            print("=" * 80)
            print(f"Room ID: {room_id}")
            print(f"Number of Users: {len(tokens)}")
            print("=" * 80)
            
            for i, token_info in enumerate(tokens, 1):
                role = "👤 Moderator" if token_info["is_moderator"] else "👤 Participant"
                print(f"\n{role} - {token_info['display_name']}:")
                print(f"  URL: {token_info['url']}")
                print(f"  Token: {token_info['token']}")
            
            print("\n" + "=" * 80)
            print("💡 Testing Instructions:")
            print("   1. Open each URL in separate browser windows/tabs")
            print("   2. Allow camera/microphone permissions")
            print("   3. All users should appear in the meeting")
            print("=" * 80)
            
        except Exception as e:
            print(f"❌ Error generating tokens: {e}")
            sys.exit(1)
    else:
        # Single user mode
        user_id = sys.argv[2] if len(sys.argv) > 2 and not sys.argv[2].startswith("--") else None
        display_name = sys.argv[3] if len(sys.argv) > 3 and not sys.argv[3].startswith("--") else None
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

