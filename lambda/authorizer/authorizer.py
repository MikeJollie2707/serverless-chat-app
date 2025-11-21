import os
import json
import time
import urllib.request
import urllib.error
from typing import Dict, Any

import jwt
from jwt import InvalidTokenError, ExpiredSignatureError
from jwt.utils import base64url_decode
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives import serialization

APP_CLIENT_ID = os.getenv("APP_CLIENT_ID")
JWKS_TTL = int(os.getenv("JWKS_TTL_SECONDS", "3600"))
COGNITO_URL = os.getenv("COGNITO_URL")
JWKS_URL = f"{COGNITO_URL}/.well-known/jwks.json"


# Simple in-process cache for JWKS
_JWKS_CACHE = {"expires_at": 0.0, "keys_by_kid": {}}

def _load_jwks() -> Dict[str, Any]:
    """Fetch JWKS and cache by 'kid'."""
    now = time.time()
    if _JWKS_CACHE["expires_at"] > now and _JWKS_CACHE["keys_by_kid"]:
        return _JWKS_CACHE["keys_by_kid"]

    try:
        with urllib.request.urlopen(JWKS_URL, timeout=5) as resp:
            data = json.loads(resp.read().decode("utf-8"))
    except (urllib.error.URLError, urllib.error.HTTPError) as e:
        # If network fails but we have a warm cache, keep using it
        if _JWKS_CACHE["keys_by_kid"]:
            return _JWKS_CACHE["keys_by_kid"]
        raise RuntimeError(f"Unable to fetch JWKS: {e}")

    keys_by_kid = {k["kid"]: k for k in data.get("keys", [])}
    _JWKS_CACHE["keys_by_kid"] = keys_by_kid
    _JWKS_CACHE["expires_at"] = now + JWKS_TTL
    return keys_by_kid

def _get_public_key_for_token(token: str):
    """Resolve the RSA public key matching the JWT's 'kid'."""
    unverified_header = jwt.get_unverified_header(token)
    kid = unverified_header.get("kid")
    if not kid:
        raise InvalidTokenError("JWT header missing 'kid'")

    jwks = _load_jwks()
    jwk = jwks.get(kid)
    if not jwk:
        # cache miss: force refresh once, then retry
        _JWKS_CACHE["expires_at"] = 0
        jwks = _load_jwks()
        jwk = jwks.get(kid)
        if not jwk:
            raise InvalidTokenError("No matching JWK for token 'kid'")

    return jwk

def _jwk_to_pem(jwk):
    n = int.from_bytes(base64url_decode(jwk['n']), 'big')
    e = int.from_bytes(base64url_decode(jwk['e']), 'big')
    public_key = rsa.RSAPublicNumbers(e, n).public_key()
    return public_key.public_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PublicFormat.SubjectPublicKeyInfo
    )

def _verify_access_token(token: str) -> Dict[str, Any]:
    """Verify signature, issuer, expiration, and Cognito access-token specifics."""
    public_key = _get_public_key_for_token(token)

    # NOTE: access tokens from Cognito typically do NOT include 'aud'; they include 'client_id'.
    claims = jwt.decode(
        token,
        key=_jwk_to_pem(public_key),
        algorithms=["RS256"],
        options={"require": ["exp", "iat", "token_use"], "verify_aud": False},
        issuer=COGNITO_URL,
    )

    # Ensure it's an access token and intended for this app client
    if claims.get("token_use") != "access":
        raise InvalidTokenError("token_use must be 'access'")
    if claims.get("client_id") != APP_CLIENT_ID:
        raise InvalidTokenError("client_id does not match expected app client id")

    return claims

def _generate_policy(principal_id: str, effect: str, method_arn: str, context: Dict[str, Any] = None):
    """Return an IAM policy for API Gateway custom authorizer."""
    policy = {
        "principalId": principal_id,
        "policyDocument": {
            "Version": "2012-10-17",
            "Statement": [{
                "Action": "execute-api:Invoke",
                "Effect": effect,
                "Resource": method_arn
            }]
        },
        "context": {}
    }
    # Only simple string/number/bool values allowed in context
    if context:
        for k, v in context.items():
            if isinstance(v, (str, int, float, bool)) and len(str(v)) <= 1000:
                policy["context"][k] = v
            else:
                policy["context"][k] = str(v)[:1000]
    return policy

def _extract_bearer_token(event: Dict[str, Any]) -> str:
    """Support standard API Gateway TOKEN authorizer: event['authorizationToken'] contains 'Bearer ...'."""
    auth_header = event["queryStringParameters"]["token"]
    return auth_header.strip()

def authorizer(event, context):
    """
    API Gateway REST (Custom) TOKEN authorizer entrypoint.
    Expects event.authorizationToken = 'Bearer <JWT>' and event.methodArn present.
    """
    method_arn = event.get("methodArn", "*")

    try:
        token = _extract_bearer_token(event)
        if not token:
            raise InvalidTokenError("Missing token")

        claims = _verify_access_token(token)

        # Use 'sub' as principalId; include useful claims in context
        principal_id = claims.get("sub", "user")
        ctx = {
            "scope": claims.get("scope", ""),
            "username": claims.get("username", ""),
            "client_id": claims.get("client_id", ""),
            "token_use": claims.get("token_use", ""),
            "exp": int(claims.get("exp", 0)),
        }

        return _generate_policy(principal_id, "Allow", method_arn, ctx)

    except ExpiredSignatureError as e: 
        # Token expired → Deny
        return _generate_policy("anonymous", "Deny", method_arn, {"reason": "token_expired"})
    except InvalidTokenError as e:
        return _generate_policy("anonymous", "Deny", method_arn, {"reason": f"invalid_token: {e}"})
    except Exception as e:
        # Any other error → Deny (don’t leak internals)
        return _generate_policy("anonymous", "Deny", method_arn, {"reason": "error"})