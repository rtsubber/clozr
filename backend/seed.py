#!/usr/bin/env python3
"""Seed the Clozr database with a default account and BrandBoost catalog"""

import sys
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from main import SessionLocal, Account, ServiceCatalogItem, hash_password
import uuid

def seed():
    db = SessionLocal()
    
    # Create default account
    email = os.environ.get("CLOZR_ADMIN_EMAIL", "ron@brandbooststudio.co")
    password = os.environ.get("CLOZR_ADMIN_PASSWORD")
    if not password:
        import secrets
        password = secrets.token_urlsafe(16)
        print(f"⚠️  No CLOZR_ADMIN_PASSWORD set. Generated random password.")
        print(f"⚠️  Save this password — it won't be shown again:")
        print(f"    {password}")
    
    existing = db.query(Account).filter(Account.email == email).first()
    if existing:
        print(f"Account already exists: {email} (id: {existing.id})")
        account = existing
    else:
        account = Account(
            id=str(uuid.uuid4()),
            email=email,
            password_hash=hash_password(password),
            name="Ron Sublett",
            company="BrandBoost Studio",
            brand_name="The Clozr",
            brand_color="#6C5CE7",
            accent_color="#00D2D3",
        )
        db.add(account)
        db.commit()
        db.refresh(account)
        print(f"✅ Created account: {email} (id: {account.id})")
    
    # Seed BrandBoost catalog defaults
    defaults = [
        ("review_monitoring", "Review Monitoring & Response", "Reputation Management",
         "Monitor Google/Yelp/Facebook reviews daily and auto-respond",
         "Local-Eye + Agent Monitor watches for new reviews, generates AI responses for approval, posts after confirmation",
         "45 min/day", "$299", "star"),
        ("social_posting", "Social Media Auto-Posting", "Social Media",
         "Automated social media content creation and scheduling",
         "AI generates captions from product data, schedules posts across Facebook/TikTok/YouTube",
         "30 min/day", "$199", "phone_android"),
        ("seo_monitoring", "SEO & Competitor Monitoring", "SEO & Marketing",
         "Track competitor changes and SEO performance weekly",
         "SEO Agent monitors rankings, competitor activity, and content opportunities automatically",
         "2 hrs/week", "$249", "search"),
        ("inventory_sync", "Inventory & Order Sync", "E-Commerce",
         "Automatically sync inventory between suppliers and store",
         "Scheduled sync between Zendrop/CJ Dropshipping and Shopify, with stock alerts",
         "30 min/day", "$149", "inventory"),
        ("daily_reporting", "Automated Daily Reports", "Reporting",
         "Generate and send daily performance reports",
         "n8n workflow collects data from all sources, generates formatted report, emails at scheduled time",
         "20 min/day", "$149", "bar_chart"),
        ("email_templating", "Smart Email Responses", "Communication",
         "Auto-draft responses to common customer emails",
         "AI categorizes incoming emails, drafts responses using business context, queues for approval",
         "25 min/day", "$149", "email"),
        ("appointment_booking", "Appointment Booking Automation", "Scheduling",
         "Auto-schedule and confirm appointments via phone or web",
         "Maya AI answers calls, books appointments, sends confirmations via SMS/email",
         "1 hr/day", "$399", "calendar_today"),
        ("lead_followup", "Lead Follow-Up Sequences", "Sales",
         "Automated follow-up emails and calls for new leads",
         "New leads trigger personalized email sequence + Maya AI follow-up calls",
         "45 min/day", "$299", "track_changes"),
    ]
    
    for item_id, name, category, desc, automation, time_saved, cost, icon in defaults:
        existing_item = db.query(ServiceCatalogItem).filter(
            ServiceCatalogItem.id == item_id,
            ServiceCatalogItem.account_id == account.id,
        ).first()
        if not existing_item:
            item = ServiceCatalogItem(
                id=item_id,
                account_id=account.id,
                name=name,
                category=category,
                description=desc,
                automation=automation,
                time_saved=time_saved,
                monthly_cost=cost,
                icon=icon,
            )
            db.add(item)
    
    db.commit()
    print(f"✅ Catalog seeded with {len(defaults)} services")
    print(f"\nLogin: {email}")
    print(f"Password: {password}")
    print(f"Account ID: {account.id}")
    
    db.close()


if __name__ == "__main__":
    seed()