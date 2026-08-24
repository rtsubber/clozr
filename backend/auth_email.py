"""Password reset + email verification for Clozr.

Uses Resend for email delivery.
Token-based flow: generate token → email link → verify token → update password/email.

Security:
- Tokens are SHA-256 hashed in DB (never stored plaintext)
- Tokens expire after 1 hour
- Tokens are single-use (deleted after verification)
- Rate-limited: 3 resets per email per hour, 5 verification resends per hour
"""

import os
import hashlib
import secrets
import logging
from datetime import datetime, timezone, timedelta
from email.message import EmailMessage
from typing import Optional

import resend

logger = logging.getLogger(__name__)

# ── Config ──
RESEND_API_KEY = os.getenv("RESEND_API_KEY", "")
EMAIL_FROM = os.getenv("CLOZR_EMAIL_FROM", "Clozr <onboarding@resend.dev>")
APP_URL = os.getenv("APP_URL", "https://clozr.brandbooststudio.co")

# Rate limits
MAX_RESETS_PER_HOUR = 3
MAX_VERIFICATIONS_PER_HOUR = 5
TOKEN_EXPIRY_HOURS = 1

if RESEND_API_KEY:
    resend.api_key = RESEND_API_KEY


def _hash_token(token: str) -> str:
    """SHA-256 hash of token for DB storage."""
    return hashlib.sha256(token.encode()).hexdigest()


def _is_rate_limited(db, model, account_id: str, max_per_hour: int) -> bool:
    """Check if account has exceeded rate limit for given action."""
    one_hour_ago = datetime.now(timezone.utc) - timedelta(hours=1)
    count = db.query(model).filter(
        model.account_id == account_id,
        model.created_at >= one_hour_ago
    ).count()
    return count >= max_per_hour


def generate_reset_token(db, account_id: str) -> str:
    """Generate a password reset token. Returns plaintext token (send to user)."""
    from main import PasswordResetToken
    plaintext = secrets.token_urlsafe(32)
    hashed = _hash_token(plaintext)
    expires = datetime.now(timezone.utc) + timedelta(hours=TOKEN_EXPIRY_HOURS)

    token = PasswordResetToken(
        account_id=account_id,
        token_hash=hashed,
        expires_at=expires,
    )
    db.add(token)
    db.commit()
    return plaintext


def generate_verify_token(db, account_id: str) -> str:
    """Generate an email verification token. Returns plaintext token."""
    from main import EmailVerificationToken
    plaintext = secrets.token_urlsafe(32)
    hashed = _hash_token(plaintext)
    expires = datetime.now(timezone.utc) + timedelta(hours=TOKEN_EXPIRY_HOURS)

    token = EmailVerificationToken(
        account_id=account_id,
        token_hash=hashed,
        expires_at=expires,
    )
    db.add(token)
    db.commit()
    return plaintext


def verify_reset_token(db, plaintext_token: str) -> Optional[str]:
    """Verify a password reset token. Returns account_id if valid, None if invalid/expired."""
    from main import PasswordResetToken
    hashed = _hash_token(plaintext_token)
    now = datetime.now(timezone.utc)

    token = db.query(PasswordResetToken).filter(
        PasswordResetToken.token_hash == hashed,
        PasswordResetToken.expires_at > now,
        PasswordResetToken.used == False,
    ).first()

    if not token:
        return None

    # Mark as used
    token.used = True
    db.commit()
    return token.account_id


def verify_email_token(db, plaintext_token: str) -> Optional[str]:
    """Verify an email verification token. Returns account_id if valid."""
    from main import EmailVerificationToken
    hashed = _hash_token(plaintext_token)
    now = datetime.now(timezone.utc)

    token = db.query(EmailVerificationToken).filter(
        EmailVerificationToken.token_hash == hashed,
        EmailVerificationToken.expires_at > now,
        EmailVerificationToken.used == False,
    ).first()

    if not token:
        return None

    # Mark as used
    token.used = True
    db.commit()
    return token.account_id


def send_password_reset_email(email: str, token: str) -> bool:
    """Send password reset email via Resend."""
    if not RESEND_API_KEY:
        logger.error("RESEND_API_KEY not configured - cannot send email")
        return False

    reset_url = f"{APP_URL}/reset-password?token={token}"

    try:
        resend.Emails.send({
            "from": EMAIL_FROM,
            "to": [email],
            "subject": "Reset your Clozr password",
            "html": f"""
                <div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; max-width: 480px; margin: 0 auto; padding: 40px 20px;">
                    <div style="text-align: center; margin-bottom: 32px;">
                        <h1 style="color: #6C5CE7; font-size: 24px; margin: 0;">Clozr</h1>
                        <p style="color: #8B8BA0; font-size: 14px; margin-top: 4px;">AI that closes deals, not just notes</p>
                    </div>
                    <div style="background: #16161D; border-radius: 12px; padding: 32px; border: 1px solid #2A2A3A;">
                        <h2 style="color: #E0E0F0; font-size: 18px; margin: 0 0 16px;">Reset your password</h2>
                        <p style="color: #8B8BA0; font-size: 14px; line-height: 1.6;">
                            We received a request to reset your password. Click the button below to set a new password.
                            This link expires in 1 hour.
                        </p>
                        <a href="{reset_url}" style="display: inline-block; background: #6C5CE7; color: white; padding: 12px 32px; border-radius: 8px; text-decoration: none; font-weight: 600; margin: 20px 0;">
                            Reset Password
                        </a>
                        <p style="color: #8B8BA0; font-size: 13px; margin-top: 20px;">
                            If you didn't request this, you can safely ignore this email.
                        </p>
                    </div>
                    <p style="color: #8B8BA0; font-size: 12px; text-align: center; margin-top: 24px;">
                        © 2026 Clozr. All rights reserved.
                    </p>
                </div>
            """,
        })
        logger.info(f"Password reset email sent to {email}")
        return True
    except Exception as e:
        logger.error(f"Failed to send password reset email: {e}")
        return False


def send_verification_email(email: str, token: str, name: str = "") -> bool:
    """Send email verification via Resend."""
    if not RESEND_API_KEY:
        logger.error("RESEND_API_KEY not configured - cannot send email")
        return False

    verify_url = f"{APP_URL}/verify-email?token={token}"
    first_name = name.split()[0] if name else "there"

    try:
        resend.Emails.send({
            "from": EMAIL_FROM,
            "to": [email],
            "subject": "Welcome to Clozr — verify your email",
            "html": f"""
                <div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; max-width: 480px; margin: 0 auto; padding: 40px 20px;">
                    <div style="text-align: center; margin-bottom: 32px;">
                        <h1 style="color: #6C5CE7; font-size: 24px; margin: 0;">Clozr</h1>
                        <p style="color: #8B8BA0; font-size: 14px; margin-top: 4px;">AI that closes deals, not just notes</p>
                    </div>
                    <div style="background: #16161D; border-radius: 12px; padding: 32px; border: 1px solid #2A2A3A;">
                        <h2 style="color: #E0E0F0; font-size: 18px; margin: 0 0 16px;">Hey {first_name} 👋</h2>
                        <p style="color: #8B8BA0; font-size: 14px; line-height: 1.6;">
                            Welcome to Clozr! Verify your email to get started with AI-powered meeting proposals.
                        </p>
                        <a href="{verify_url}" style="display: inline-block; background: #6C5CE7; color: white; padding: 12px 32px; border-radius: 8px; text-decoration: none; font-weight: 600; margin: 20px 0;">
                            Verify Email
                        </a>
                        <p style="color: #8B8BA0; font-size: 13px; margin-top: 20px;">
                            This link expires in 1 hour. If you didn't create an account, you can ignore this email.
                        </p>
                    </div>
                    <div style="background: #16161D; border-radius: 12px; padding: 24px; border: 1px solid #2A2A3A; margin-top: 16px;">
                        <h3 style="color: #E0E0F0; font-size: 14px; margin: 0 0 12px;">What's next?</h3>
                        <ul style="color: #8B8BA0; font-size: 13px; line-height: 2; padding-left: 20px; margin: 0;">
                            <li>Add your services to the catalog</li>
                            <li>Record your first meeting</li>
                            <li>Get an AI-generated proposal in seconds</li>
                        </ul>
                    </div>
                    <p style="color: #8B8BA0; font-size: 12px; text-align: center; margin-top: 24px;">
                        © 2026 Clozr. All rights reserved.
                    </p>
                </div>
            """,
        })
        logger.info(f"Verification email sent to {email}")
        return True
    except Exception as e:
        logger.error(f"Failed to send verification email: {e}")
        return False
