# 🎬 BookMyShow Clone — Django Full-Stack Project

A production-ready movie ticket booking system built with Python Django, implementing all 6 internship tasks.

---

## 🚀 Quick Start

```bash
# Clone / extract the project
cd bookmyshow

# Run setup (creates venv, installs deps, migrates, seeds data)
bash setup.sh

# Start server
source venv/bin/activate
python manage.py runserver
```

Open **http://127.0.0.1:8000**

### Login Credentials
| Role | Username | Password |
|------|----------|----------|
| Admin | `admin` | `Admin@1234` |
| User | `testuser` | `Test@1234` |

---

## 📋 Task Implementation Details

### ✅ Task 1 — Scalable Genre & Language Filtering with Query Optimization
**File:** `movies/views.py` → `MovieListView`

**Implemented:**
- Multi-select genre AND language filters via `?genre=action&genre=comedy&language=ta`
- Server-side filtering using `__in` + `.distinct()` — prevents Cartesian product
- Database-level aggregation for filter counts (no in-memory counting)
- Dynamic faceted counts: genre counts update after language filter is applied, and vice versa
- Composite database indexes on `genres__slug`, `languages__code`, `is_active`
- Pagination works seamlessly with all filter combinations
- Sort by: release date, title, rating — all compatible with filters
- AJAX endpoint `/api/filter-counts/` for live count updates

**Query Strategy:**
```python
# Uses indexed M2M lookup — no full-table scan
qs = Movie.objects.filter(is_active=True)
    .filter(genres__slug__in=genre_slugs).distinct()
    .filter(languages__code__in=lang_codes).distinct()

# DB aggregation for counts
Genre.objects.filter(movies__in=base)
    .annotate(count=Count('movies', distinct=True))
    .values('slug', 'name', 'count')
```

---

### ✅ Task 2 — Automated Ticket Email Confirmation with Template Engine
**Files:** `bookings/tasks.py`, `templates/emails/`

**Implemented:**
- Django template engine renders HTML + plain-text emails
- Celery background queue — email does NOT block booking API response
- Retry logic: up to 3 retries with exponential backoff (60s, 120s, 180s)
- `EmailLog` model tracks every delivery attempt with status and error messages
- `retry_failed_emails` Celery Beat task re-queues failed emails every 5 min
- SMTP integration via Django's `EmailMultiAlternatives`
- Email contains: booking ID, seat numbers, theater info, show timing, payment ID
- No sensitive data (passwords, card info) in emails

**Email Flow:**
```
Payment Verified → send_booking_confirmation_email.delay(booking_id) → Celery Queue → SMTP
                                                                            ↓ (on fail)
                                                                    Retry (max 3x, backoff)
                                                                            ↓
                                                                    EmailLog.status = 'failed'
```

---

### ✅ Task 3 — Secure YouTube Trailer Embedding with Performance Controls
**Files:** `movies/models.py` → `Movie.save()`, `templates/movies/movie_detail.html`

**Implemented:**
- URL validation via regex — only valid YouTube URLs accepted (`youtube.com/watch?v=`, `youtu.be/`)
- Uses `youtube-nocookie.com` embed URL — prevents cross-site tracking
- `sandbox="allow-scripts allow-same-origin allow-presentation"` on iframe
- **Lazy loading**: iframe `src` is NOT set on page load — only injected on click
- `bleach.clean()` sanitizes movie descriptions against XSS
- JavaScript whitelist check blocks non-YouTube iframes
- Graceful fallback: if trailer URL is invalid, shows external link instead
- `rel=0&modestbranding=1` parameters in embed URL

---

### ✅ Task 4 — Payment Gateway Integration with Idempotency & Webhook Security
**Files:** `payments/views.py`, `payments/models.py`

**Implemented:**
- Razorpay integration with server-side order creation
- **HMAC-SHA256 signature verification** — does NOT trust frontend callback alone
- Idempotency key stored per booking — prevents duplicate orders on retry
- `WebhookEvent` model stores raw events with `event_id` — duplicate webhooks are skipped
- Handles: `payment.captured`, `payment.failed` webhook events
- Payment timeout: expired seat holds are released on `payment.failed`
- Webhook signature validated using `hmac.compare_digest` (timing-safe)
- Payment lifecycle: `created → pending → success/failed`
- Partial failure handling: booking remains `pending` until webhook confirms

**Payment Lifecycle:**
```
User → /payments/create-order/ → Razorpay order → Frontend checkout
     → User pays → Razorpay callback → /payments/verify/ (HMAC check)
     → Booking confirmed → Email queued
     → Razorpay Webhook → /payments/webhook/razorpay/ (idempotency check)
```

---

### ✅ Task 5 — Concurrency-Safe Seat Reservation with Auto Timeout
**Files:** `bookings/views.py` → `reserve_seats`, `bookings/tasks.py` → `release_expired_reservations`

**Implemented:**
- `select_for_update()` acquires row-level DB lock — prevents race conditions
- `unique_together = ['showtime', 'seat']` enforces DB-level uniqueness
- 2-minute hold with `expires_at` timestamp
- Atomic transaction wraps the entire reservation check + create
- Conflict detection returns specific conflicting seat info
- Celery Beat task runs every 1 minute to release expired holds
- Edge cases handled:
  - User closes app → timer expires → auto-release
  - Network interruption → no partial reservation
  - Multiple devices → first committer wins (DB lock)
  - Re-selecting seats releases old holds first

**Race Condition Prevention:**
```python
with transaction.atomic():
    seats = Seat.objects.select_for_update()  # row-level lock
        .filter(id__in=seat_ids)
    conflict = SeatReservation.objects.filter(
        status__in=['held', 'confirmed'],
        expires_at__gt=timezone.now()
    ).exclude(user=request.user).select_for_update()
    if conflict.exists():
        return JsonResponse({'error': 'Seats taken'}, 409)
    SeatReservation.objects.bulk_create(reservations)
```

---

### ✅ Task 6 — Advanced Admin Analytics Dashboard with Aggregation Optimization
**Files:** `analytics/views.py`, `templates/admin_dashboard/dashboard.html`

**Implemented:**
- Role-based access: only users with `role='admin'` or `is_superuser` can access
- Revenue analytics: daily / weekly / monthly using `TruncDay/Week/Month`
- Most popular movies by booking count (DB aggregation via `Count`)
- Busiest theaters by occupancy rate
- Peak booking hours using `ExtractHour`
- Cancellation rate calculation at DB level
- Redis caching (`django-redis`) for all heavy queries — 5 min TTL
- **No full datasets loaded into memory** — all aggregation at DB level
- Interactive charts via Chart.js (line + bar)
- Admin credentials: `admin` / `Admin@1234` (hashed with PBKDF2)
- Session-based authentication with Django's built-in protection

**Caching Strategy:**
```python
data = cache.get('analytics_revenue_daily')
if not data:
    data = Booking.objects.filter(status='confirmed')
        .annotate(day=TruncDay('created_at'))
        .values('day').annotate(revenue=Sum('total_amount'))
    cache.set('analytics_revenue_daily', data, 300)
```

---

## 🗂️ Project Structure

```
bookmyshow/
├── bookmyshow/          # Django project config
│   ├── settings.py      # All settings
│   ├── urls.py          # Root URL config
│   └── celery.py        # Celery config
├── movies/              # Movie catalog, genres, languages, theaters
├── bookings/            # Seat selection, reservations, booking history
├── payments/            # Razorpay integration, webhooks
├── accounts/            # Custom user model, auth
├── analytics/           # Admin dashboard with charts
├── templates/           # All HTML templates
│   ├── base.html
│   ├── movies/
│   ├── bookings/
│   ├── payments/
│   ├── accounts/
│   ├── admin_dashboard/
│   └── emails/          # Email templates (HTML + TXT)
├── static/              # CSS, JS, images
├── requirements.txt
├── setup.sh             # One-click setup script
└── manage.py
```

---

## ⚙️ Configuration

Edit `.env` file:

```env
SECRET_KEY=your-secret-key
DEBUG=True
REDIS_URL=redis://localhost:6379/0
EMAIL_BACKEND=django.core.mail.backends.smtp.EmailBackend
EMAIL_HOST_USER=your@gmail.com
EMAIL_HOST_PASSWORD=your-app-password
RAZORPAY_KEY_ID=rzp_test_...
RAZORPAY_KEY_SECRET=...
```

---

## 🔧 Running Background Workers

```bash
# Terminal 1: Redis
redis-server

# Terminal 2: Celery worker (emails, etc.)
celery -A bookmyshow worker -l info

# Terminal 3: Celery beat (scheduled tasks — seat release, email retry)
celery -A bookmyshow beat -l info --scheduler django_celery_beat.schedulers:DatabaseScheduler

# Terminal 4: Django dev server
python manage.py runserver
```

---

## 🛡️ Security Features

| Feature | Implementation |
|--------|----------------|
| XSS Prevention | `bleach.clean()` on descriptions, iframe sandbox |
| CSRF Protection | Django middleware + token in all forms |
| SQL Injection | Django ORM (parameterized queries only) |
| Payment Fraud | HMAC-SHA256 signature verification |
| Replay Attacks | Webhook idempotency via `WebhookEvent.event_id` |
| Race Conditions | `select_for_update()` + atomic transactions |
| Password Security | Django PBKDF2 hashing |
| Role Isolation | Custom `admin_required` decorator |
| Sensitive Data | Payment IDs never exposed in frontend JS |

---

## 📦 Tech Stack

- **Backend**: Python 3.10+, Django 4.2
- **Database**: SQLite (dev) / PostgreSQL (prod)
- **Cache/Queue**: Redis + Celery + Celery Beat
- **Email**: Django + SMTP / Console backend
- **Payments**: Razorpay
- **Frontend**: Vanilla HTML/CSS/JS + Chart.js
- **Static**: WhiteNoise
- **Security**: bleach, HMAC, Django's built-in security middleware
