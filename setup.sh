#!/bin/bash
# ============================================================
# BookMyShow Django Project — Quick Setup Script
# ============================================================

set -e

echo ""
echo "🎬 BookMyShow Django Project Setup"
echo "==================================="
echo ""

# Check Python
if ! command -v python3 &>/dev/null; then
    echo "❌ Python 3 not found. Please install Python 3.10+"
    exit 1
fi

# Create virtual environment
if [ ! -d "venv" ]; then
    echo "📦 Creating virtual environment..."
    python3 -m venv venv
fi

# Activate
source venv/bin/activate
echo "✅ Virtual environment activated"

# Install dependencies
echo "📥 Installing dependencies..."
pip install --upgrade pip -q
pip install -r requirements.txt -q
echo "✅ Dependencies installed"

# Copy .env
if [ ! -f ".env" ]; then
    cp .env.example .env
    echo "✅ Created .env from .env.example (edit it with your keys)"
fi

# Run migrations
echo "🗄️  Running migrations..."
python manage.py makemigrations accounts movies bookings payments analytics 2>/dev/null || true
python manage.py migrate --run-syncdb
echo "✅ Migrations done"

# Collect static
echo "🖼️  Collecting static files..."
python manage.py collectstatic --noinput -v 0
echo "✅ Static files collected"

# Seed data
echo "🌱 Seeding demo data..."
python manage.py seed_data
echo "✅ Data seeded"

echo ""
echo "============================================================"
echo "✅ Setup complete! Start the server:"
echo ""
echo "   source venv/bin/activate"
echo "   python manage.py runserver"
echo ""
echo "🌐 Open: http://127.0.0.1:8000"
echo "🔧 Admin: http://127.0.0.1:8000/admin"
echo "📊 Dashboard: http://127.0.0.1:8000/analytics/dashboard/"
echo ""
echo "👤 Login credentials:"
echo "   Admin  → admin / Admin@1234"
echo "   User   → testuser / Test@1234"
echo ""
echo "⚡ For background tasks (email, seat auto-release):"
echo "   Start Redis:  redis-server"
echo "   Start Celery: celery -A bookmyshow worker -l info"
echo "   Start Beat:   celery -A bookmyshow beat -l info"
echo "============================================================"
