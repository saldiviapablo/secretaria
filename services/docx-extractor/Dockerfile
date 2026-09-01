FROM python:3.11-slim

# Create unprivileged user
RUN groupadd -g 10001 appgroup && \
    useradd -u 10001 -g appgroup -s /sbin/nologin -d /app appuser

WORKDIR /app

# Copy dependency definition
COPY requirements.txt .

# Install dependencies in system python without cache
RUN pip install --no-cache-dir -r requirements.txt

# Copy application source code
COPY app/ ./app/

# Set ownership
RUN chown -R appuser:appgroup /app

USER appuser

EXPOSE 8080

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080", "--no-access-log"]
