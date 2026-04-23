# Kiro Gateway - Docker Image
# Optimized single-stage build with uv

FROM python:3.10-slim

# Set environment variables
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

# Create non-root user for security
RUN groupadd -r kiro && useradd -r -g kiro kiro

# Install uv
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /usr/local/bin/

# Set working directory
WORKDIR /app

# Install dependencies first (better layer caching)
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev --no-install-project

# Copy application code
COPY --chown=kiro:kiro . .

# Install the project itself
RUN uv sync --frozen --no-dev

# Create directory for debug logs with proper permissions
RUN mkdir -p debug_logs && chown -R kiro:kiro debug_logs

# Switch to non-root user
USER kiro

# Expose port
EXPOSE 8000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD uv run python -c "import httpx; httpx.get('http://localhost:8000/health', timeout=5)"

# Run the application
CMD ["uv", "run", "python", "main.py"]
