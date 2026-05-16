# TLS certificates

Place your certificate files here (not committed to git):

| File | Description |
|------|-------------|
| `fullchain.pem` | Certificate + chain |
| `privkey.pem` | Private key |

Apache reads these paths (see `apache/vhosts/odoo.conf`).

---

## Option A — Cloudflare Origin Certificate (no Certbot)

Use when DNS is proxied through Cloudflare and SSL mode is **Full (strict)**.

1. Cloudflare dashboard → **SSL/TLS** → **Origin Server** → Create certificate.  
2. Copy certificate → `certs/fullchain.pem`  
3. Copy private key → `certs/privkey.pem`  
4. `chmod 600 certs/privkey.pem`  
5. `make prod` (or `docker compose restart apache`)

Do **not** use **Flexible** SSL (HTTP to your VPS) for production Odoo.

---

## Option B — Let's Encrypt with Certbot (on the VPS)

**Let's Encrypt (on the host):**

```bash
certbot certonly --standalone -d odoo.example.com
cp /etc/letsencrypt/live/odoo.example.com/fullchain.pem ./certs/
cp /etc/letsencrypt/live/odoo.example.com/privkey.pem ./certs/
chmod 600 ./certs/privkey.pem
docker compose restart apache
```

For local testing only, you can generate a self-signed cert:

```bash
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout certs/privkey.pem -out certs/fullchain.pem \
  -subj "/CN=localhost"
```
