"""Stripe payment integration for Clozr subscriptions."""

import os
import logging
import stripe
from fastapi import APIRouter, HTTPException, Request, Depends
from pydantic import BaseModel
from typing import Optional
from sqlalchemy.orm import Session

router = APIRouter(prefix="/api/payments", tags=["payments"])

# Stripe configuration
STRIPE_SECRET_KEY = os.getenv("STRIPE_SECRET_KEY", "")
STRIPE_WEBHOOK_SECRET = os.getenv("STRIPE_WEBHOOK_SECRET", "")
APP_URL = os.getenv("APP_URL", "https://clozr.brandbooststudio.co")

if STRIPE_SECRET_KEY:
    stripe.api_key = STRIPE_SECRET_KEY

# Price IDs (created in Stripe dashboard)
PRICES = {
    "pro_monthly": os.getenv("STRIPE_PRICE_PRO_MONTHLY", "price_1TehBuH5RfM228JPbqIR1jrd"),
    "pro_annual": os.getenv("STRIPE_PRICE_PRO_ANNUAL", "price_1TehBvH5RfM228JPyeCigCmI"),
    "business_monthly": os.getenv("STRIPE_PRICE_BUSINESS_MONTHLY", "price_1TehBvH5RfM228JPvv80VCLO"),
    "business_annual": os.getenv("STRIPE_PRICE_BUSINESS_ANNUAL", "price_1TehBvH5RfM228JPqf44feFC"),
    "selfhosted_monthly": os.getenv("STRIPE_PRICE_SELFHOSTED_MONTHLY", "price_1TehBwH5RfM228JPiDh2SEVI"),
    "selfhosted_annual": os.getenv("STRIPE_PRICE_SELFHOSTED_ANNUAL", "price_1TehBwH5RfM228JPGqgdKh2M"),
}

# Tier definitions
TIERS = {
    "free": {
        "name": "Free",
        "price_monthly": 0,
        "price_annual": 0,
        "meetings_per_month": 5,
        "max_meeting_minutes": 60,
        "proposals_per_month": 2,
        "followups_per_month": 3,
        "storage_days": 7,
        "diarization": True,
        "templates": 0,
        "seats": 1,
        "self_hosted": False,
        "crm_integrations": False,
        "custom_branding": False,
    },
    "pro": {
        "name": "Pro",
        "price_monthly": 19,
        "price_annual": 180,
        "meetings_per_month": -1,
        "max_meeting_minutes": -1,
        "proposals_per_month": -1,
        "followups_per_month": -1,
        "storage_days": 365,
        "diarization": True,
        "templates": 10,
        "seats": 1,
        "self_hosted": False,
        "crm_integrations": True,
        "custom_branding": False,
    },
    "business": {
        "name": "Business",
        "price_monthly": 39,
        "price_annual": 384,
        "meetings_per_month": -1,
        "max_meeting_minutes": -1,
        "proposals_per_month": -1,
        "followups_per_month": -1,
        "storage_days": 1095,
        "diarization": True,
        "templates": -1,
        "seats": 5,
        "self_hosted": False,
        "crm_integrations": True,
        "custom_branding": True,
    },
    "selfhosted": {
        "name": "Self-Hosted",
        "price_monthly": 79,
        "price_annual": 780,
        "meetings_per_month": -1,
        "max_meeting_minutes": -1,
        "proposals_per_month": -1,
        "followups_per_month": -1,
        "storage_days": -1,
        "diarization": True,
        "templates": -1,
        "seats": 20,
        "self_hosted": True,
        "crm_integrations": True,
        "custom_branding": True,
    },
}


class CheckoutRequest(BaseModel):
    price_key: str
    email: Optional[str] = None
    # account_id removed — now comes from JWT auth (CRITICAL-NEW-3)


class PortalRequest(BaseModel):
    pass  # account_id comes from JWT auth now


@router.get("/tiers")
async def get_tiers():
    """Return all pricing tiers with feature details."""
    return {
        "tiers": TIERS,
        "prices": PRICES,
    }


@router.post("/checkout")
async def create_checkout_session(
    req: CheckoutRequest,
    account_id: str = Depends(verify_token),  # CRITICAL-NEW-3: Auth required
):
    """Create a Stripe Checkout session for subscription signup."""
    if not STRIPE_SECRET_KEY:
        raise HTTPException(status_code=500, detail="Stripe not configured")

    price_id = PRICES.get(req.price_key)
    if not price_id:
        raise HTTPException(status_code=400, detail=f"Invalid price key: {req.price_key}")

    try:
        session = stripe.checkout.Session.create(
            mode="subscription",
            payment_method_types=["card"],
            line_items=[{
                "price": price_id,
                "quantity": 1,
            }],
            success_url=f"{APP_URL}/pricing?success=true&session_id={{CHECKOUT_SESSION_ID}}",
            cancel_url=f"{APP_URL}/pricing?canceled=true",
            client_reference_id=account_id,  # From JWT, not request body
            customer_email=req.email,
            metadata={
                "account_id": account_id,  # From JWT, not request body
                "tier": req.price_key.split("_")[0],
            },
            allow_promotion_codes=True,
            subscription_data={
                "metadata": {
                    "account_id": account_id,
                },
            },
        )
        return {"url": session.url, "session_id": session.id}
    except stripe.error.StripeError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/portal")
async def create_portal_session(
    req: PortalRequest,
    account_id: str = Depends(verify_token),  # CRITICAL-NEW-3: Auth required
):
    """Create a Stripe Customer Portal session for subscription management."""
    if not STRIPE_SECRET_KEY:
        raise HTTPException(status_code=500, detail="Stripe not configured")

    # Use SQLAlchemy instead of raw sqlite3
    from main import SessionLocal, Account
    db = SessionLocal()
    try:
        account = db.query(Account).filter(Account.id == account_id).first()  # JWT-verified
        if not account or not account.stripe_customer_id:
            raise HTTPException(status_code=404, detail="No Stripe customer found for this account")

        try:
            session = stripe.billing_portal.Session.create(
                customer=account.stripe_customer_id,
                return_url=f"{APP_URL}/settings",
            )
            return {"url": session.url}
        except stripe.error.StripeError as e:
            raise HTTPException(status_code=400, detail=str(e))
    finally:
        db.close()


@router.post("/webhook")
async def stripe_webhook(request: Request):
    """Handle Stripe webhook events with idempotency (CRITICAL-NEW-2)."""
    if not STRIPE_WEBHOOK_SECRET:
        raise HTTPException(status_code=500, detail="Webhook secret not configured")

    payload = await request.body()
    sig_header = request.headers.get("stripe-signature", "")

    try:
        event = stripe.Webhook.construct_event(
            payload, sig_header, STRIPE_WEBHOOK_SECRET
        )
    except stripe.error.SignatureVerificationError:
        raise HTTPException(status_code=400, detail="Invalid signature")

    # CRITICAL-NEW-2: Idempotency check — skip already-processed events
    from main import SessionLocal, Account, WebhookEvent
    db = SessionLocal()
    try:
        event_id = event["id"]
        existing = db.query(WebhookEvent).filter(WebhookEvent.id == event_id).first()
        if existing:
            logging.info(f"Skipping duplicate webhook event: {event_id}")
            return {"received": True, "duplicate": True}
        db.add(WebhookEvent(id=event_id))
        db.commit()
    except Exception:
        db.rollback()
        # If we can't check idempotency, continue processing (fail open)
        pass

    # Handle events
    event_type = event["type"]
    data = event["data"]["object"]

    try:
        if event_type == "checkout.session.completed":
            account_id = data.get("client_reference_id") or data.get("metadata", {}).get("account_id")
            customer_id = data.get("customer")
            subscription_id = data.get("subscription")

            # Get subscription details
            subscription = stripe.Subscription.retrieve(subscription_id)
            price_id = subscription["items"]["data"][0]["price"]["id"]

            # Determine tier from price
            tier = "free"
            for key, pid in PRICES.items():
                if pid == price_id:
                    tier = key.split("_")[0]
                    break

            account = db.query(Account).filter(Account.id == account_id).first()
            if account:
                account.tier = tier
                account.stripe_customer_id = customer_id
                account.stripe_subscription_id = subscription_id
                account.subscription_status = "active"
                db.commit()
                logging.info(f"Stripe checkout complete: account={account_id} tier={tier}")

        elif event_type == "customer.subscription.updated":
            subscription_id = data.get("id")
            price_id = data["items"]["data"][0]["price"]["id"]

            tier = "free"
            for key, pid in PRICES.items():
                if pid == price_id:
                    tier = key.split("_")[0]
                    break

            account = db.query(Account).filter(
                Account.stripe_subscription_id == subscription_id
            ).first()
            if account:
                account.tier = tier
                account.subscription_status = data.get("status")
                db.commit()

        elif event_type == "customer.subscription.deleted":
            subscription_id = data.get("id")
            account = db.query(Account).filter(
                Account.stripe_subscription_id == subscription_id
            ).first()
            if account:
                account.tier = "free"
                account.subscription_status = "canceled"
                db.commit()

        elif event_type == "invoice.payment_failed":
            # Payment failed - notify but don't downgrade yet
            customer_id = data.get("customer")
            logging.warning(f"Stripe payment failed for customer={customer_id}")

    finally:
        db.close()

    return {"received": True}


@router.get("/subscription")
async def get_subscription(
    account_id: str = Depends(verify_token),  # CRITICAL-NEW-3: Auth required
):
    """Get the current subscription status for the authenticated account."""
    from main import SessionLocal, Account
    db = SessionLocal()
    try:
        account = db.query(Account).filter(Account.id == account_id).first()
        if not account:
            raise HTTPException(status_code=404, detail="Account not found")

        tier_info = TIERS.get(account.tier, TIERS["free"])

        return {
            "account_id": account_id,
            "tier": account.tier or "free",
            "tier_name": tier_info["name"],
            "status": account.subscription_status or "active",
            "features": tier_info,
            # Don't expose Stripe IDs to frontend (security)
        }
    finally:
        db.close()