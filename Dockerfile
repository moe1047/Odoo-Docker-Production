FROM odoo:18.0

USER root

# curl  -> healthchecks
# ghostscript -> optional PDF compression addons (e.g. upload-time compress)
RUN apt-get update \
 && apt-get install -y --no-install-recommends curl ghostscript \
 && rm -rf /var/lib/apt/lists/*

# Optional: Python deps for your custom addons
# COPY requirements.txt /tmp/requirements.txt
# RUN pip3 install --no-cache-dir --break-system-packages -r /tmp/requirements.txt

USER odoo
