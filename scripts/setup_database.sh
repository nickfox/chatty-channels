#!/bin/bash

# setup_database.sh
# Quick setup script for PostgreSQL database

set -e

echo "=== Chatty Channels Database Setup ==="
echo ""

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo "❌ Docker not found. Please install Docker first:"
    echo "   https://docs.docker.com/desktop/install/mac-install/"
    exit 1
fi

echo "✓ Docker is installed"

# Check if docker-compose is available
if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
    echo "❌ docker-compose not found. Please install docker-compose first."
    exit 1
fi

echo "✓ docker-compose is available"

# Navigate to database directory
cd "$(dirname "$0")/../database"

echo ""
echo "Starting PostgreSQL with pgvector..."
docker-compose up -d

echo ""
echo "Waiting for PostgreSQL to be ready..."
sleep 5

# Check if PostgreSQL is running
if docker ps | grep -q chatty-channels-db; then
    echo "✓ PostgreSQL is running"
else
    echo "❌ PostgreSQL failed to start. Check logs with:"
    echo "   docker logs chatty-channels-db"
    exit 1
fi

# Verify database is initialized
echo ""
echo "Verifying database schema..."
if docker exec chatty-channels-db psql -U postgres -d chatty_channels -c "SELECT COUNT(*) FROM projects;" &> /dev/null; then
    echo "✓ Database schema is initialized"
else
    echo "⚠️  Database schema may not be fully initialized"
    echo "   Check logs with: docker logs chatty-channels-db"
fi

echo ""
echo "=== Setup Complete ==="
echo ""
echo "PostgreSQL is running at: localhost:5432"
echo "Database: chatty_channels"
echo "Username: postgres"
echo "Password: postgres"
echo ""
echo "To connect: docker exec -it chatty-channels-db psql -U postgres -d chatty_channels"
echo "To view logs: docker logs chatty-channels-db"
echo "To stop: docker-compose down"
echo ""

# Check if Ollama is installed
echo "Checking for Ollama (for embeddings)..."
if command -v ollama &> /dev/null; then
    echo "✓ Ollama is installed"

    # Check if nomic-embed-text is available
    if ollama list | grep -q nomic-embed-text; then
        echo "✓ nomic-embed-text model is installed"
    else
        echo "⚠️  nomic-embed-text model not found"
        echo "   Install with: ollama pull nomic-embed-text:latest"
    fi
else
    echo "⚠️  Ollama not found (optional, for embeddings)"
    echo "   Install with: brew install ollama"
    echo "   Then run: ollama pull nomic-embed-text:latest"
fi

echo ""
echo "Next steps:"
echo "1. Add PostgresNIO package to Xcode project (see docs/POSTGRESQL_MIGRATION.md)"
echo "2. Build and run the ChattyChannels app"
echo "3. The database will be automatically initialized on first run"
echo ""
