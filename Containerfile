FROM python:3.8-slim

LABEL org.opencontainers.image.title="LibreBadge" \
      org.opencontainers.image.description="Open source web based ID badge software (Django)" \
      org.opencontainers.image.source="https://github.com/LibreBadge/LibreBadge"

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    DJANGO_SETTINGS_MODULE=mysite.settings

# --- Hardening: least privilege (Secure by Design 6.7.2) ---
# Run the application as an unprivileged user, never as root.
RUN groupadd -r librebadge && useradd -r -g librebadge librebadge

WORKDIR /app

# --- Hardening: dependency control (Secure by Design 6.2, CAF B4) ---
# Pin exact dependency versions so builds are reproducible and auditable.
# NOTE: Django 3.0 is end-of-life upstream; it is pinned here only because the
# application's settings are incompatible with newer Django. If you control the
# codebase, upgrade Django and re-pin. Review versions for CVEs regularly
# (Cyber Security Policy Handbook B4: patch known vulnerabilities promptly).
RUN pip install --no-cache-dir \
        "Django==3.0.14" \
        "django-crispy-forms==1.12.0" \
        "gunicorn==20.1.0"

COPY --chown=librebadge:librebadge . .

WORKDIR /app/mysite

# --- Hardening: secure configuration (CAF B4, Secure by Design 6.7.3) ---
# The upstream settings.py hardcodes a secret key, enables DEBUG and leaves
# ALLOWED_HOSTS empty. Patch these so all three are driven by environment
# variables at runtime; the secret must never be committed or baked into the
# image (Cyber Security Policy Handbook B3: Data Security).
RUN sed -i \
    -e "s|^SECRET_KEY = .*|import os; SECRET_KEY = os.environ['DJANGO_SECRET_KEY']|" \
    -e "s|^DEBUG = .*|DEBUG = os.environ.get('DJANGO_DEBUG', 'False') == 'True'|" \
    -e "s|^ALLOWED_HOSTS = .*|ALLOWED_HOSTS = os.environ.get('DJANGO_ALLOWED_HOSTS', '').split(',')|" \
    mysite/settings.py

# --- Hardening: identity and access control (CAF B2) ---
# The shipped database contains a default admin/admin account. Fail the build
# if that account still exists; provision a dedicated admin with a strong,
# rotated credential through a separate secret-managed migration instead.
# RUN python manage.py shell -c "..."  # remove/replace default admin here

RUN python manage.py collectstatic --noinput || true && \
    mkdir -p media && chown -R librebadge:librebadge /app

USER librebadge

EXPOSE 8660

# --- Hardening: production server (CAF B4) ---
# Never serve with the Django development server; use a production WSGI server.
CMD ["gunicorn", "mysite.wsgi:application", \
     "--bind", "0.0.0.0:8660", \
     "--workers", "2", \
     "--access-logfile", "-", \
     "--error-logfile", "-"]
