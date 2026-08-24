"""Shared auth utilities — breaks circular import between main.py and stripe_payments.py.

main.py sets JWT_SECRET, SessionLocal, and Account on this module at startup,
then both main.py and stripe_payments.py can use verify_token and get_db.
"""
from fastapi import Request, Depends, HTTPException
from jose import jwt, JWTError

# These are set by main.py after engine/SessionLocal are created
JWT_SECRET = ""
SessionLocal = None
Account = None


def get_db():
    if SessionLocal is None:
        raise RuntimeError("auth.get_db called before main.py initialized SessionLocal")
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def verify_token(request: Request, db=Depends(get_db)) -> str:
    """Extract and verify account_id from JWT. Returns account_id or raises 401."""
    auth_header = request.headers.get("Authorization", "")
    if not auth_header.startswith("Bearer "):
        raise HTTPException(401, "Missing or invalid authorization header")
    try:
        payload = jwt.decode(auth_header[7:], JWT_SECRET, algorithms=["HS256"], options={"verify_exp": True})
        account_id = payload.get("sub")
        if not account_id:
            raise HTTPException(401, "Invalid token")
        if Account is None:
            raise RuntimeError("auth.verify_token called before main.py initialized Account")
        account = db.query(Account).filter(Account.id == account_id, Account.is_active == True).first()
        if not account:
            raise HTTPException(401, "Account disabled or not found")
        return account_id
    except JWTError:
        raise HTTPException(401, "Token expired or invalid")